import AppKit
import Observation
import PhotoCore
import SwiftUI

/// Where the Server sheet was opened: it decides which permissions the check
/// requires, the wording, and whether Remove Server… is offered (issue #28,
/// R1, design §4).
public enum ServerSheetPurpose: Sendable, Equatable {
    case importing
    case publishing

    /// Import's five; from Publish only `asset.upload` and `asset.read`.
    public var requiredPermissions: [String] {
        switch self {
        case .importing: ImmichClient.neededPermissions
        case .publishing: ImmichClient.publishingPermissions
        }
    }

    /// Import reads the key's account; Publish's sheet doesn't.
    public var readsAccount: Bool { self == .importing }
}

/// A window that hosts the Server sheet: the import window, or the library
/// window for Publish (design §4).
@MainActor
public protocol ServerSheetHost: AnyObject {
    /// The saved servers, for the name check.
    var savedServers: [RemoteServiceRecord] { get }
    var serverCatalog: Catalog? { get }
    /// The window the sheet is on (its height bounds the sheet's).
    var serverSheetWindow: NSWindow? { get }
    /// A server was saved: the sheet closes.
    func serverSheetSaved(_ service: RemoteServiceRecord) async
    /// Cancel or Esc: the sheet closes, nothing saved.
    func serverSheetCancelled()
    /// Remove Server… (Import only).
    func serverSheetRemove(_ service: RemoteServiceRecord)
}

/// The Server sheet's state (issue #271, design §3): the form, the check and
/// the certificate page. The key typed here goes to the key store and
/// nowhere else; it is never shown, read back or printed.
@MainActor
@Observable
public final class ServerSheetModel: Identifiable {
    public enum Mode {
        case add
        case edit(RemoteServiceRecord)
    }

    public enum Page: Equatable {
        case form
        /// `changed`: the pinned certificate's replacement (design §3.5).
        case certificate(CertificateSummary, changed: Bool)
    }

    public let id = UUID()
    public let mode: Mode
    public let purpose: ServerSheetPurpose
    @ObservationIgnored weak var host: (any ServerSheetHost)?
    @ObservationIgnored let keys: any RemoteKeyStore
    public var name: String
    public var address: String {
        didSet { if oldValue != address { addressEdited() } }
    }
    /// The key typed in the field, held (and observed) here so the field
    /// redraws with it after the page changes (design review S1, N-5).
    /// Memory only; never printed.
    public private(set) var key = ""
    /// Whether a key was typed.
    public private(set) var keyEntered = false
    public var unencryptedConfirmed = false
    public var page: Page = .form
    public private(set) var isChecking = false
    public private(set) var result: ConnectionCheckResult?
    /// The person pressed Add or Save once: errors show from then on.
    public private(set) var submitted = false
    /// A key the import check refused holds `asset.upload` and `asset.read`
    /// (design §4.1: the result then says it can be saved from Publish).
    public private(set) var keyCanPublish = false
    /// The library holds publish records or import links for the saved
    /// address (R26).
    public private(set) var savedAddressHasRecords = false
    /// A certificate trusted on page 2, for this sheet's checks, with the
    /// address it was trusted for.
    private var trusted: ServerFormRules.TrustedCertificate?
    @ObservationIgnored private var checkTask: Task<Void, Never>?

    public init(mode: Mode, host: any ServerSheetHost, purpose: ServerSheetPurpose, keys: any RemoteKeyStore) {
        self.mode = mode
        self.host = host
        self.purpose = purpose
        self.keys = keys
        switch mode {
        case .add:
            name = ""
            address = ""
        case .edit(let service):
            name = service.name
            address = service.address
            unencryptedConfirmed = service.allowsUnencrypted
            if let catalog = host.serverCatalog {
                let saved = service.address
                Task {
                    savedAddressHasRecords = (try? await catalog.hasRecordsOrLinks(provider: service.provider,
                                                                                    address: saved)) ?? false
                }
            }
        }
    }

    /// Edit Server's warning under the address (R26, design §4.2): the typed
    /// address, normalized, is not the saved one, and the library has records
    /// or links for the saved one.
    public var showsAddressWarning: Bool {
        guard let existing, savedAddressHasRecords, let parsed = parsedAddress else { return false }
        return parsed.normalized != existing.address
    }

    public var isEdit: Bool { if case .edit = mode { true } else { false } }
    var existing: RemoteServiceRecord? { if case .edit(let service) = mode { service } else { nil } }

