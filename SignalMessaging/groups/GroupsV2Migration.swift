//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import ZKGroup
import HKDFKit

public class GroupsV2Migration {

    // MARK: - Dependencies

    private static var tsAccountManager: TSAccountManager {
        return TSAccountManager.shared()
    }

    private static var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private static var profileManager: OWSProfileManager {
        return OWSProfileManager.shared()
    }

    private static var groupsV2: GroupsV2Impl {
        return SSKEnvironment.shared.groupsV2 as! GroupsV2Impl
    }

    // MARK: -

    private init() {}

    // MARK: - Mapping

    public static func v2GroupId(forV1GroupId v1GroupId: Data) throws -> Data {
        try calculateMigrationMetadata(forV1GroupId: v1GroupId).v2GroupId
    }

    public static func v2MasterKey(forV1GroupId v1GroupId: Data) throws -> Data {
        try calculateMigrationMetadata(forV1GroupId: v1GroupId).v2MasterKey
    }
}

// MARK: -

public extension GroupsV2Migration {

    // MARK: -

    static func tryManualMigration(groupThread: TSGroupThread) -> Promise<TSGroupThread> {
        guard FeatureFlags.groupsV2MigrationManualMigrationPolite ||
            FeatureFlags.groupsV2MigrationManualMigrationAggressive else {
                return Promise(error: OWSAssertionError("Manual migration not enabled."))
        }
        return tryToMigrate(groupThread: groupThread, migrationMode: manualMigrationMode)
    }

    // If there is a v1 group in the database that can be
    // migrated to a v2 group, try to migrate it to a v2
    // group. It might or might not already be migrated on
    // the service.
    static func tryToMigrate(groupThread: TSGroupThread,
                             migrationMode: GroupsV2MigrationMode) -> Promise<TSGroupThread> {
        firstly(on: .global()) {
            Self.databaseStorage.read { transaction in
                Self.canGroupBeMigratedByLocalUser(groupThread: groupThread,
                                                   migrationMode: migrationMode,
                                                   transaction: transaction)
            }
        }.then(on: .global()) { (canGroupBeMigrated: Bool) -> Promise<TSGroupThread> in
            guard canGroupBeMigrated else {
                throw OWSGenericError("Group can not be migrated.")
            }
            return Self.localMigrationAttempt(groupId: groupThread.groupModel.groupId,
                                              migrationMode: migrationMode)
        }
    }

    // If there is a corresponding v1 group in the local database,
    // update it to reflect the v1 group already on the service.
    static func updateAlreadyMigratedGroupIfNecessary(v2GroupId: Data) -> Promise<Void> {
        firstly(on: .global()) { () -> Promise<Void> in
            guard let groupThread = (Self.databaseStorage.read { transaction in
                TSGroupThread.fetch(groupId: v2GroupId, transaction: transaction)
            }) else {
                // No need to migrate; not in database.
                return Promise.value(())
            }
            guard groupThread.isGroupV1Thread else {
                // No need to migrate; not a v1 group.
                return Promise.value(())
            }

            return firstly(on: .global()) { () -> Promise<TSGroupThread> in
                Self.localMigrationAttempt(groupId: v2GroupId,
                                           migrationMode: .alreadyMigratedOnService)
            }.asVoid()
        }
    }

    static func migrationInfoForManualMigration(groupThread: TSGroupThread) -> GroupsV2MigrationInfo {
        databaseStorage.read { transaction in
            migrationInfoForManualMigration(groupThread: groupThread,
                                            transaction: transaction)
        }
    }

    // Will return nil if the group cannot be migrated by the local
    // user for any reason.
    static func migrationInfoForManualMigration(groupThread: TSGroupThread,
                                                transaction: SDSAnyReadTransaction) -> GroupsV2MigrationInfo {

        guard FeatureFlags.groupsV2MigrationManualMigrationPolite ||
            FeatureFlags.groupsV2MigrationManualMigrationAggressive else {
                return .buildCannotBeMigrated(state: .cantBeMigrated_FeatureNotEnabled)
        }
        return migrationInfo(groupThread: groupThread,
                             migrationMode: manualMigrationMode,
                             transaction: transaction)
    }

