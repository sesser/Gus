import Foundation
import Security
import Synchronization

/// Where a server connection's key is kept (R1): the macOS Keychain in the
/// app, memory in tests and scripted launches. Nothing else ever holds a key:
/// not the catalog, preferences, logs, Activity text or debug-script output.
/// `account` is the connection's `uuid`, never its name or address.
public protocol RemoteKeyStore: Sendable {
    func setKey(_ key: String, account: String) throws(RemoteKeyStoreError)
    /// Nil when there is no key for `account`.
    func key(account: String) throws(RemoteKeyStoreError) -> String?
    /// Deleting a key that is not there is not an error.
    func deleteKey(account: String) throws(RemoteKeyStoreError)
}

/// The Keychain refused (R2's seventh result): the system's own words, which
/// never contain the key.
public struct RemoteKeyStoreError: Error, Equatable, Sendable, CustomStringConvertible {
    public var status: Int32
    public var message: String

    public init(status: Int32, message: String) {
        self.status = status
        self.message = message
    }

    public var description: String { message }

    static func from(_ status: OSStatus) -> RemoteKeyStoreError {
        let text = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return RemoteKeyStoreError(status: status, message: text)
    }
}

/// Generic password items in the login keychain, one per connection, under a
/// service named from the running app's bundle identifier
/// (`<bundle identifier>.servers`). A copy of the app with another
/// identifier (a scripted test copy) has a service of its own, so it never
/// reads the real app's keys; scripted launches use `InMemoryKeyStore`
/// anyway (PRD, library launch guard).
///
/// The file-based keychain, not the data protection keychain: that one needs
/// a keychain-access-groups entitlement, which an ad hoc signature can't
/// carry. Each new build is a new signature, so macOS may ask once whether
/// the build may read an item an older build stored (P5).
public struct KeychainKeyStore: RemoteKeyStore {
    public let service: String

    public init(bundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        service = Self.service(bundleIdentifier: bundleIdentifier)
    }

    public static func service(bundleIdentifier: String?) -> String {
        (bundleIdentifier ?? AppBranding.bundleIdentifier) + ".servers"
    }

    private func query(_ account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    public func setKey(_ key: String, account: String) throws(RemoteKeyStoreError) {
        let data = Data(key.utf8)
        let update: [CFString: Any] = [kSecValueData: data]
        var status = SecItemUpdate(query(account) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(account)
            item[kSecValueData] = data
            item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlocked
            item[kSecAttrLabel] = service
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw .from(status) }
    }

    public func key(account: String) throws(RemoteKeyStoreError) -> String? {
        var item = query(account)
        item[kSecReturnData] = true
        item[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw .from(status) }
        return String(decoding: data, as: UTF8.self)
    }

    public func deleteKey(account: String) throws(RemoteKeyStoreError) {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw .from(status) }
    }
}

/// Keys in memory, for tests and scripted launches. `failing` makes every
/// call throw, as a Keychain that refuses (AC2).
public final class InMemoryKeyStore: RemoteKeyStore {
    private let state = Mutex<(keys: [String: String], failing: Bool)>(([:], false))

    public init() {}

    public var failing: Bool {
        get { state.withLock { $0.failing } }
        set { state.withLock { $0.failing = newValue } }
    }

    public var accounts: [String] { state.withLock { Array($0.keys.keys).sorted() } }

    private static let refusal = RemoteKeyStoreError(status: errSecNotAvailable, message: "The keychain is not available.")

    public func setKey(_ key: String, account: String) throws(RemoteKeyStoreError) {
        try state.withLock { state throws(RemoteKeyStoreError) in
            guard !state.failing else { throw Self.refusal }
            state.keys[account] = key
        }
    }

    public func key(account: String) throws(RemoteKeyStoreError) -> String? {
        try state.withLock { state throws(RemoteKeyStoreError) in
            guard !state.failing else { throw Self.refusal }
            return state.keys[account]
        }
    }

    public func deleteKey(account: String) throws(RemoteKeyStoreError) {
        try state.withLock { state throws(RemoteKeyStoreError) in
            guard !state.failing else { throw Self.refusal }
            state.keys[account] = nil
        }
    }
}
