//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Network
import SignalServiceKit
import WiFiAware

@available(iOS 26.0, *)
class WADeviceTransferOutgoingConnection: DeviceTransfer.OutgoingConnection {
    func connect(deviceTransferUrl: URL) async throws -> any DeviceTransfer.Session {
        let browser = NetworkBrowser(
            for: .wifiAware(.connecting(to: .allPairedDevices, from: .deviceTransferService)),
        )

        // Connect to the first discovered endpoint.
        let endpoint = try await browser.run { waEndpoints in
            for endpoint in waEndpoints {
                return .finish(endpoint)
            }
            return .continue
        }

        let connection = NetworkConnection(
            to: endpoint,
            using: .parameters {
                Coder(
                    receiving: WiFiAware.NetworkEvent.self,
                    sending: WiFiAware.NetworkEvent.self,
                    using: NetworkJSONCoder(),
                ) {
                    TCP().keepalive(idleTimeInSeconds: 10, count: 30, intervalInSeconds: 5)
                }
            }
            .wifiAware { $0.performanceMode = WiFiAware.Constants.appPerformanceMode }
            .serviceClass(WiFiAware.Constants.appServiceClass),
        )
        return try WADeviceTransferSession(connection: connection)
    }

    func stop(error: Error?) {
    }
}
