//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public protocol SVRLocalStorage: LocalKeyStorage {
    func getIsMasterKeyBackedUp(_ transaction: DBReadTransaction) -> Bool

    func getMasterKey(_ transaction: DBReadTransaction) -> MasterKey?

    // TODO: Temporary
    func getOrGenerateMasterKey(_ transaction: DBReadTransaction) -> MasterKey

    func isKeyAvailable(_ key: SVR.DerivedKey, tx: DBReadTransaction) -> Bool
}

public protocol LocalKeyStorage {

    /// Media Root Backup Key
    ///
    func getMediaRootBackupKey(tx: DBReadTransaction) -> BackupKey?
    func getOrGenerateMediaRootBackupKey(tx: DBWriteTransaction) -> BackupKey

    func setMediaRootBackupKey(
        fromRestoredBackup backupProto: BackupProto_BackupInfo,
        tx: DBWriteTransaction
    ) throws
    /// Set the MRBK found in a provisioning message.
    func setMediaRootBackupKey(
        fromProvisioningMessage provisioningMessage: ProvisionMessage,
        tx: DBWriteTransaction
    ) throws
    func setMediaRootBackupKey(
        fromKeysSyncMessage syncMessage: SSKProtoSyncMessageKeys,
        tx: DBWriteTransaction
    ) throws

    // Generic 'wipe key type' method
    func wipeMediaRootBackupKeyFromFailedProvisioning(tx: DBWriteTransaction)
}

public protocol SVRLocalStorageInternal: SVRLocalStorage {

    func getPinType(_ transaction: DBReadTransaction) -> SVR.PinType?

    func getEncodedPINVerificationString(_ transaction: DBReadTransaction) -> String?

    // Linked devices get the storage service key and store it locally. The primary doesn't do this.
    func getSyncedStorageServiceKey(_ transaction: DBReadTransaction) -> Data?

    func getSVR2MrEnclaveStringValue(_ transaction: DBReadTransaction) -> String?

    // MARK: - Setters

    func setIsMasterKeyBackedUp(_ value: Bool, _ transaction: DBWriteTransaction)

    func setMasterKey(_ value: Data?, _ transaction: DBWriteTransaction)

    func setPinType(_ value: SVR.PinType, _ transaction: DBWriteTransaction)

    func setEncodedPINVerificationString(_ value: String?, _ transaction: DBWriteTransaction)

    // Linked devices get the storage service key and store it locally. The primary doesn't do this.
    func setSyncedStorageServiceKey(_ value: Data?, _ transaction: DBWriteTransaction)

    // Linked devices get the backup key and store it locally. The primary doesn't do this.
    func setSyncedBackupKey(_ value: Data?, _ transaction: DBWriteTransaction)

    func setSVR2MrEnclaveStringValue(_ value: String?, _ transaction: DBWriteTransaction)

    // MARK: - Clearing Keys

    func clearKeys(_ transaction: DBWriteTransaction)

    // MARK: - Cleanup

    func cleanupDeadKeys(_ transaction: DBWriteTransaction)
}

/// Stores state related to SVR independent of enclave; e.g. do we have backups at all,
/// what type is our pin, etc.
internal class SVRLocalStorageImpl: SVRLocalStorageInternal {
    private let masterKeyKvStore: KeyValueStore

    public static let mediaRootBackupKeyLength: UInt = 32 /* bytes */
    private static let keyName = "mrbk"
    private let mbrkKvStore: KeyValueStore

    public init() {
        // Collection name must not be changed; matches that historically kept in KeyBackupServiceImpl.
        self.masterKeyKvStore = KeyValueStore(collection: "kOWSKeyBackupService_Keys")
        self.mbrkKvStore = KeyValueStore(collection: "MediaRootBackupKey")
    }

    // MARK: - Getters

    public func isKeyAvailable(_ key: SVR.DerivedKey, tx: DBReadTransaction) -> Bool {
        return getMasterKey(tx) != nil
    }

    public func getIsMasterKeyBackedUp(_ transaction: DBReadTransaction) -> Bool {
        return masterKeyKvStore.getBool(Keys.isMasterKeyBackedUp, defaultValue: false, transaction: transaction)
    }

    public func getMasterKey(_ transaction: DBReadTransaction) -> MasterKey? {
        guard let data = masterKeyKvStore.getData(Keys.masterKey, transaction: transaction) else {
            return nil
        }
        return MasterKeyImpl(masterKey: data)
    }

    func getOrGenerateMasterKey(_ transaction: DBReadTransaction) -> MasterKey {
        if let masterKey = getMasterKey(transaction) {
            return masterKey
        }
        return MasterKeyImpl(masterKey: Randomness.generateRandomBytes(SVR.masterKeyLengthBytes))
    }

    public func getPinType(_ transaction: DBReadTransaction) -> SVR.PinType? {
        guard let raw = masterKeyKvStore.getInt(Keys.pinType, transaction: transaction) else {
            return nil
        }
        return SVR.PinType(rawValue: raw)
    }

