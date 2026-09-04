//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public struct BadgeCount {
    public let unreadChatCount: UInt
    public let unreadCallsCount: UInt

    public var unreadTotalCount: UInt {
        unreadChatCount + unreadCallsCount
    }
}

public protocol BadgeCountFetcher {
    func fetchBadgeCount(tx: DBReadTransaction) -> BadgeCount
}

class BadgeCountFetcherImpl: BadgeCountFetcher {
    func fetchBadgeCount(tx: DBReadTransaction) -> BadgeCount {
        let badgeCountType: BadgeCountType
        if BuildFlags.improvedNotifications {
            badgeCountType = DependenciesBridge.shared.notificationPreferencesManager.badgeCountType(tx: tx)
        } else {
            badgeCountType = .unreadMessages
        }

        let unreadChatCount: UInt
        switch badgeCountType {
        case .unreadMessages:
            unreadChatCount = InteractionFinder.unreadCountInAllThreads(transaction: tx)
        case .unreadChats:
            unreadChatCount = InteractionFinder.unreadThreadCountInAllThreads(transaction: tx)
        }
        let unreadMissedCallCount = DependenciesBridge.shared.callRecordMissedCallManager.countUnreadMissedCalls(tx: tx)

        return BadgeCount(
            unreadChatCount: unreadChatCount,
            unreadCallsCount: unreadMissedCallCount,
        )
    }
}
