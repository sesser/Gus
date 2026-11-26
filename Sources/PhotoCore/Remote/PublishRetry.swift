import Foundation
import Security

/// The publish check against a saved server (design §3.3): the key from the
/// store, a client and what the server allows, or why not. Used by the sheet,
/// by Publish N Photos and by Retry Failed.
public enum PublishConnection: Sendable {
    case ready(ImmichClient, PublishServerInfo)
    case failed(ConnectionCheckResult)

    /// Off the main actor: the Keychain may ask the person.
    public static func connect(_ service: RemoteServiceRecord, keys: any RemoteKeyStore,
                               readsAccount: Bool) async -> PublishConnection {
        guard let address = service.serverAddress else { return .failed(.notImmich) }
        let key: String
        do throws(RemoteKeyStoreError) {
            guard let stored = try keys.key(account: service.uuid) else {
                return .failed(.keychain(RemoteKeyStoreError.from(errSecItemNotFound).message))
            }
            key = stored
        } catch {
            return .failed(.keychain(error.message))
        }
        let connection = RemoteConnection(address: address, key: key, pinned: service.pinnedFingerprint,
                                          unencryptedConfirmed: service.allowsUnencrypted)
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
    /// photo: not an ending. The run stays exactly as it was before this
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