    public func getEncodedPINVerificationString(_ transaction: DBReadTransaction) -> String? {
        return masterKeyKvStore.getString(Keys.encodedPINVerificationString, transaction: transaction)
    }

    // Linked devices get the storage service key and store it locally. The primary doesn't do this.
    // TODO: By 10/2024, we can remove this method. Starting in 10/2023, we started sending
    // master keys in syncs. A year later, any primary that has not yet delivered a master
    // key must not have launched and is therefore deregistered; we are ok to ignore the
    // storage service key and take the master key or bust.
    public func getSyncedStorageServiceKey(_ transaction: DBReadTransaction) -> Data? {
        return masterKeyKvStore.getData(Keys.syncedStorageServiceKey, transaction: transaction)
    }

    public func getSVR2MrEnclaveStringValue(_ transaction: DBReadTransaction) -> String? {
        return masterKeyKvStore.getString(Keys.svr2MrEnclaveStringValue, transaction: transaction)
    }

    /// Manages the "Media Root Backup Key" a.k.a. "MRBK" a.k.a. "Mr Burger King".
    /// This is a key we generate once and use forever that is used to derive encryption keys
    /// for all backed-up media.
    /// The MRBK is _not_ derived from the AccountEntropyPool any of its derivatives;
    /// instead we store the MRBK in the backup proto itself. This avoids needing to rotate
    /// media uploads if the AEP or backup key/id ever changes (at time of writing, it never does);
    /// the MRBK can be left the same and put into the new backup generated with the new backups keys.

    /// Get the already-generated MRBK. Returns nil if none has been set. If you require an MRBK
    /// (e.g. you are creating a backup), use ``getOrGenerateMediaRootBackupKey``.
    public func getMediaRootBackupKey(tx: DBReadTransaction) -> BackupKey? {
        guard let data = mbrkKvStore.getData(Self.keyName, transaction: tx) else {
            return nil
        }
        // TODO: Log error?
        return try! BackupKey(contents: Array(data))
    }

    /// Get the already-generated MRBK or, if one has not been generated, generate one.
    /// WARNING: this method should only be called _after_ restoring or choosing not to restore
    /// from an existing backup; calling this generates a new key and invalidates all media backups.
    public func getOrGenerateMediaRootBackupKey(tx: DBWriteTransaction) -> BackupKey {
        if let value = getMediaRootBackupKey(tx: tx) {
            return value
        }
        let newValue = Randomness.generateRandomBytes(Self.mediaRootBackupKeyLength)
        mbrkKvStore.setData(newValue, key: Self.keyName, transaction: tx)
        return try! BackupKey(contents: Array(newValue))
    }

    // MARK: - Setters

    public func setIsMasterKeyBackedUp(_ value: Bool, _ transaction: DBWriteTransaction) {
        masterKeyKvStore.setBool(value, key: Keys.isMasterKeyBackedUp, transaction: transaction)
    }

    public func setMasterKey(_ value: Data?, _ transaction: DBWriteTransaction) {
        masterKeyKvStore.setData(value, key: Keys.masterKey, transaction: transaction)
    }

    public func setPinType(_ value: SVR.PinType, _ transaction: DBWriteTransaction) {
        masterKeyKvStore.setInt(value.rawValue, key: Keys.pinType, transaction: transaction)
    }

    public func setEncodedPINVerificationString(_ value: String?, _ transaction: DBWriteTransaction) {
        masterKeyKvStore.setString(value, key: Keys.encodedPINVerificationString, transaction: transaction)
    }

    // Linked devices get the storage service key and store it locally. The primary doesn't do this.
    public func setSyncedStorageServiceKey(_ value: Data?, _ transaction: DBWriteTransaction) {
        masterKeyKvStore.setData(value, key: Keys.syncedStorageServiceKey, transaction: transaction)
    }

    // Linked devices get the backup key and store it locally. The primary doesn't do this.
    public func setSyncedBackupKey(_ value: Data?, _ transaction: DBWriteTransaction) {
        masterKeyKvStore.setData(value, key: Keys.syncedBackupKey, transaction: transaction)
    }

    public func setSVR2MrEnclaveStringValue(_ value: String?, _ transaction: DBWriteTransaction) {
        masterKeyKvStore.setString(value, key: Keys.svr2MrEnclaveStringValue, transaction: transaction)
    }

    /// Set the MRBK found in a backup at restore time.
    public func setMediaRootBackupKey(
        fromRestoredBackup backupProto: BackupProto_BackupInfo,
        tx: DBWriteTransaction
    ) throws {
        guard let mrbk = backupProto.mediaRootBackupKey.nilIfEmpty else {
            // TODO: [Backups] fail if MRBK unset
            return
        }
        try setMediaRootBackupKey(mrbk, tx: tx)
    }