    private static var manualMigrationMode: GroupsV2MigrationMode {
        owsAssertDebug(FeatureFlags.groupsV2MigrationManualMigrationPolite ||
            FeatureFlags.groupsV2MigrationManualMigrationAggressive)

        return (FeatureFlags.groupsV2MigrationManualMigrationAggressive
            ? .manualMigrationAggressive
            : .manualMigrationPolite)
    }

    private static var autoMigrationMode: GroupsV2MigrationMode {
        owsAssertDebug(FeatureFlags.groupsV2MigrationAutoMigrationPolite ||
            FeatureFlags.groupsV2MigrationAutoMigrationAggressive)

        return (FeatureFlags.groupsV2MigrationAutoMigrationAggressive
            ? .manualMigrationAggressive
            : .manualMigrationPolite)
    }
}

// MARK: -

fileprivate extension GroupsV2Migration {

    // groupId might be the v1 or v2 group id.
    static func localMigrationAttempt(groupId: Data,
                                      migrationMode: GroupsV2MigrationMode) -> Promise<TSGroupThread> {

        return firstly(on: .global()) { () -> Promise<Void> in
            return GroupManager.ensureLocalProfileHasCommitmentIfNecessary()
        }.map(on: .global()) { () -> UnmigratedState in
            try Self.loadUnmigratedState(groupId: groupId)
        }.then(on: .global()) { (unmigratedState: UnmigratedState) -> Promise<UnmigratedState> in
            firstly {
                Self.tryToFillInMissingUuids(unmigratedState: unmigratedState)
            }.map(on: .global()) {
                return unmigratedState
            }
        }.then(on: .global()) { (unmigratedState: UnmigratedState) -> Promise<TSGroupThread> in
            addMigratingV2GroupId(unmigratedState.migrationMetadata.v1GroupId)
            addMigratingV2GroupId(unmigratedState.migrationMetadata.v2GroupId)

            return firstly(on: .global()) { () -> Promise<TSGroupThread> in
                attemptToMigrateByPullingFromService(unmigratedState: unmigratedState,
                                                     migrationMode: migrationMode)
            }.recover(on: .global()) { (error: Error) -> Promise<TSGroupThread> in
                if case GroupsV2Error.groupDoesNotExistOnService = error,
                migrationMode.canMigrateToService {
                    // If the group is not already on the service, try to
                    // migrate by creating on the service.
                    return attemptToMigrateByCreatingOnService(unmigratedState: unmigratedState,
                                                               migrationMode: migrationMode)
                } else {
                    throw error
                }
            }
        }
    }

    static func tryToFillInMissingUuids(unmigratedState: UnmigratedState) -> Promise<Void> {
        let groupMembership = unmigratedState.groupThread.groupModel.groupMembership
        let membersToMigrate = membersToTryToMigrate(groupMembership: groupMembership)
        let phoneNumbersWithoutUuids = membersToMigrate.compactMap { (address: SignalServiceAddress) -> String? in
            if address.uuid != nil {
                return nil
            }
            return address.phoneNumber
        }
        guard !phoneNumbersWithoutUuids.isEmpty else {
            return Promise.value(())
        }

        Logger.info("Trying to fill in missing uuids: \(phoneNumbersWithoutUuids.count)")

        let discoveryTask = ContactDiscoveryTask(phoneNumbers: Set(phoneNumbersWithoutUuids))
        return discoveryTask.perform().asVoid()
    }

    static func attemptToMigrateByPullingFromService(unmigratedState: UnmigratedState,
                                                     migrationMode: GroupsV2MigrationMode) -> Promise<TSGroupThread> {

        return firstly(on: .global()) { () -> Promise<GroupV2Snapshot> in
            let groupSecretParamsData = unmigratedState.migrationMetadata.v2GroupSecretParams
            return self.groupsV2.fetchCurrentGroupV2Snapshot(groupSecretParamsData: groupSecretParamsData)
        }.recover(on: .global()) { (error: Error) -> Promise<GroupV2Snapshot> in
            if case GroupsV2Error.groupDoesNotExistOnService = error {
                // Convert error if the group is not already on the service.
                throw GroupsV2Error.groupDoesNotExistOnService
            } else {
                throw error
            }
        }.then(on: .global()) { (snapshot: GroupV2Snapshot) throws -> Promise<TSGroupThread> in
            self.migrateGroupUsingSnapshot(unmigratedState: unmigratedState,
                                           groupV2Snapshot: snapshot)
        }.timeout(seconds: GroupManager.groupUpdateTimeoutDuration,
                  description: "Migrate group from service") {
                    GroupsV2Error.timeout
        }
    }

    static func migrateGroupUsingSnapshot(unmigratedState: UnmigratedState,
                                          groupV2Snapshot: GroupV2Snapshot) -> Promise<TSGroupThread> {
        let localProfileKey = profileManager.localProfileKey()
        guard let localUuid = tsAccountManager.localUuid else {
            return Promise(error: OWSAssertionError("Missing localUuid."))
        }

        return firstly(on: .global()) { () -> TSGroupModelV2 in
            try self.databaseStorage.read { transaction in
                let builder = try TSGroupModelBuilder(groupV2Snapshot: groupV2Snapshot)
                return try builder.buildAsV2(transaction: transaction)
            }
        }.then(on: .global()) { (newGroupModelV2: TSGroupModelV2) throws -> Promise<TSGroupThread> in
            let newDisappearingMessageToken = groupV2Snapshot.disappearingMessageToken
            // groupUpdateSourceAddress is nil because we don't know the
            // author(s) of changes reflected in the snapshot.
            let groupUpdateSourceAddress: SignalServiceAddress? = nil

            return GroupManager.replaceMigratedGroup(groupIdV1: unmigratedState.groupThread.groupModel.groupId,
                                                     groupModelV2: newGroupModelV2,
                                                     disappearingMessageToken: newDisappearingMessageToken,
                                                     groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                     shouldSendMessage: false)
        }.map(on: .global()) { (groupThread: TSGroupThread) throws -> TSGroupThread in
            GroupManager.storeProfileKeysFromGroupProtos(groupV2Snapshot.profileKeys)

            // If the group state includes a stale profile key for the
            // local user, schedule an update to fix that.
            if let profileKey = groupV2Snapshot.profileKeys[localUuid],
                profileKey != localProfileKey.keyData {
                self.databaseStorage.write { transaction in
                    self.groupsV2.updateLocalProfileKeyInGroup(groupId: groupThread.groupModel.groupId,
                                                               transaction: transaction)
                }
            }

            return groupThread
        }
    }

    static func attemptToMigrateByCreatingOnService(unmigratedState: UnmigratedState,
                                                    migrationMode: GroupsV2MigrationMode) -> Promise<TSGroupThread> {

        return firstly(on: .global()) { () -> Promise<TSGroupThread> in
            let groupThread = unmigratedState.groupThread
            guard groupThread.isLocalUserFullMember else {
                throw OWSAssertionError("Local user cannot migrate group; is not a full member.")
            }
            let membersToMigrate = membersToTryToMigrate(groupMembership: groupThread.groupMembership)

            return firstly(on: .global()) { () -> Promise<Void> in
                GroupManager.tryToEnableGroupsV2(for: Array(membersToMigrate), isBlocking: true, ignoreErrors: true)
            }.then(on: .global()) { () throws -> Promise<Void> in
                self.groupsV2.tryToEnsureProfileKeyCredentials(for: Array(membersToMigrate))
            }.then(on: .global()) { () throws -> Promise<String?> in
                guard let avatarData = unmigratedState.groupThread.groupModel.groupAvatarData else {
                    // No avatar to upload.
                    return Promise.value(nil)
                }
                // Upload avatar.
                return firstly(on: .global()) { () -> Promise<String> in
                    return self.groupsV2.uploadGroupAvatar(avatarData: avatarData,
                                                           groupSecretParamsData: unmigratedState.migrationMetadata.v2GroupSecretParams)
                }.map(on: .global()) { (avatarUrlPath: String) -> String? in
                    return avatarUrlPath
                }
            }.map(on: .global()) { (avatarUrlPath: String?) throws -> TSGroupModelV2 in
                try databaseStorage.read { transaction in
                    try Self.deriveMigratedGroupModel(unmigratedState: unmigratedState,
                                                      avatarUrlPath: avatarUrlPath,
                                                      migrationMode: migrationMode,
                                                      transaction: transaction)
                }
            }.then(on: .global()) { (proposedGroupModel: TSGroupModelV2) -> Promise<TSGroupModelV2> in
                Self.migrateGroupOnService(proposedGroupModel: proposedGroupModel,
                                           disappearingMessageToken: unmigratedState.disappearingMessageToken)
            }.then(on: .global()) { (groupModelV2: TSGroupModelV2) -> Promise<TSGroupThread> in
                guard let localAddress = tsAccountManager.localAddress else {
                    throw OWSAssertionError("Missing localAddress.")
                }
                return GroupManager.replaceMigratedGroup(groupIdV1: unmigratedState.groupThread.groupModel.groupId,
                                                         groupModelV2: groupModelV2,
                                                         disappearingMessageToken: unmigratedState.disappearingMessageToken,
                                                         groupUpdateSourceAddress: localAddress,
                                                         shouldSendMessage: true)
            }.map(on: .global()) { (groupThread: TSGroupThread) -> TSGroupThread in
                self.profileManager.addThread(toProfileWhitelist: groupThread)
                return groupThread
            }.timeout(seconds: GroupManager.groupUpdateTimeoutDuration,
                      description: "Migrate group") {
                        GroupsV2Error.timeout
            }
        }
    }

    static func deriveMigratedGroupModel(unmigratedState: UnmigratedState,
                                         avatarUrlPath: String?,
                                         migrationMode: GroupsV2MigrationMode,
                                         transaction: SDSAnyReadTransaction) throws -> TSGroupModelV2 {

        guard let localAddress = tsAccountManager.localAddress else {
            throw OWSAssertionError("Missing localAddress.")
        }
        guard let localUuid = localAddress.uuid else {
            throw OWSAssertionError("Missing localUuid.")
        }
        let v1GroupThread = unmigratedState.groupThread
        let v1GroupModel = v1GroupThread.groupModel
        guard v1GroupModel.groupsVersion == .V1 else {
            throw OWSAssertionError("Invalid group version: \(v1GroupModel.groupsVersion.rawValue).")
        }
        let migrationMetadata = unmigratedState.migrationMetadata
        let v2GroupId = migrationMetadata.v2GroupId
        let v2GroupSecretParams = migrationMetadata.v2GroupSecretParams

        var groupModelBuilder = v1GroupModel.asBuilder

        groupModelBuilder.groupId = v2GroupId
        groupModelBuilder.groupAccess = GroupAccess.defaultForV2
        groupModelBuilder.groupsVersion = .V2
        groupModelBuilder.groupV2Revision = 0
        groupModelBuilder.groupSecretParamsData = v2GroupSecretParams
        groupModelBuilder.newGroupSeed = nil
        groupModelBuilder.isPlaceholderModel = false

        // We should either have both avatarData and avatarUrlPath or neither.
        if let avatarData = v1GroupModel.groupAvatarData,
            let avatarUrlPath = avatarUrlPath {
            groupModelBuilder.avatarData = avatarData
            groupModelBuilder.avatarUrlPath = avatarUrlPath
        } else {
            owsAssertDebug(v1GroupModel.groupAvatarData == nil)
            owsAssertDebug(avatarUrlPath == nil)
            groupModelBuilder.avatarData = nil
            groupModelBuilder.avatarUrlPath = nil
        }

        // Build member list.
        //
        // The group creator is an administrator;
        // the other members are normal users.
        var v2MembershipBuilder = GroupMembership.Builder()
        let membersToMigrate = membersToTryToMigrate(groupMembership: v1GroupModel.groupMembership)
        for address in membersToMigrate {
            guard address.uuid != nil else {
                Logger.warn("Member missing uuid: \(address).")
                owsAssertDebug(migrationMode.canSkipMembersWithoutUuids)
                Logger.warn("Discarding member: \(address).")
                continue
            }

            if !GroupManager.doesUserHaveGroupsV2Capability(address: address,
                                                            transaction: transaction) {
                Logger.warn("Member without Groups v2 capability: \(address).")
                owsAssertDebug(migrationMode.canSkipMembersWithoutCapabilities)
                continue
            }
            if !GroupManager.doesUserHaveGroupsV2MigrationCapability(address: address,
                                                            transaction: transaction) {
                Logger.warn("Member without migration capability: \(address).")
                owsAssertDebug(migrationMode.canSkipMembersWithoutCapabilities)
                continue
            }

            var isInvited = false
            if !groupsV2.hasProfileKeyCredential(for: address, transaction: transaction) {
                Logger.warn("Inviting user with unknown profile key: \(address).")
                owsAssertDebug(migrationMode.canInviteMembersWithoutProfileKey)
                isInvited = true
            }

            // All migrated members become admins.
            let role: TSGroupMemberRole = .administrator

            if isInvited {
                v2MembershipBuilder.addInvitedMember(address, role: role, addedByUuid: localUuid)
            } else {
                v2MembershipBuilder.addFullMember(address, role: role)
            }
        }

        v2MembershipBuilder.remove(localAddress)
        v2MembershipBuilder.addFullMember(localAddress, role: .administrator)
        groupModelBuilder.groupMembership = v2MembershipBuilder.build()

        groupModelBuilder.addedByAddress = nil

        return try groupModelBuilder.buildAsV2(transaction: transaction)
    }

    static func migrateGroupOnService(proposedGroupModel: TSGroupModelV2,
                                      disappearingMessageToken: DisappearingMessageToken) -> Promise<TSGroupModelV2> {
        return firstly {
            self.groupsV2.createNewGroupOnService(groupModel: proposedGroupModel,
                                                  disappearingMessageToken: disappearingMessageToken)
        }.then(on: .global()) { _ in
            self.groupsV2.fetchCurrentGroupV2Snapshot(groupModel: proposedGroupModel)
        }.map(on: .global()) { (groupV2Snapshot: GroupV2Snapshot) throws -> TSGroupModelV2 in
            let createdGroupModel = try self.databaseStorage.read { (transaction) throws -> TSGroupModelV2 in
                let groupModelBuilder = try TSGroupModelBuilder(groupV2Snapshot: groupV2Snapshot)
                return try groupModelBuilder.buildAsV2(transaction: transaction)
            }
            if proposedGroupModel != createdGroupModel {
                Logger.verbose("proposedGroupModel: \(proposedGroupModel.debugDescription)")
                Logger.verbose("createdGroupModel: \(createdGroupModel.debugDescription)")
                if DebugFlags.groupsV2ignoreCorruptInvites {
                    Logger.warn("Proposed group model does not match created group model.")
                } else {
                    owsFailDebug("Proposed group model does not match created group model.")
                }
            }
            return createdGroupModel
        }
    }

    static func canGroupBeMigratedByLocalUser(groupThread: TSGroupThread,
                                              migrationMode: GroupsV2MigrationMode,
                                              transaction: SDSAnyReadTransaction) -> Bool {
        migrationInfo(groupThread: groupThread,
                      migrationMode: migrationMode,
                      transaction: transaction).canGroupBeMigrated
    }

    // This method might be called for any group (v1 or v2).
    // It returns a description of whether the group can be
    // migrated, and if so under what conditions.
    //
    // Will return nil if the group cannot be migrated by the local
    // user for any reason.
    static func migrationInfo(groupThread: TSGroupThread,
                              migrationMode: GroupsV2MigrationMode,
                              transaction: SDSAnyReadTransaction) -> GroupsV2MigrationInfo {

        guard groupThread.isGroupV1Thread else {
            return .buildCannotBeMigrated(state: .cantBeMigrated_NotAV1Group)
        }
        let isLocalUserFullMember = groupThread.isLocalUserFullMember

        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("Missing localAddress.")
            return .buildCannotBeMigrated(state: .cantBeMigrated_NotRegistered)
        }

        let isGroupInProfileWhitelist = profileManager.isThread(inProfileWhitelist: groupThread,
                                                                transaction: transaction)

        let groupMembership = groupThread.groupModel.groupMembership
        let membersToMigrate = membersToTryToMigrate(groupMembership: groupMembership)

        // Inspect member list.
        //
        // The group creator is an administrator;
        // the other members are normal users.
        var membersWithoutUuids = [SignalServiceAddress]()
        var membersWithoutCapabilities = [SignalServiceAddress]()
        var membersWithoutProfileKeys = [SignalServiceAddress]()
        var membersMigrated = [SignalServiceAddress]()
        for address in membersToMigrate {
            if address.isEqualToAddress(localAddress) {
                continue
            }

            guard nil != address.uuid else {
                Logger.warn("Member without uuid: \(address).")
                membersWithoutUuids.append(address)
                continue
            }

            if !GroupManager.doesUserHaveGroupsV2Capability(address: address,
                                                            transaction: transaction) {
                Logger.warn("Member without Groups v2 capability: \(address).")
                membersWithoutCapabilities.append(address)
                continue
            }
            if !GroupManager.doesUserHaveGroupsV2MigrationCapability(address: address,
                                                                     transaction: transaction) {
                Logger.warn("Member without migration capability: \(address).")
                membersWithoutCapabilities.append(address)
                continue
            }

            membersMigrated.append(address)

            if !groupsV2.hasProfileKeyCredential(for: address, transaction: transaction) {
                Logger.warn("Member without profile key: \(address).")
                membersWithoutProfileKeys.append(address)
                continue
            }
        }

        let hasTooManyMembers = membersMigrated.count > GroupManager.groupsV2MaxGroupSizeHardLimit

        let state: GroupsV2MigrationState = {
            if !migrationMode.canMigrateIfNotMember,
                !isLocalUserFullMember {
                return .cantBeMigrated_LocalUserIsNotAMember
            }
            if !migrationMode.canMigrateIfNotInProfileWhitelist,
                !isGroupInProfileWhitelist {
                return .cantBeMigrated_NotInProfileWhitelist
            }
            if !migrationMode.canSkipMembersWithoutUuids,
                !membersWithoutUuids.isEmpty {
                return .cantBeMigrated_MembersWithoutUuids
            }
            if !migrationMode.canSkipMembersWithoutCapabilities,
                !membersWithoutCapabilities.isEmpty {
                return .cantBeMigrated_MembersWithoutCapabilities
            }
            if !migrationMode.canInviteMembersWithoutProfileKey,
                !membersWithoutProfileKeys.isEmpty {
                return .cantBeMigrated_MembersWithoutProfileKey
            }
            if !migrationMode.canMigrateWithTooManyMembers,
                hasTooManyMembers {
                return .cantBeMigrated_TooManyMembers
            }
            return .canBeMigrated
        }()

        return GroupsV2MigrationInfo(isGroupInProfileWhitelist: isGroupInProfileWhitelist,
                                     membersWithoutUuids: membersWithoutUuids,
                                     membersWithoutCapabilities: membersWithoutCapabilities,
                                     membersWithoutProfileKeys: membersWithoutProfileKeys,
                                     state: state)
    }

    static func membersToTryToMigrate(groupMembership: GroupMembership) -> Set<SignalServiceAddress> {

        let allMembers = groupMembership.allMembersOfAnyKind
        let addressesWithoutUuids = Array(allMembers).filter { $0.uuid == nil }
        let knownUndiscoverable = Set(ContactDiscoveryTask.addressesRecentlyMarkedAsUndiscoverableForGroupMigrations(addressesWithoutUuids))

        var result = Set<SignalServiceAddress>()
        for address in allMembers {
            if nil == address.uuid, knownUndiscoverable.contains(address) {
                Logger.warn("Ignoring unregistered member without uuid: \(address).")
                continue
            }
            result.insert(address)
        }
        return result
    }
}

