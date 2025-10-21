//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

internal class BackupArchivePollArchiver: BackupArchiveProtoStreamWriter {
    private typealias ArchiveFrameError = BackupArchive.ArchiveFrameError<BackupArchive.InteractionUniqueId>

    private let pollManager: PollMessageManager
    private let db: DB
    private let recipientDatabaseTable: RecipientDatabaseTable

    init(
        pollManager: PollMessageManager,
        db: DB,
        recipientDatabaseTable: RecipientDatabaseTable
    ) {
        self.pollManager = pollManager
        self.db = db
        self.recipientDatabaseTable = recipientDatabaseTable
    }

    // MARK: - Archiving

    func archivePoll(
        _ message: TSMessage,
        messageRowId: Int64,
        interactionUniqueId: BackupArchive.InteractionUniqueId,
        context: BackupArchive.ChatArchivingContext
    ) -> BackupArchive.ArchiveInteractionResult<BackupArchive.InteractionArchiveDetails.ChatItemType> {
        let pollResult = pollManager.buildPollForBackup(message: message, messageRowId: messageRowId, tx: context.tx)

        let poll: BackupsPollData
        switch (pollResult) {
        case .success(let backupsPollData):
            poll = backupsPollData
        case .failure(let error):
            return .messageFailure([error])
        }

        var pollProto = BackupProto_Poll()
        pollProto.question = poll.question
        pollProto.allowMultiple = poll.allowMultiple
        pollProto.hasEnded_p = poll.isEnded

        for option in poll.options {
            var pollOptionProto = BackupProto_Poll.PollOption()
            pollOptionProto.option = option.text

            for vote in option.votes {
                var pollVoteProto = BackupProto_Poll.PollOption.PollVote()
                guard let voterId = context.recipientContext.recipientId(forRecipientDbRowId: vote.voteAuthorId) else {
                    return .messageFailure([.archiveFrameError(.pollVoteAuthorSignalRecipientIdMissing, BackupArchive.InteractionUniqueId(interaction: message))])
                }

                pollVoteProto.voterID = voterId.value
                pollVoteProto.voteCount = vote.voteCount
                pollOptionProto.votes.append(pollVoteProto)
            }
            pollProto.options.append(pollOptionProto)
        }

        return .success(.poll(pollProto))
    }

    // MARK: Restoring

    typealias RestoredMessageBody = BackupArchive.RestoredMessageContents

    func restorePoll(
        _ poll: RestoredMessageBody.Poll,
        chatItemId: BackupArchive.ChatItemId,
        message: TSMessage,
        context: BackupArchive.RecipientRestoringContext
    ) -> BackupArchive.RestoreInteractionResult<Void> {
        let restorePollResult = pollManager.restorePollFromBackup(
            pollBackupData: poll.poll,
            message: message,
            chatItemId: chatItemId,
            tx: context.tx
        )

        switch restorePollResult {
        case .success:
            return .success(())
        case .unrecognizedEnum(let error):
            return .unrecognizedEnum(error)
        case .partialRestore(let errors):
            return .partialRestore((), errors)
        case .failure(let error):
            return .messageFailure(error)
        }
    }
}
