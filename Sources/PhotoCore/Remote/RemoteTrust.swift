import CryptoKit
import Foundation
import Security

/// The SHA-256 of a certificate's DER bytes: what the person compares with
/// their server's and what a connection pins (R6, design §3.5).
public struct CertificateFingerprint: Hashable, Sendable {
    public let bytes: [UInt8]

    public init(certificateData: Data) {
        bytes = Array(SHA256.hash(data: certificateData))
    }

    /// 64 hexadecimal digits, as stored in the catalog.
    public init?(hex: String) {
        let digits = Array(hex.filter { !$0.isWhitespace && $0 != ":" })
        guard digits.count == 64 else { return nil }
        var bytes: [UInt8] = []
        for index in stride(from: 0, to: 64, by: 2) {
            guard let byte = UInt8(String(digits[index...index + 1]), radix: 16) else { return nil }
            bytes.append(byte)
        }
        self.bytes = bytes
    }

    private var pairs: [String] { bytes.map { String(format: "%02X", $0) } }

    /// Upper case, no separators: the stored form.
    public var hex: String { pairs.joined() }

    /// Two lines of 16 pairs, a space between pairs and two after the eighth
    /// (design §3.5).
    public var displayLines: [String] {
        stride(from: 0, to: pairs.count, by: 16).map { start in
            let line = pairs[start..<min(start + 16, pairs.count)]
            return line.prefix(8).joined(separator: " ") + "  " + line.dropFirst(8).joined(separator: " ")
        }
    }

    /// Colon-separated pairs, the form browsers and servers show (what Copy
    /// puts on the pasteboard).
    public var colonSeparated: String { pairs.joined(separator: ":") }

    /// Groups of four digits, for VoiceOver.
    public var spokenGroups: String {
        let digits = Array(hex)
        return stride(from: 0, to: digits.count, by: 4).map { String(digits[$0..<min($0 + 4, digits.count)]) }
            .joined(separator: " ")
    }
}

/// What the certificate page shows (design §3.5).
public struct CertificateSummary: Hashable, Sendable {
    public var subject: String
    public var issuer: String
    public var notBefore: Date?
    public var notAfter: Date?
    public var fingerprint: CertificateFingerprint

    public init(subject: String, issuer: String, notBefore: Date?, notAfter: Date?, fingerprint: CertificateFingerprint) {
        self.subject = subject
        self.issuer = issuer
        self.notBefore = notBefore
        self.notAfter = notAfter
        self.fingerprint = fingerprint
    }

    public init(_ certificate: SecCertificate) {
        let data = SecCertificateCopyData(certificate) as Data
        fingerprint = CertificateFingerprint(certificateData: data)
        subject = SecCertificateCopySubjectSummary(certificate) as String? ?? ""
        issuer = Self.issuerName(certificate) ?? ""
        notBefore = SecCertificateCopyNotValidBeforeDate(certificate) as Date?
        notAfter = SecCertificateCopyNotValidAfterDate(certificate) as Date?
    }

    /// The issuer's common name, else its organization.
    private static func issuerName(_ certificate: SecCertificate) -> String? {
        let keys = [kSecOIDX509V1IssuerName] as CFArray
        guard let values = SecCertificateCopyValues(certificate, keys, nil) as? [CFString: Any],
              let issuer = values[kSecOIDX509V1IssuerName] as? [CFString: Any],
              let parts = issuer[kSecPropertyKeyValue] as? [[CFString: Any]]
        else { return nil }
        func part(_ oid: CFString) -> String? {
            parts.first { ($0[kSecPropertyKeyLabel] as? String) == oid as String }?[kSecPropertyKeyValue] as? String
        }
        return part(kSecOIDCommonName) ?? part(kSecOIDOrganizationName)
    }
}

/// What a connection does with the certificate a server presented (R6),
/// decided in the TLS challenge, before any request (and so before the key)
/// leaves the Mac.
public enum TrustDecision: Equatable, Sendable {
    /// No pin, and the system trusts it for this host.
    case systemTrusted
    /// It is the certificate the person trusted for this connection.
    case pinned
    /// No pin, and the system does not trust it: the person may review it.
    case untrusted(CertificateSummary)
    /// The connection has a pin and this is another certificate: a failure,
    /// never a prompt in the middle of an import.
    case changed(CertificateSummary)

    public var accepts: Bool {
        switch self {
        case .systemTrusted, .pinned: true
        case .untrusted, .changed: false
        }
    }

    /// With a pin, only that certificate is accepted, whether or not the
    /// system trusts another one; without a pin, the system decides. There is
    /// no way to turn the check off.
    public static func decide(trust: SecTrust, host: String, pinned: CertificateFingerprint?) -> TrustDecision {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
            return .untrusted(CertificateSummary(subject: host, issuer: "", notBefore: nil, notAfter: nil,
                                                 fingerprint: CertificateFingerprint(certificateData: Data())))
        }
        let summary = CertificateSummary(leaf)
        if let pinned {
            return summary.fingerprint == pinned ? .pinned : .changed(summary)
        }
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString))
        return SecTrustEvaluateWithError(trust, nil) ? .systemTrusted : .untrusted(summary)
    }
}
