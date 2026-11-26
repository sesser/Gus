import Foundation
import Security

/// The publish check against a saved server (design §3.3): the key from the
/// store, a client and what the server allows, or why not. Used by the sheet,
/// by Publish N Photos and by Retry Failed.
public enum PublishConnection: Sendable {
    case ready(ImmichClient, PublishServerInfo)
    case failed(ConnectionCheckResult)
    /// The server as saved now is not `service`: removed, or its address or
    /// trusted certificate changed (security review N7). Nothing was sent.
    /// Never `.unchanged`.
    case changed(PublishServerChange)
    /// The catalog could not be read; nothing was sent.
    case unreadable(String)

    /// Off the main actor: the Keychain may ask the person. The key is read
    /// with the row as saved now (`RemoteSavedKey`), and only a row with
    /// `service`'s address and trusted certificate is contacted, so a key
    /// saved for a new address never goes to the previous one: not from a
    /// record held since before a Save, nor between a Save's key write and
    /// its row write (security review N7).
    public static func connect(_ service: RemoteServiceRecord, catalog: Catalog, keys: any RemoteKeyStore,
                               readsAccount: Bool) async -> PublishConnection {
        guard service.serverAddress != nil else { return .failed(.notImmich) }
        let key: String
        let saved: RemoteServiceRecord
        switch await RemoteSavedKey.read(for: service, in: catalog, keys: keys) {
        case .key(let stored, let record):
            key = stored
            saved = record
        case .changed(let change):
            return .changed(change)
        case .keychain(let error):
            return .failed(.keychain(error.message))
        case .catalog(let message):
            return .unreadable(message)
        }
        guard let address = saved.serverAddress else { return .failed(.notImmich) }
        let connection = RemoteConnection(address: address, key: key, pinned: saved.pinnedFingerprint,
                                          unencryptedConfirmed: saved.allowsUnencrypted)
        guard let client = try? ImmichClient(connection: connection) else {
            return .failed(.unreachable(reason: "", isLocalHost: address.isLocalNetworkHost))
        }
        switch await client.publishCheck(readsAccount: readsAccount) {
        case .passed(let info): return .ready(client, info)
        case .failed(let result): return .failed(result)
        }
    }
}

/// How a Retry Failed came out (R23, design §10.3).
public enum PublishRetryOutcome: Sendable {
    /// Stopped while it checked its server, or before it started on any
    /// photo, or its server was no longer saved as the run's (removed, or
    /// its address or certificate changed, security review N7): not an
    /// ending. The run stays exactly as it was before this
    /// Retry Failed (PRD revision 7, review D-10).
    case calledOff
    /// Its check found a problem (a failed check or a missing permission,
    /// review D-5): the run's new ending. No photo was started.
    case checkStopped(PublishRun)
    /// It started on its photos: the run as it ended, however it ended.
    case ran(PublishRun)

    /// The run to record in place of the old one, or nil to leave the old one
    /// as it was. `stopAsked`: the person's Stop came before the app acted on
    /// this outcome; it wins over a check result not yet acted on (D-10).
    public func ended(stopAsked: Bool) -> PublishRun? {
        switch self {
        case .calledOff: nil
        case .checkStopped(let run): stopAsked ? nil : run
        case .ran(let run): run
        }
    }
}

/// Retry Failed after the app has taken the publish slot: the server check,
/// then the run's remaining work (R23, design §10.3). Stopping is cancelling
/// the task that runs it.
public enum PublishRetry {
    /// `check` contacts the run's server (`PublishConnection.connect` in the
    /// app); `makeJob` builds the job for the client it gave (nil when it
    /// can't be built, which leaves the run as it was).
    public static func perform(
        _ run: PublishRun,
        check: @Sendable () async -> PublishConnection,
        makeJob: @Sendable (ImmichClient, PublishServerInfo) async -> PublishJob?,
        progress: @escaping @Sendable (PublishProgress) -> Void = { _ in }
    ) async -> PublishRetryOutcome {
        let connection = await check()
        // A Stop during the check wins over what the check found (D-10).
        if Task.isCancelled { return .calledOff }
        var ended = run
        ended.endedAt = Date()
        switch connection {
        case .failed(let result):
            ended.ending = .stopped(.checkFailed(result))
            return .checkStopped(ended)
        case .changed, .unreadable:
            // The server was changed or removed since Retry Failed read it,
            // or the catalog can't say: nothing was sent, and the run stays
            // as it was; the next Retry Failed gives the refusal its reload
            // finds (security review N7).
            return .calledOff
        case .ready(let client, let info):
            let missing = PublishPermissions.missing(from: info.permissions, album: run.choices.album,
                                                     stacking: run.choices.stacking)
            if let first = missing.all.first {
                ended.ending = .stopped(.missingPermission(first))
                return .checkStopped(ended)
            }
            // Nothing ran if the job can't be built: not an ending either.
            guard let job = await makeJob(client, info), !Task.isCancelled else { return .calledOff }
            guard let retried = await job.retry(run, progress: progress) else { return .calledOff }
            return .ran(retried)
        }
    }
}
