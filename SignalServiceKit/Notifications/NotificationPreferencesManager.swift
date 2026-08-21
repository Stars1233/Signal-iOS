//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public enum NotificationType: UInt {
    case noNameNoPreview = 0
    case nameNoPreview = 1
    case namePreview = 2

    public var displayName: String {
        switch self {
        case .namePreview:
            return OWSLocalizedString("NOTIFICATIONS_SENDER_AND_MESSAGE", comment: "")
        case .nameNoPreview:
            return OWSLocalizedString("NOTIFICATIONS_SENDER_ONLY", comment: "")
        case .noNameNoPreview:
            return OWSLocalizedString("NOTIFICATIONS_NONE", comment: "")
        }
    }
}

public struct NotificationPreferencesManager {
    private enum Key {
        static let previewType = "PreviewType"
        static let playSoundInForeground = "PlaySoundInForeground"
        static let messageSentSound = "MessageSentSound"
        static let shouldNotifyOfNewAccounts = "NotifyOfNewAccounts"
        static let includeMutedThreadsInBadgeCount = "IncludeMutedThreadsInBadgeCount"
        static let globalNotificationSound = "GlobalNotificationSound"
    }

    private let kvStore = NewKeyValueStore(collection: "NotificationPreferences")

    public init() {}

    // MARK: - Preview type

    public func previewType(tx: DBReadTransaction) -> NotificationType {
        let rawValue = kvStore.fetchValue(UInt64.self, forKey: Key.previewType, tx: tx)
        return rawValue.flatMap({ NotificationType(rawValue: UInt($0)) }) ?? .namePreview
    }

    public func setPreviewType(_ value: NotificationType, tx: DBWriteTransaction) {
        kvStore.writeValue(UInt64(value.rawValue), forKey: Key.previewType, tx: tx)
    }

    // MARK: - Sounds

    public func playSoundInForeground(tx: DBReadTransaction) -> Bool {
        kvStore.fetchValue(Bool.self, forKey: Key.playSoundInForeground, tx: tx) ?? true
    }

    public func setPlaySoundInForeground(_ value: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(value, forKey: Key.playSoundInForeground, tx: tx)
    }

    public func isMessageSentSoundEnabled(tx: DBReadTransaction) -> Bool {
        kvStore.fetchValue(Bool.self, forKey: Key.messageSentSound, tx: tx) ?? true
    }

    public func setIsMessageSentSoundEnabled(_ value: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(value, forKey: Key.messageSentSound, tx: tx)
    }

    // MARK: - New accounts

    public func shouldNotifyOfNewAccounts(tx: DBReadTransaction) -> Bool {
        kvStore.fetchValue(Bool.self, forKey: Key.shouldNotifyOfNewAccounts, tx: tx) ?? false
    }

    public func setShouldNotifyOfNewAccounts(_ value: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(value, forKey: Key.shouldNotifyOfNewAccounts, tx: tx)
    }

    // MARK: - Badge count

    public func includeMutedThreadsInBadgeCount(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: Key.includeMutedThreadsInBadgeCount, tx: tx) ?? false
    }

    public func setIncludeMutedThreadsInBadgeCount(_ value: Bool, tx: DBWriteTransaction) {
        kvStore.writeValue(value, forKey: Key.includeMutedThreadsInBadgeCount, tx: tx)
    }

    // MARK: - Notification sound

    public func globalNotificationSound(tx: DBReadTransaction) -> Sound {
        let soundId = kvStore.fetchValue(UInt64.self, forKey: Key.globalNotificationSound, tx: tx)
        guard let soundId else { return Sounds.defaultNotificationSound }
        return Sounds.soundForId(soundId)
    }

    public func setGlobalNotificationSound(_ sound: Sound, tx: DBWriteTransaction) {
        Logger.info("Setting global notification sound to: \(sound.displayName)")

        guard Sounds.writeFallbackNotificationSoundFile(for: sound) else {
            return
        }

        kvStore.writeValue(sound.id, forKey: Key.globalNotificationSound, tx: tx)
    }
}
