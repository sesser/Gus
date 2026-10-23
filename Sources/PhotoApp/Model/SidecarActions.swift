import Foundation
import PhotoCore
import os

extension LibraryModel {
    private static let sidecarLog = Logger(subsystem: AppBranding.bundleIdentifier, category: "sidecars")

    // MARK: Writing

    /// Writes queued sidecar changes shortly after the last change, in the
    /// background. A request while a run is busy starts another run after it.
    func scheduleSidecarSync() {
        guard writesSidecars else { return }
        if sidecarSyncTask != nil {
            sidecarSyncPending = true
            return
        }
        let sidecars = self.sidecars
        sidecarSyncTask = Task {
            try? await Task.sleep(for: .milliseconds(1500))
            repeat {
                sidecarSyncPending = false
                let mounted = onlineVolumeIDs
                do {
                    let report = try await sidecars.processQueue(mountedVolumes: mounted)
                    if report.changedOnDisk > 0 { await refreshDiskChanges() }
                    if report.failed > 0 {
                        statusMessage = String(localized: "Could not write \(report.failed) sidecar files.")
                    }
                } catch is CancellationError {
                } catch {
                    Self.sidecarLog.error("Writing sidecars failed: \(error.localizedDescription, privacy: .public)")
                }
            } while sidecarSyncPending && !Task.isCancelled
            sidecarSyncTask = nil
        }
    }

    // MARK: Checking

    /// Looks for sidecars and masters other apps changed, on every mounted
    /// volume, in the background.
    func checkForDiskChanges(delay: Duration = .zero) {
        guard diskCheckTask == nil else { return }
        let sidecars = self.sidecars
        diskCheckTask = Task {
            try? await Task.sleep(for: delay)
            isCheckingDisk = true
            do {
                let report = try await sidecars.checkForChanges(mountedVolumes: onlineVolumeIDs)
                Self.sidecarLog.info("Checked \(report.checked) masters: \(report.changedOnDisk) changed outside the app")
            } catch is CancellationError {
            } catch {
                Self.sidecarLog.error("Checking for changes failed: \(error.localizedDescription, privacy: .public)")
            }
            isCheckingDisk = false
            await refreshDiskChanges()
            diskCheckTask = nil
        }
    }

    func refreshDiskChanges() async {
        diskChangeCount = (try? await catalog.diskChangeCount()) ?? diskChangeCount
        diskChangeRevision += 1
        if diskChangeCount == 0, sidebarSelection == .changedOnDisk { sidebarSelection = .allPhotos }
    }

    // MARK: Review

    /// Settles outside changes for the given photos, then shows the result.
    func resolveDiskChanges(_ changes: [DiskChange], with resolution: SidecarSync.Resolution) {
        guard !changes.isEmpty else { return }
        let sidecars = self.sidecars
        let mounted = onlineVolumeIDs
        persist { try await sidecars.resolve(changes, with: resolution, mountedVolumes: mounted) }
        afterPendingWrites { model in
            await model.refreshDiskChanges()
            await model.refreshKeywords()
            model.reloadItems(keepFocus: true)
        }
    }
}
