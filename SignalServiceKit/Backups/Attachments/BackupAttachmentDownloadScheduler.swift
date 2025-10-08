//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public protocol BackupAttachmentDownloadScheduler {
    /// "Enqueue" an attachment from a backup for download, if needed and eligible, otherwise do nothing.
    ///
    /// If the same attachment pointed to by the reference is already enqueued, updates it to the greater
    /// of the existing and new reference's timestamp.
    ///
    /// Doesn't actually trigger a download; callers must later call ``BackupAttachmentDownloadQueueRunner/restoreAttachmentsIfNeeded``
    /// to insert rows into the normal AttachmentDownloadQueue and download.
    func enqueueFromBackupIfNeeded(
        _ referencedAttachment: ReferencedAttachment,
        restoreStartTimestampMs: UInt64,
        backupPlan: BackupPlan,
        remoteConfig: RemoteConfig,
        isPrimaryDevice: Bool,
        tx: DBWriteTransaction
    ) throws
}

public class BackupAttachmentDownloadSchedulerImpl: BackupAttachmentDownloadScheduler {

    private let backupAttachmentDownloadStore: BackupAttachmentDownloadStore

    public init(
        backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
    ) {
        self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
    }

    public func enqueueFromBackupIfNeeded(
        _ referencedAttachment: ReferencedAttachment,
        restoreStartTimestampMs: UInt64,
        backupPlan: BackupPlan,
        remoteConfig: RemoteConfig,
        isPrimaryDevice: Bool,
        tx: DBWriteTransaction
    ) throws {
        let eligibility = BackupAttachmentDownloadEligibility.forAttachment(
            referencedAttachment.attachment,
            reference: referencedAttachment.reference,
            currentTimestamp: restoreStartTimestampMs,
            backupPlan: backupPlan,
            remoteConfig: remoteConfig,
            isPrimaryDevice: isPrimaryDevice
        )

        if
            let state = eligibility.thumbnailMediaTierState,
            state != .done
        {
            try backupAttachmentDownloadStore.enqueue(
                referencedAttachment,
                thumbnail: true,
                // Thumbnails are always media tier
                canDownloadFromMediaTier: true,
                state: state,
                currentTimestamp: restoreStartTimestampMs,
                tx: tx
            )
        }
        if
            let state = eligibility.fullsizeState,
            state != .done
        {
            try backupAttachmentDownloadStore.enqueue(
                referencedAttachment,
                thumbnail: false,
                canDownloadFromMediaTier: eligibility.canDownloadMediaTierFullsize,
                state: state,
                currentTimestamp: restoreStartTimestampMs,
                tx: tx
            )
        }
    }
}

#if TESTABLE_BUILD

open class BackupAttachmentDownloadSchedulerMock: BackupAttachmentDownloadScheduler {

    public init() {}

    open func enqueueFromBackupIfNeeded(
        _ referencedAttachment: ReferencedAttachment,
        restoreStartTimestampMs: UInt64,
        backupPlan: BackupPlan,
        remoteConfig: RemoteConfig,
        isPrimaryDevice: Bool,
        tx: DBWriteTransaction
    ) throws {
        // Do nothing
    }
}

#endif
