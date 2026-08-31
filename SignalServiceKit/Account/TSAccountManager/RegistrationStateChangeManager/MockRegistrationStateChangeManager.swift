//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

import Foundation
public import LibSignalClient

open class MockRegistrationStateChangeManager: RegistrationStateChangeManager {

    public init() {}

    public var registrationStateMock: (() -> TSRegistrationState) = {
        return .registered
    }

    open func registrationState(tx: DBReadTransaction) -> TSRegistrationState {
        return registrationStateMock()
    }

    public lazy var didRegisterOrProvisionMock: (
        _ aci: Aci,
        _ phoneNumber: (e164: E164, pni: Pni),
        _ authToken: String,
        _ deviceId: DeviceId,
    ) -> Void = { [weak self] _, _, _, _ in
        self?.registrationStateMock = { .registered }
    }

    open func didRegisterOrProvision(
        aci: Aci,
        phoneNumber: (e164: E164, pni: Pni),
        authToken: String,
        deviceId: DeviceId,
        tx: DBWriteTransaction,
    ) {
        didRegisterOrProvisionMock(aci, phoneNumber, authToken, deviceId)
    }

    public lazy var didFinishProvisioningSecondayMock: () -> Void = { [weak self] in
        self?.registrationStateMock = { .provisioned }
    }

    open func didFinishProvisioningSecondary(tx: DBWriteTransaction) {
        didFinishProvisioningSecondayMock()
    }

    public var didUpdateLocalPhoneNumberMock: (
        _ aci: Aci,
        _ phoneNumber: (E164, Pni),
    ) -> Void = { _, _ in }

    public func didUpdateLocalPhoneNumber(aci: Aci, phoneNumber: (e164: E164, pni: Pni), tx: DBWriteTransaction) {
        didUpdateLocalPhoneNumberMock(aci, phoneNumber)
    }

    public lazy var resetForReregistrationMock: (
        _ localPhoneNumber: E164,
        _ localAci: Aci,
        _ wasPrimaryDevice: Bool,
    ) -> Void = { [weak self] phoneNumber, aci, _ in
        self?.registrationStateMock = { .reregistering(phoneNumber: phoneNumber.stringValue, aci: aci) }
    }

    open func resetForReregistration(
        localPhoneNumber: E164,
        localAci: Aci,
        wasPrimaryDevice: Bool,
        tx: DBWriteTransaction,
    ) {
        return resetForReregistrationMock(localPhoneNumber, localAci, wasPrimaryDevice)
    }

    public lazy var setIsTransferInProgressMock: () -> Void = { [weak self] in
        self?.registrationStateMock = { .transferringIncoming }
    }

    open func setIsTransferInProgress(tx: DBWriteTransaction) {
        setIsTransferInProgressMock()
    }

    public lazy var setIsTransferCompleteMock: () -> Void = { [weak self] in
        self?.registrationStateMock = { .registered }
    }

    open func setIsTransferComplete(sendStateUpdateNotification: Bool, tx: DBWriteTransaction) {
        setIsTransferCompleteMock()
    }

    public lazy var setWasTransferredMock: () -> Void = { [weak self] in
        self?.registrationStateMock = { .transferred }
    }

    open func setWasTransferred(tx: DBWriteTransaction) {
        setWasTransferredMock()
    }

    public var cleanUpTransferStateOnAppLaunchIfNeededMock: () -> Void = {}

    open func cleanUpTransferStateOnAppLaunchIfNeeded() {
        cleanUpTransferStateOnAppLaunchIfNeededMock()
    }

    public lazy var setIsDeregisteredOrDelinkedMock: (
        _ isDeregisteredOrDelinked: Bool,
    ) -> Void = { [weak self] isDeregisteredOrDelinked in
        let wasPrimary = self?.registrationStateMock().isPrimaryDevice ?? true
        if isDeregisteredOrDelinked {
            self?.registrationStateMock = wasPrimary ? { .deregistered } : { .delinked }
        } else {
            self?.registrationStateMock = wasPrimary ? { .registered } : { .provisioned }
        }
    }

    open func setIsDeregisteredOrDelinked(_ isDeregisteredOrDelinked: Bool, tx: DBWriteTransaction) {
        setIsDeregisteredOrDelinkedMock(isDeregisteredOrDelinked)
    }

    public var unregisterFromServiceMock: () async throws -> Void = { fatalError() }

    open func unregisterFromService() async throws {
        try await unregisterFromServiceMock()
    }

    public func unlinkLocalDevice(localDeviceId: LocalDeviceId, auth: ChatServiceAuth) async throws { fatalError() }
}

#endif