    /// Set the MRBK found in a provisioning message.
    public func setMediaRootBackupKey(
        fromProvisioningMessage provisioningMessage: ProvisionMessage,
        tx: DBWriteTransaction
    ) throws {
        guard let mrbk = provisioningMessage.mrbk else { return }
        try setMediaRootBackupKey(mrbk, tx: tx)
    }

    public func setMediaRootBackupKey(
        fromKeysSyncMessage syncMessage: SSKProtoSyncMessageKeys,
        tx: DBWriteTransaction
    ) throws {
        guard let mrbk = syncMessage.mediaRootBackupKey?.nilIfEmpty else {
            return
        }
        try setMediaRootBackupKey(mrbk, tx: tx)
    }

    public func wipeMediaRootBackupKeyFromFailedProvisioning(tx: DBWriteTransaction) {
        mbrkKvStore.removeValue(forKey: Self.keyName, transaction: tx)
    }

    private func setMediaRootBackupKey(
        _ mrbk: Data,
        tx: DBWriteTransaction
    ) throws {
        guard mrbk.byteLength == Self.mediaRootBackupKeyLength else {
            throw OWSAssertionError("Invalid MRBK length!")
        }
        mbrkKvStore.setData(mrbk, key: Self.keyName, transaction: tx)
    }

    // MARK: - Clearing Keys

    public func clearKeys(_ transaction: DBWriteTransaction) {
        masterKeyKvStore.removeValues(
            forKeys: [
                Keys.masterKey,
                Keys.pinType,
                Keys.encodedPINVerificationString,
                Keys.isMasterKeyBackedUp,
                Keys.syncedStorageServiceKey,
                Keys.legacy_svr1EnclaveName,
                Keys.svr2MrEnclaveStringValue
            ],
            transaction: transaction
        )

        mbrkKvStore.removeValue(forKey: Self.keyName, transaction: transaction)
    }

    // MARK: - Cleanup

    func cleanupDeadKeys(_ transaction: any DBWriteTransaction) {
        masterKeyKvStore.removeValues(
            forKeys: [
                Keys.legacy_svr1EnclaveName,
            ],
            transaction: transaction
        )
    }

    // MARK: - Identifiers

    private enum Keys {
        // These must not change, they match what was historically in KeyBackupServiceImpl.
        static let masterKey = "masterKey"
        static let pinType = "pinType"
        static let encodedPINVerificationString = "encodedVerificationString"
        static let isMasterKeyBackedUp = "isMasterKeyBackedUp"
        static let syncedStorageServiceKey = "Storage Service Encryption"
        static let syncedBackupKey = "Backup Key"
        // Kept around because its existence indicates we had an svr1 backup.
        // TODO: Remove after Nov 1, 2024
        static let legacy_svr1EnclaveName = "enclaveName"
        static let svr2MrEnclaveStringValue = "svr2_mrenclaveStringValue"
    }
}

#if TESTABLE_BUILD
public class SVRLocalStorageMock: SVRLocalStorage {

    var isMasterKeyBackedUp: Bool = false
    var masterKey: MasterKeyMock?
    var mediaRootBackupKey: Data?

    public func getMediaRootBackupKey(tx: any DBReadTransaction) -> BackupKey? {
        guard let mediaRootBackupKey else { return nil }
        return try! BackupKey(contents: Array(mediaRootBackupKey))
    }

    public func getOrGenerateMediaRootBackupKey(tx: any DBWriteTransaction) -> BackupKey {
        guard let mediaRootBackupKey = getMediaRootBackupKey(tx: tx) else {
            fatalError("not implemented")
        }
        return mediaRootBackupKey
    }

    public func setMediaRootBackupKey(fromRestoredBackup backupProto: BackupProto_BackupInfo, tx: any DBWriteTransaction) throws {
        mediaRootBackupKey = backupProto.mediaRootBackupKey
    }

    public func setMediaRootBackupKey(fromProvisioningMessage provisioningMessage: ProvisionMessage, tx: any DBWriteTransaction) throws {
        mediaRootBackupKey = provisioningMessage.mrbk
    }

    public func setMediaRootBackupKey(fromKeysSyncMessage syncMessage: SSKProtoSyncMessageKeys, tx: any DBWriteTransaction) throws {
        mediaRootBackupKey = syncMessage.mediaRootBackupKey
    }

    public func wipeMediaRootBackupKeyFromFailedProvisioning(tx: any DBWriteTransaction) {
        fatalError("not implemented")
    }

    public func getIsMasterKeyBackedUp(_ transaction: DBReadTransaction) -> Bool {
        return isMasterKeyBackedUp
    }

    public func getMasterKey(_ transaction: DBReadTransaction) -> MasterKey? {
        return masterKey
    }

    public func getOrGenerateMasterKey(_ transaction: DBReadTransaction) -> MasterKey {
        return masterKey!
    }

    public func isKeyAvailable(_ key: SVR.DerivedKey, tx: DBReadTransaction) -> Bool {
        return masterKey != nil
    }
}
#endif