// MARK: -

public enum GroupsV2MigrationState {
    case canBeMigrated
    case cantBeMigrated_FeatureNotEnabled
    case cantBeMigrated_NotAV1Group
    case cantBeMigrated_NotRegistered
    case cantBeMigrated_LocalUserIsNotAMember
    case cantBeMigrated_NotInProfileWhitelist
    case cantBeMigrated_TooManyMembers
    case cantBeMigrated_MembersWithoutUuids
    case cantBeMigrated_MembersWithoutCapabilities
    case cantBeMigrated_MembersWithoutProfileKey
}

// MARK: -

public struct GroupsV2MigrationInfo {
    // These properties only have valid values if canGroupBeMigrated is true.
    public let isGroupInProfileWhitelist: Bool
    public let membersWithoutUuids: [SignalServiceAddress]
    public let membersWithoutCapabilities: [SignalServiceAddress]
    public let membersWithoutProfileKeys: [SignalServiceAddress]

    // Always consult this property first.
    public let state: GroupsV2MigrationState

    public var canGroupBeMigrated: Bool {
        state == .canBeMigrated
    }

    fileprivate static func buildCannotBeMigrated(state: GroupsV2MigrationState) -> GroupsV2MigrationInfo {
        GroupsV2MigrationInfo(isGroupInProfileWhitelist: false,
                              membersWithoutUuids: [],
                              membersWithoutCapabilities: [],
                              membersWithoutProfileKeys: [],
                              state: state)
    }
}

