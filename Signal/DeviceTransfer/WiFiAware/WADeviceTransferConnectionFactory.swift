//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

@available(iOS 26.0, *)
struct WADeviceTransferConnectionFactory: DeviceTransfer.ConnectionFactory {
    func buildOutgoingConnection(tsAccountManager: TSAccountManager, deviceTransferURL: URL) -> any DeviceTransfer.OutgoingConnection {
        return WADeviceTransferOutgoingConnection()
    }

    func buildIncomingConnection(tsAccountManager: TSAccountManager) -> any DeviceTransfer.IncomingConnection {
        return WADeviceTransferIncomingConnection()
    }
}
