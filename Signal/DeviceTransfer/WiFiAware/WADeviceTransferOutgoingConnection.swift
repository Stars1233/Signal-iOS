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
    let selectedPeer: (any DeviceTransfer.PeerID)? = nil

    func connect(peer: any DeviceTransfer.PeerID) async throws -> any DeviceTransfer.Session {
        guard let peer = peer as? WADeviceTransferPeerId else {
            throw OWSAssertionError("Incompatible peer type encountered")
        }
        let browser = NetworkBrowser(
            for: .wifiAware(.connecting(to: .allPairedDevices, from: .deviceTransferService)),
        )

        let endpoint = try await browser.run { waEndpoints in
            for endpoint in waEndpoints {
                let discoveredPeer = WADeviceTransferPeerId(pairedDevice: endpoint.device)
                if discoveredPeer.peerID == peer.peerID {
                    return .finish(endpoint)
                }
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