// MARK: -

public enum GroupsV2MigrationMode {
    // TODO: We may want to rename polite/aggressive to
    // auto-migration/manual-migration.
    case manualMigrationPolite
    case manualMigrationAggressive
    case autoMigrationPolite
    case autoMigrationAggressive
    case alreadyMigratedOnService

    private var isManualMigration: Bool {
        self == .manualMigrationPolite || self == .manualMigrationAggressive
    }

    private var isAutoMigration: Bool {
        self == .autoMigrationPolite || self == .autoMigrationAggressive
    }

    private var isPolite: Bool {
        self == .manualMigrationPolite || self == .autoMigrationPolite
    }

    private var isAggressive: Bool {
        self == .manualMigrationAggressive || self == .autoMigrationAggressive
    }

    private var isAlreadyMigratedOnService: Bool {
        self == .alreadyMigratedOnService
    }

    public var canSkipMembersWithoutUuids: Bool {
        isAggressive || isAlreadyMigratedOnService
    }

    public var canSkipMembersWithoutCapabilities: Bool {
        isAggressive || isAlreadyMigratedOnService
    }

    public var canInviteMembersWithoutProfileKey: Bool {
        isManualMigration || isAggressive || isAlreadyMigratedOnService
    }

    public var canMigrateIfNotInProfileWhitelist: Bool {
        // TODO: What about manual?
        isAlreadyMigratedOnService
    }

