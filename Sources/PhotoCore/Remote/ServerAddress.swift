import Darwin
import Foundation

/// A server's address as the person typed it, normalized (issue #271, design
/// §3.2): no scheme means `https://`; the scheme and host are lower-cased; a
/// default port (443 for https, 80 for http), a trailing slash and a trailing
/// `/api` are removed; a path prefix (a reverse proxy at `/immich`) and any
/// other port are kept.
///
/// The normalized text is also what a link to a remote photo stores (R16), so
/// two ways of writing one address (`HTTPS://Photos.Example.com:443/`) are the
/// same server, and any other address is another server.
public struct ServerAddress: Hashable, Sendable, CustomStringConvertible {
    public enum Scheme: String, Sendable {
        case https, http
    }

    public enum ParseError: Error, Equatable, Sendable {
        /// Nothing was typed.
        case empty
        /// A scheme other than http or https ("Use an address that starts
        /// with https:// or http://.").
        case unsupportedScheme
        /// Not an address: no host, a user name or password, a query or a
        /// fragment.
        case invalid
    }

    public let scheme: Scheme
    /// Lower-case; an IPv6 literal without its brackets.
    public let host: String
    /// Nil for the scheme's default port.
    public let port: Int?
    /// "" or a path prefix such as "/immich", percent-encoded, with no
    /// trailing slash.
    public let path: String

    /// "https://photos.example.com", "http://192.168.1.5:2283/immich".
    public var description: String {
        var text = "\(scheme.rawValue)://\(hostForURL)"
        if let port { text += ":\(port)" }
        return text + path
    }

    /// The normalized address, as stored in the catalog.
    public var normalized: String { description }

    /// The API's root: the address followed by `/api`.
    public var apiBaseURL: URL {
        // `description` is built from parts URLComponents accepted.
        URL(string: description + "/api")!
    }

    var hostForURL: String { host.contains(":") ? "[\(host)]" : host }

    /// The normalized address of `text`, or why it is not one.
    public static func parse(_ text: String) -> Result<ServerAddress, ParseError> {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        if let range = trimmed.range(of: "://") {
            let scheme = trimmed[..<range.lowerBound].lowercased()
            guard scheme == "http" || scheme == "https" else { return .failure(.unsupportedScheme) }
        } else if trimmed.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:(?!\d)"#, options: .regularExpression) != nil {
            // "ftp:host" or "mailto:…": a scheme without "//", not a host and port.
            return .failure(.unsupportedScheme)
        } else {
            trimmed = "https://" + trimmed
        }
        guard let components = URLComponents(string: trimmed),
              let schemeText = components.scheme?.lowercased(), let scheme = Scheme(rawValue: schemeText),
              var host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil
        else { return .failure(.invalid) }
        host = host.lowercased()
        if host.hasPrefix("[") && host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if host.hasSuffix("."), host.count > 1 { host.removeLast() }
        guard !host.isEmpty, !host.contains(where: { $0.isWhitespace || $0 == "/" || $0 == "@" }) else {
            return .failure(.invalid)
        }
        var port = components.port
        if let value = port {
            guard (1...65535).contains(value) else { return .failure(.invalid) }
            if (scheme == .https && value == 443) || (scheme == .http && value == 80) { port = nil }
        }
        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        if path.lowercased().hasSuffix("/api") { path.removeLast(4) }
        while path.hasSuffix("/") { path.removeLast() }
        return .success(ServerAddress(scheme: scheme, host: host, port: port, path: path))
    }

    /// Normalizes an address already stored (it was normalized when saved).
    public init?(normalized text: String) {
        guard case .success(let address) = Self.parse(text) else { return nil }
        self = address
    }

    init(scheme: Scheme, host: String, port: Int?, path: String) {
        self.scheme = scheme
        self.host = host
        self.port = port
        self.path = path
    }

    /// The host is on the local network (R5): a private, loopback or
    /// link-local IP address, `localhost`, a `.local` name, or a name with no
    /// dots.
    public var isLocalNetworkHost: Bool { LocalNetwork.isLocal(host: host) }
}

