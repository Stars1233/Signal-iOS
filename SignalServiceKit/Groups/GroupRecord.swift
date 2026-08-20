//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB
import LibSignalClient

public struct GroupRecord: Codable, FetchableRecord, PersistableRecord {
    // This table has a "Record" suffix to avoid the SQL "GROUP" keyword.
    public static let databaseTableName: String = "GroupRecord"

    enum Constants {
        static let refreshInterval: TimeInterval = .week
        static let refreshJitter: TimeInterval = refreshInterval / 7
    }

    public typealias RowId = Int64
    typealias ThreadId = TSThread.RowId

    let rowId: RowId

    /// Might be 16 bytes (GV1) or 32 bytes (GV2).
    let groupId: Data

    /// Might not exist. Perhaps the group hasn't been restored yet or the
    /// thread has been deleted.
    private(set) var threadId: ThreadId?

    /// Missing for GV1 groups; potentially missing for GV2 groups you've left.
    let masterKey: GroupMasterKey?

    /// The timestamp when the group was most recently auto-refreshed.
    private(set) var refreshedAt: Int64

    var refreshedAtDate: Date {
        return Date(timeIntervalSince1970: TimeInterval(self.refreshedAt))
    }

    enum CodingKeys: String, CodingKey {
        case rowId
        case groupId
        case threadId
        case masterKey
        case refreshedAt
    }

    enum Columns {
        static let rowId = Column(CodingKeys.rowId.rawValue)
        static let groupId = Column(CodingKeys.groupId.rawValue)
        static let threadId = Column(CodingKeys.threadId.rawValue)
        static let masterKey = Column(CodingKeys.masterKey.rawValue)
        static let refreshedAt = Column(CodingKeys.refreshedAt.rawValue)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.rowId = try container.decode(RowId.self, forKey: .rowId)
        self.groupId = try container.decode(Data.self, forKey: .groupId)
        self.threadId = try container.decodeIfPresent(ThreadId.self, forKey: .threadId)
        self.masterKey = try container.decodeIfPresent(Data.self, forKey: .masterKey).map(GroupMasterKey.init(contents:))
        self.refreshedAt = try container.decode(Int64.self, forKey: .refreshedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.rowId, forKey: .rowId)
        try container.encode(self.groupId, forKey: .groupId)
        try container.encode(self.threadId, forKey: .threadId)
        try container.encode(self.masterKey?.serialize(), forKey: .masterKey)
        try container.encode(self.refreshedAt, forKey: .refreshedAt)
    }

    static func insertRecord(
        groupId: Data,
        threadId: TSThread.RowId?,
        masterKey: GroupMasterKey?,
        refreshedAt: Date,
        tx: DBWriteTransaction,
    ) -> Self {
        return failIfThrows {
            return try Self.fetchOne(
                tx.database,
                sql: """
                INSERT INTO \(GroupRecord.databaseTableName) (
                    \(Columns.groupId.name),
                    \(Columns.threadId.name),
                    \(Columns.masterKey.name),
                    \(Columns.refreshedAt.name)
                ) VALUES (?, ?, ?, ?) RETURNING *
                """,
                arguments: [
                    groupId,
                    threadId,
                    masterKey?.serialize(),
                    Int64(refreshedAt.timeIntervalSince1970),
                ],
            ).owsFailUnwrap("must return value or error")
        }
    }

    func deriveSecretParams() -> GroupSecretParams? {
        return failIfThrows {
            return try self.masterKey.map {
                return try GroupSecretParams.deriveFromMasterKey(groupMasterKey: $0)
            }
        }
    }

    mutating func setThreadId(_ threadId: ThreadId, tx: DBWriteTransaction) {
        self.threadId = threadId
        failIfThrows { try self.update(tx.database) }
    }

    mutating func setRefreshedAt(_ refreshedAt: Date, tx: DBWriteTransaction) {
        self.refreshedAt = Int64(refreshedAt.timeIntervalSince1970)
        failIfThrows { try self.update(tx.database) }
    }

    static func addingRefreshJitter(toDate date: Date) -> Date {
        let jitter = TimeInterval.random(in: -Constants.refreshJitter...Constants.refreshJitter)
        return date.addingTimeInterval(jitter)
    }
}