    public var canMigrateToService: Bool {
        !isAlreadyMigratedOnService
    }

    public var canMigrateIfNotMember: Bool {
        isAlreadyMigratedOnService
    }

    public var canMigrateWithTooManyMembers: Bool {
        isAlreadyMigratedOnService
    }
}

// MARK: -

extension GroupsV2Migration {

    // MARK: - Migrating Group Ids

    // We track migrating group ids for usage in asserts.
    private static let unfairLock = UnfairLock()
    private static var migratingV2GroupIds = Set<Data>()

    private static func addMigratingV2GroupId(_ groupId: Data) {
        _ = unfairLock.withLock {
            migratingV2GroupIds.insert(groupId)
        }
    }

    public static func isMigratingV2GroupId(_ groupId: Data) -> Bool {
        unfairLock.withLock {
            migratingV2GroupIds.contains(groupId)
        }
    }
}

// MARK: -

fileprivate extension GroupsV2Migration {

    // MARK: - Mapping

    static func gv2MasterKey(forV1GroupId v1GroupId: Data) throws -> Data {
        guard GroupManager.isValidGroupId(v1GroupId, groupsVersion: .V1) else {
            throw OWSAssertionError("Invalid v1 group id.")
        }
        guard let migrationInfo: Data = "GV2 Migration".data(using: .utf8) else {
            throw OWSAssertionError("Couldn't convert info data.")
        }
        let salt = Data(repeating: 0, count: 32)
        let masterKeyLength: Int32 = Int32(GroupMasterKey.SIZE)
        let masterKey =
            try HKDFKit.deriveKey(v1GroupId, info: migrationInfo, salt: salt, outputSize: masterKeyLength)
        guard masterKey.count == masterKeyLength else {
            throw OWSAssertionError("Invalid master key.")
        }
        return masterKey
    }

    // MARK: -

    struct MigrationMetadata {
        let v1GroupId: Data
        let v2GroupId: Data
        let v2MasterKey: Data
        let v2GroupSecretParams: Data
    }

    private static func calculateMigrationMetadata(forV1GroupId v1GroupId: Data) throws -> MigrationMetadata {
        guard GroupManager.isValidGroupId(v1GroupId, groupsVersion: .V1) else {
            throw OWSAssertionError("Invalid group id: \(v1GroupId.hexadecimalString).")
        }
        let masterKey = try gv2MasterKey(forV1GroupId: v1GroupId)
        let v2GroupSecretParams = try groupsV2.groupSecretParamsData(forMasterKeyData: masterKey)
        let v2GroupId = try groupsV2.groupId(forGroupSecretParamsData: v2GroupSecretParams)
        return MigrationMetadata(v1GroupId: v1GroupId,
                                 v2GroupId: v2GroupId,
                                 v2MasterKey: masterKey,
                                 v2GroupSecretParams: v2GroupSecretParams)
    }

    private static func calculateMigrationMetadata(for v1GroupModel: TSGroupModel) throws -> MigrationMetadata {
        guard v1GroupModel.groupsVersion == .V1 else {
            throw OWSAssertionError("Invalid group version: \(v1GroupModel.groupsVersion.rawValue).")
        }
        return try calculateMigrationMetadata(forV1GroupId: v1GroupModel.groupId)
    }

    struct UnmigratedState {
        let groupThread: TSGroupThread
        let disappearingMessagesConfiguration: OWSDisappearingMessagesConfiguration
        let migrationMetadata: MigrationMetadata

        var disappearingMessageToken: DisappearingMessageToken {
            disappearingMessagesConfiguration.asToken
        }
    }

    private static func loadUnmigratedState(groupId: Data) throws -> UnmigratedState {
        try databaseStorage.read { transaction in
            guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                throw OWSAssertionError("Missing group thread.")
            }
            guard groupThread.groupModel.groupsVersion == .V1 else {
                // This can happen due to races, but should be very rare.
                throw OWSAssertionError("Unexpected groupsVersion.")
            }
            let disappearingMessagesConfiguration = groupThread.disappearingMessagesConfiguration(with: transaction)
            let migrationMetadata = try Self.calculateMigrationMetadata(for: groupThread.groupModel)

            return UnmigratedState(groupThread: groupThread,
                                   disappearingMessagesConfiguration: disappearingMessagesConfiguration,
                                   migrationMetadata: migrationMetadata)
        }
    }
}