    public func setKey(_ text: String) {
        key = text
        keyEntered = !text.isEmpty
        if case .keyRejected? = result { result = nil }
        if case .missingPermissions? = result { result = nil }
    }

    private func addressEdited() {
        // The confirmation and a trusted certificate are for one address
        // (design §3.3, §3.6; design review N-3).
        unencryptedConfirmed = false
        trusted = nil
        result = nil
    }

    public var addressState: ServerFormRules.AddressState { ServerFormRules.addressState(address) }

    public var parsedAddress: ServerAddress? {
        switch addressState {
        case .encrypted(let address), .unencryptedLocal(let address): address
        default: nil
        }
    }

    public var effectiveName: String { ServerFormRules.effectiveName(name, address: parsedAddress) }

    public var nameTaken: Bool {
        let others = (host?.savedServers ?? []).filter { $0.id != existing?.id }.map(\.name)
        return ServerFormRules.nameTaken(effectiveName, among: others)
    }

    var addressChanged: Bool { parsedAddress?.normalized != existing?.address }

    var changed: Bool {
        guard let existing else { return true }
        return effectiveName != existing.name || addressChanged || keyEntered
            || unencryptedConfirmed != existing.allowsUnencrypted
    }

    /// A certificate trusted on page 2 and not saved yet.
    var trustedPending: Bool { trusted != nil }

    public var canSubmit: Bool {
        !isChecking && ServerFormRules.canSubmit(address: addressState, keyEntered: keyEntered,
                                                 unencryptedConfirmed: unencryptedConfirmed, nameTaken: nameTaken,
                                                 isEdit: isEdit, changed: changed, trustedPending: trustedPending)
    }

    /// "Will connect to ‹address›": whenever it differs from what was typed,
    /// and always before the first check (design §3.2).
    public var echo: String? {
        guard let parsedAddress else { return nil }
        let typed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed != parsedAddress.normalized || result == nil ? parsedAddress.normalized : nil
    }

    // MARK: Actions

    /// Add or Save (Return): checks the server when the address or key
    /// changed, then saves the row and the key together.
    public func submit() {
        submitted = true
        guard canSubmit, let address = parsedAddress, let host, let catalog = host.serverCatalog else { return }
        let name = effectiveName
        if let existing, !ServerFormRules.needsCheck(isEdit: true, addressChanged: addressChanged, keyEntered: keyEntered,
                                                     trustedPending: trustedPending) {
            var record = existing
            record.name = name
            Task {
                if let saved = try? await catalog.saveRemoteService(record) { await host.serverSheetSaved(saved) }
            }
            return
        }
        guard keyEntered || existing != nil else { return }
        // A pin is for one address: a new address starts without one.
        let chosen = ServerFormRules.pin(trusted: trusted, address: address.normalized, existing: existing)
        let pin = chosen?.fingerprint
        let pinnedAt = chosen?.trustedAt
        let unencryptedConfirmed = self.unencryptedConfirmed
        let existing = self.existing
        isChecking = true
        result = nil
        let keys = self.keys
        let enteredKey = keyEntered ? key : nil
        let purpose = self.purpose
        keyCanPublish = false
        checkTask = Task {
            defer { isChecking = false }
            // The Keychain is asked off the main thread: its access prompt
            // must not block the window (code review C8).
            let key: String
            if let enteredKey {
                key = enteredKey
            } else {
                let account = existing?.uuid ?? ""
                switch await Task.detached(operation: { Self.storedKey(keys, account: account) }).value {
                case .success(let stored): key = stored
                case .failure(let error):
                    result = .keychain(error.message)
                    return
                }
            }
            let connection = RemoteConnection(address: address, key: key, pinned: pin,
                                              unencryptedConfirmed: unencryptedConfirmed)
            let outcome: ConnectionCheckResult
            var permissions: [String]?
            do {
                (outcome, permissions) = await (try ImmichClient(connection: connection))
                    .checkWithPermissions(requiring: purpose.requiredPermissions, readsAccount: purpose.readsAccount)
            } catch {
                outcome = .unreachable(reason: "", isLocalHost: address.isLocalNetworkHost)
            }
            guard !Task.isCancelled else { return }
            if case .missingPermissions = outcome, let permissions {
                keyCanPublish = ImmichClient.missing(from: permissions, needed: ImmichClient.publishingPermissions).isEmpty
            }
            switch outcome {
            case .passed:
                var record = existing ?? RemoteServiceRecord(name: name, address: address.normalized)
                record.name = name
                record.address = address.normalized
                record.allowsUnencrypted = address.scheme == .http
                record.certificateFingerprint = pin?.hex
                record.certificateTrustedAt = pin == nil ? nil : pinnedAt
                // The key and the row are saved together; a failed save puts
                // the previous key back, so a key meant for a new address never
                // stays beside the old one (security review F2).
                switch await catalog.saveRemoteService(record, key: enteredKey, keys: keys) {
                case .saved(let saved):
                    await host.serverSheetSaved(saved)
                case .keychainRefused(let error):
                    result = .keychain(error.message)
                case .catalogFailed(let message):
                    result = .keychain(message)
                }
            case .untrustedCertificate(let summary):
                page = .certificate(summary, changed: false)
            default:
                result = outcome
            }
        }
    }

