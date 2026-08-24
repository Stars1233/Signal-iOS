//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Network
import SignalServiceKit
import WiFiAware

@available(iOS 26.0, *)
class WADeviceTransferIncomingConnection: DeviceTransfer.IncomingConnection {
    var connectionContinuation: CheckedContinuation<DeviceTransfer.Session, Error>?
    private var connectionTask: Task<Void, Error>?

    func start(mode: DeviceTransfer.Mode) throws -> URL {
        return URL(string: "PeerID")!
    }

    func waitForConnection() async throws -> any DeviceTransfer.Session {
        let listener = try NetworkListener(
            for: .wifiAware(.connecting(to: .deviceTransferService, from: .allPairedDevices)),
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

        return try await withCheckedThrowingContinuation { continuation in
            self.connectionContinuation = continuation
            connectionTask = Task {
                do {
                    while true {
                        try Task.checkCancellation()
                        do {
                            try await listener.run { connection in
                                self.connectionContinuation.take()?.resume(
                                    returning: try WADeviceTransferSession(connection: connection),
                                )
                            }
                        } catch {
                            try await Task.sleep(nanoseconds: 1.clampedNanoseconds)
                        }
                    }
                } catch {
                    self.connectionContinuation.take()?.resume(throwing: error)
                }
            }
        }
    }

    func stop(error: Error?) {
        connectionTask?.cancel()
        connectionContinuation.take()?.resume(throwing: error ?? CancellationError())
    }
}
