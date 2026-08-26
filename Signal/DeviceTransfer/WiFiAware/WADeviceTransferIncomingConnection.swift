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
    private var connectionContinuation: CheckedContinuation<DeviceTransfer.Session, Error>?
    private var connectionTask: Task<Void, Error>?

    let discoveredPeerStream: AsyncThrowingStream<[DeviceTransfer.PeerID], any Error>
    private let discoveredPeerSink: AtomicValue<AsyncThrowingStream<[DeviceTransfer.PeerID], Error>.Continuation>
    private var discoveredPeerTask: Task<Void, Never>?

    init() {
        let sink: AsyncThrowingStream<[DeviceTransfer.PeerID], Error>.Continuation
        (self.discoveredPeerStream, sink) = AsyncThrowingStream.makeStream()
        self.discoveredPeerSink = AtomicValue(sink, lock: .init())

        self.discoveredPeerTask = Task { [weak self] in
            do {
                for try await updatedDeviceList in WAPairedDevice.allDevices {
                    let pairedDevices = updatedDeviceList.values.map {
                        WADeviceTransferPeerId(pairedDevice: $0)
                    }
                    self?.discoveredPeerSink.get().yield(pairedDevices)
                }
            } catch {
                self?.discoveredPeerSink.get().finish(throwing: error)
            }
        }
    }

    deinit {
        discoveredPeerSink.get().finish()
        discoveredPeerTask.take()?.cancel()
    }

    func start(mode: DeviceTransfer.Mode) throws -> URL {
        var components = URLComponents()
        components.scheme = UrlOpener.Constants.sgnlPrefix
        components.host = DeviceTransfer.UrlConstants.transferHost
        let queryItems = [
            DeviceTransfer.UrlConstants.versionKey: String(DeviceTransfer.UrlConstants.currentTransferVersion),
            DeviceTransfer.UrlConstants.transferModeKey: mode.rawValue,
        ]
        components.queryItems = queryItems.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }

    func waitForConnection() async throws -> any DeviceTransfer.Session {
        return try await withCheckedThrowingContinuation { continuation in
            self.connectionContinuation = continuation
            connectionTask = Task {
                do {
                    while true {
                        try Task.checkCancellation()
                        do {
                            try await NetworkListener(
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
                            ).run { connection in
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