    /// The stored key, or the Keychain's refusal (a missing item included).
    nonisolated static func storedKey(_ keys: any RemoteKeyStore, account: String) -> Result<String, RemoteKeyStoreError> {
        do throws(RemoteKeyStoreError) {
            guard let stored = try keys.key(account: account) else { return .failure(.from(errSecItemNotFound)) }
            return .success(stored)
        } catch {
            return .failure(error)
        }
    }

    /// Cancel or Esc: stops a check; nothing is saved.
    public func cancel() {
        if case .certificate = page {
            page = .form
            return
        }
        checkTask?.cancel()
        isChecking = false
        host?.serverSheetCancelled()
    }

    /// Back (⌘[) on the certificate page: the form as it was.
    public func back() {
        page = .form
    }

    /// Trust Certificate: the check runs again against this one certificate.
    public func trustCertificate() {
        guard case .certificate(let summary, _) = page else { return }
        trusted = ServerFormRules.TrustedCertificate(fingerprint: summary.fingerprint, trustedAt: Date(),
                                                     address: parsedAddress?.normalized ?? "")
        page = .form
        result = nil
        submit()
    }

    /// Review Certificate… under a changed-certificate result.
    public func reviewCertificate() {
        guard case .certificateChanged(let summary)? = result else { return }
        page = .certificate(summary, changed: true)
    }

    /// Remove Server… (Edit only): the window asks first, once this sheet has
    /// gone (design review S3: a dialog asked for while a sheet closes can be
    /// dropped).
    public func remove() {
        guard let existing, purpose == .importing, let host else { return }
        host.serverSheetRemove(existing)
    }

    /// Remove Server… is offered only from Import: one path to deleting a
    /// credential (design §4).
    public var offersRemove: Bool { isEdit && purpose == .importing }

    /// The ideal height for the page shown (S2).
    public var idealHeight: Double {
        let notice = if case .unencryptedLocal = addressState { true } else { false }
        let certificate: (shown: Bool, changed: Bool) = if case .certificate(_, let changed) = page { (true, changed) }
            else { (false, false) }
        return ServerSheetHeight.ideal(certificatePage: certificate.shown, changed: certificate.changed, notice: notice,
                                       result: result != nil || showsAddressWarning,
                                       windowHeight: host?.serverSheetWindow.map { Double($0.frame.height) })
    }
}

// MARK: - Views

/// Measurements of the Server sheet (design §3.1).
enum ServerSheetMetrics {
    static let width: CGFloat = 460
    static let barPadding: CGFloat = 12
}

/// Add Server and Edit Server: one sheet on the import window with two pages
/// (design §3). System controls only.
public struct ServerSheet: View {
    @Bindable var sheet: ServerSheetModel

    public init(sheet: ServerSheetModel) {
        self.sheet = sheet
    }

    public var body: some View {
        Group {
            switch sheet.page {
            case .form:
                ServerFormPage(sheet: sheet)
            case .certificate(let summary, let changed):
                CertificatePage(sheet: sheet, summary: summary, changed: changed)
            }
        }
        .frame(width: ServerSheetMetrics.width)
        // The height follows the content (the notice, a result, the page),
        // clamped to the window (S2); the form scrolls inside it.
        .frame(height: sheet.idealHeight)
    }
}

private struct ServerFormPage: View {
    @Bindable var sheet: ServerSheetModel
    @FocusState private var focus: Field?

    enum Field: Hashable { case name, address, key }