/// Which hosts count as the local network for plain http (R5).
public enum LocalNetwork {
    public static func isLocal(host: String) -> Bool {
        let host = host.lowercased()
        if let bytes = ipv4(host) {
            return bytes[0] == 10                                     // 10.0.0.0/8
                || (bytes[0] == 172 && (16...31).contains(bytes[1]))  // 172.16.0.0/12
                || (bytes[0] == 192 && bytes[1] == 168)              // 192.168.0.0/16
                || bytes[0] == 127                                    // loopback
                || (bytes[0] == 169 && bytes[1] == 254)              // link-local
        }
        if let bytes = ipv6(host) {
            if bytes == [UInt8](repeating: 0, count: 15) + [1] { return true }  // ::1
            if bytes[0] & 0xFE == 0xFC { return true }                          // fc00::/7, unique local
            if bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80 { return true }      // fe80::/10, link-local
            // An IPv4-mapped address (::ffff:a.b.c.d) is local when its IPv4 part is.
            if bytes[0..<10].allSatisfy({ $0 == 0 }) && bytes[10] == 0xFF && bytes[11] == 0xFF {
                return isLocal(host: bytes[12...].map(String.init).joined(separator: "."))
            }
            return false
        }
        guard !host.isEmpty, host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }) else {
            return false
        }
        // A host that reads as a number ("134744072", "0x08080808", "08") is
        // resolved by the system as an IPv4 address, or is no address at all:
        // never a local name (code review C5).
        if looksNumeric(host) { return false }
        return host == "localhost" || host.hasSuffix(".local") || !host.contains(".")
    }

    /// The host as an IPv4 address in every form the system's resolver takes
    /// (`inet_aton`): dotted quad, the short forms ("10.1"), and decimal,
    /// octal ("012.0.0.1") or hexadecimal ("0x7f000001") parts.
    static func ipv4(_ text: String) -> [UInt8]? {
        guard looksNumeric(text) else { return nil }
        var address = in_addr()
        guard text.withCString({ inet_aton($0, &address) }) == 1 else { return nil }
        return withUnsafeBytes(of: address.s_addr) { Array($0) }
    }

    /// Dot-separated parts that start with a digit and hold only digits, or
    /// `0x` and hexadecimal digits: what `inet_aton` reads as a number.
    static func looksNumeric(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 4 else { return false }
        return parts.allSatisfy { part in
            guard let first = part.first, first.isASCII, first.isNumber else { return false }
            let lower = part.lowercased()
            if lower.hasPrefix("0x") { return lower.dropFirst(2).allSatisfy(\.isHexDigit) }
            return part.allSatisfy { $0.isASCII && $0.isNumber }
        }
    }

    static func ipv6(_ text: String) -> [UInt8]? {
        // A zone ("fe80::1%en0") is not part of the address.
        let address = text.split(separator: "%", maxSplits: 1).first.map(String.init) ?? text
        var value = in6_addr()
        guard address.withCString({ inet_pton(AF_INET6, $0, &value) }) == 1 else { return nil }
        return withUnsafeBytes(of: value) { Array($0) }
    }
}

/// How the app may reach an address (R5): https always; plain http only to a
/// host on the local network, after the person confirms it; never otherwise.
/// Enforced by the connection itself, not only by the sheet or Info.plist.
public enum TransportPolicy: Equatable, Sendable {
    /// https.
    case encrypted
    /// http to a local host: allowed once the person ticked the notice's
    /// check box.
    case unencryptedLocal
    /// http to a host that is not on the local network: refused, nothing sent.
    case refused(host: String)

    public static func of(_ address: ServerAddress) -> TransportPolicy {
        switch address.scheme {
        case .https: .encrypted
        case .http: address.isLocalNetworkHost ? .unencryptedLocal : .refused(host: address.host)
        }
    }

    /// Whether a connection may be made, given the person's confirmation.
    public func permits(unencryptedConfirmed: Bool) -> Bool {
        switch self {
        case .encrypted: true
        case .unencryptedLocal: unencryptedConfirmed
        case .refused: false
        }
    }
}
