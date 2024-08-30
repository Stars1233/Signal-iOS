//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension MessageBackup {

    /// Base context class used for archiving (creating a backup).
    ///
    /// Requires a write tx on init; we want to hold the write lock while
    /// creating a backup to avoid races with e.g. message processing.
    ///
    /// But only exposes a read tx, because we explicitly do not want
    /// archiving to be updating the database, just reading from it.
    /// (The exception to this is enqueuing attachment uploads.)
    open class ArchivingContext {

        private let _tx: DBWriteTransaction

        public var tx: DBReadTransaction { _tx }

        init(tx: DBWriteTransaction) {
            self._tx = tx
        }
    }

    /// Base context class used for restoring from a backup.
    open class RestoringContext {

        public let tx: DBWriteTransaction

        init(tx: DBWriteTransaction) {
            self.tx = tx
        }
    }
}