    var body: some View {
        VStack(spacing: 0) {
            Text(sheet.isEdit ? String(localized: "Edit Server", comment: "Server sheet title")
                              : String(localized: "Add Server", comment: "Server sheet title"))
                .font(.system(size: 13, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
            Form {
                Section {
                    TextField("Name", text: $sheet.name, prompt: Text(sheet.parsedAddress?.host ?? ""))
                        .focused($focus, equals: .name)
                    if sheet.nameTaken {
                        IssueLine(text: String(localized: "A server named “\(sheet.effectiveName)” already exists.",
                                               comment: "Server sheet: the name is taken"))
                    }
                    TextField("Server address", text: $sheet.address, prompt: Text("https://photos.example.com"))
                        .focused($focus, equals: .address)
                        .accessibilityHint(Text(resultHint(concernsAddress: true)))
                    if let echo = sheet.echo {
                        SheetCaption(text: String(localized: "Will connect to \(echo)",
                                                  comment: "Server sheet: the normalized address"))
                    }
                    if sheet.showsAddressWarning {
                        IssueLine(text: ServerText.addressChangeWarning)
                            .onAppear { AccessibilityText.announce(ServerText.addressChangeWarning, priority: .medium) }
                    }
                    addressIssue
                    if case .unencryptedLocal = sheet.addressState {
                        UnencryptedNotice(confirmed: $sheet.unencryptedConfirmed)
                    }
                    resultView(concernsAddress: true)
                    SecureField(String(localized: "API key", comment: "Server sheet row label"),
                                text: Binding(get: { sheet.key }, set: { sheet.setKey($0) }),
                                prompt: Text(sheet.isEdit ? String(localized: "Leave empty to keep the current key")
                                                          : String(localized: "Paste the key here")))
                        .focused($focus, equals: .key)
                        .accessibilityHint(Text(resultHint(concernsAddress: false)))
                    ForEach(ServerText.keyCaptions(sheet.purpose), id: \.self) { SheetCaption(text: $0) }
                    SheetCaption(text: String(localized: "This Mac keeps its copy of the key in the Keychain."))
                    resultView(concernsAddress: false)
                }
            }
            .formStyle(.grouped)
            .disabled(sheet.isChecking)
            Divider()
            HStack(spacing: 12) {
                if sheet.offersRemove {
                    Button("Remove Server…", role: .destructive) { sheet.remove() }
                        .disabled(sheet.isChecking)
                }
                if sheet.isChecking {
                    ProgressView().controlSize(.small)
                    Text("Checking the server…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Spacer()
                Button("Cancel", role: .cancel) { sheet.cancel() }
                    .keyboardShortcut(.cancelAction)
                Button(sheet.isEdit ? String(localized: "Save") : String(localized: "Add", comment: "Server sheet: add the server")) {
                    sheet.submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!sheet.canSubmit)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, ServerSheetMetrics.barPadding)
        }
        .onChange(of: sheet.result) { _, result in
            guard let result, let text = ServerText.result(result, host: sheet.parsedAddress?.host ?? "",
                                                           name: sheet.effectiveName, purpose: sheet.purpose,
                                                           keyCanPublish: sheet.keyCanPublish) else { return }
            AccessibilityText.announce(text.title + ". " + text.detail, priority: .medium)
        }
    }

    /// Shown once the field lost the focus or Add was pressed (design §3.2).
    @ViewBuilder private var addressIssue: some View {
        if focus != .address || sheet.submitted {
            switch sheet.addressState {
            case .unsupportedScheme:
                IssueLine(text: String(localized: "Use an address that starts with https:// or http://."))
            case .refused(let host):
                IssueLine(text: String(localized: "“\(host)” is not on your local network. http:// is only allowed for servers on your local network; use https://.",
                                       comment: "Server sheet: plain http to a host that is not local"))
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder private func resultView(concernsAddress: Bool) -> some View {
        if let result = sheet.result,
           let text = ServerText.result(result, host: sheet.parsedAddress?.host ?? "", name: sheet.effectiveName,
                                        purpose: sheet.purpose, keyCanPublish: sheet.keyCanPublish),
           text.concernsAddress == concernsAddress {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(text.title).font(.system(size: 13, weight: .semibold))
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                Text(text.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if case .certificateChanged = result {
                    Button("Review Certificate…") { sheet.reviewCertificate() }
                }
            }
            // .contain, so Review Certificate… stays a control of its own (S5).
            .accessibilityElement(children: .contain)
        }
    }

    /// The result under a field is also that field's hint (design §8, N1).
    private func resultHint(concernsAddress: Bool) -> String {
        guard let result = sheet.result,
              let text = ServerText.result(result, host: sheet.parsedAddress?.host ?? "", name: sheet.effectiveName,
                                           purpose: sheet.purpose, keyCanPublish: sheet.keyCanPublish),
              text.concernsAddress == concernsAddress else { return "" }
        return text.title + ". " + text.detail
    }
}

/// The unencrypted notice (design §3.3): stays on screen while the person
/// decides; its check box is the confirmation, unticked for each address.
private struct UnencryptedNotice: View {
    @Binding var confirmed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("This connection is not encrypted").font(.system(size: 13, weight: .semibold))
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            Text("The address starts with http://. Your API key and every photo you import or publish cross your network without encryption, so anyone on it could read them. Use https:// if your server offers it.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Send my key and photos without encryption", isOn: $confirmed)
                .toggleStyle(.checkbox)
        }
    }
}

/// Page 2 (design §3.5): what the system could not verify, the fingerprint,
/// and two buttons, neither the default.
private struct CertificatePage: View {
    let sheet: ServerSheetModel
    let summary: CertificateSummary
    let changed: Bool

    var body: some View {
        let host = sheet.parsedAddress?.host ?? summary.subject
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(changed ? String(localized: "Trust the new certificate?") : String(localized: "Trust this certificate?"))
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    sheet.back()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                }
                .keyboardShortcut("[", modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)
            // The body scrolls between the fixed header and button bar, so
            // Back, Cancel and Trust Certificate stay on screen in a short
            // window (design review N-1). A sheet, not a scroll view under the
            // window's toolbar.
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if changed {
                        Text(String(localized: "“\(host)” presented a different certificate from the one you trusted on \(trustedDate). That is expected if it was renewed. It can also mean that someone is intercepting the connection.",
                                    comment: "Certificate page: a pinned server presented another certificate"))
                    } else {
                        Text(String(localized: "macOS can't tell who issued the certificate that “\(host)” presented. That is normal for a server you set up yourself, but another device on your network can present a certificate too. Trust it only if the fingerprint below matches your server's.",
                                    comment: "Certificate page: a certificate the system does not trust"))
                    }
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                        row(String(localized: "Issued to"), summary.subject)
                        row(String(localized: "Issued by"), summary.issuer)
                        row(String(localized: "Valid"), validity(summary))
                    }
                    if changed, let before = sheet.existing?.pinnedFingerprint {
                        FingerprintView(title: String(localized: "Trusted before"), fingerprint: before)
                        FingerprintView(title: String(localized: "Now"), fingerprint: summary.fingerprint)
                    } else {
                        FingerprintView(title: String(localized: "SHA-256 fingerprint"), fingerprint: summary.fingerprint)
                    }
                    Text(String(localized: "If you trust it, this Mac will accept only this exact certificate for “\(sheet.effectiveName)” at this address. If it ever changes, connecting fails until you review it again.",
                                comment: "Certificate page footer"))
                }
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            Divider()
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) { sheet.back() }
                    .keyboardShortcut(.cancelAction)
                Button("Trust Certificate") { sheet.trustCertificate() }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, ServerSheetMetrics.barPadding)
        }
    }

    private var trustedDate: String {
        (sheet.existing?.certificateTrustedAt ?? Date()).formatted(date: .abbreviated, time: .omitted)
    }

    private func validity(_ summary: CertificateSummary) -> String {
        let from = summary.notBefore?.formatted(date: .abbreviated, time: .omitted) ?? ""
        let to = summary.notAfter?.formatted(date: .abbreviated, time: .omitted) ?? ""
        return String(localized: "\(from) to \(to)", comment: "A range of dates, or a certificate's validity")
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}

/// A fingerprint in two monospaced lines, selectable, copied with colons.
private struct FingerprintView: View {
    let title: String
    let fingerprint: CertificateFingerprint

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(fingerprint.displayLines.joined(separator: "\n"))
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize()
                .contextMenu {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(fingerprint.colonSeparated, forType: .string)
                    }
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(fingerprint.spokenGroups))
    }
}

/// An icon and text under the field it concerns (design §3.2).
private struct IssueLine: View {
    let text: String

    var body: some View {
        Label {
            Text(text).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
    }
}

/// 11 pt secondary text under the row it explains.
private struct SheetCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
