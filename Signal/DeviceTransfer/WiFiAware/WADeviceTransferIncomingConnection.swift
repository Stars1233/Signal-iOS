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
    private let logger = PrefixedLogger(prefix: "[DeviceTransfer][WiFiAware][Incoming]")
    private var connectionContinuation: CheckedContinuation<DeviceTransfer.Session, Error>?
    private var connectionTask: Task<Void, Error>?

    let discoveredPeerStream: AsyncThrowingStream<[any DeviceTransfer.Peer], any Error>
    private let discoveredPeerSink: AtomicValue<AsyncThrowingStream<[any DeviceTransfer.Peer], Error>.Continuation>
    private var discoveredPeerTask: Task<Void, Never>?

    init() {
        let sink: AsyncThrowingStream<[any DeviceTransfer.Peer], Error>.Continuation
        (self.discoveredPeerStream, sink) = AsyncThrowingStream.makeStream()
        self.discoveredPeerSink = AtomicValue(sink, lock: .init())

        self.discoveredPeerTask = Task { [weak self] in
            do {
                for try await updatedDeviceList in WAPairedDevice.allDevices {
                    let pairedDevices: [any DeviceTransfer.Peer] = updatedDeviceList.values.compactMap { device in
                        self?.logger.debug("Discovered peer \(device)")
                        return WADeviceTransferPeer(pairedDevice: device)
                    }
                    if !pairedDevices.isEmpty {
                        self?.logger.info("Discovered \(pairedDevices.count) peers")
                        self?.discoveredPeerSink.get().yield(pairedDevices)
                    }
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
        logger.info("Wait for connection")
        return try await withCheckedThrowingContinuation { continuation in
            self.connectionContinuation = continuation
            connectionTask = Task { [weak self] in
                guard let self else { return }
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
                            ).onStateUpdate { [weak self] _, state in
                                switch state {
                                case .setup:
                                    self?.logger.info("Connection: setup")
                                case .ready:
                                    self?.logger.info("Connection: ready")
                                case .failed(let error):
                                    self?.logger.info("Connection: failed: \(error)")
                                case .cancelled:
                                    self?.logger.info("Connection: cancelled")
                                case .waiting(let error):
                                    self?.logger.info("Connection: failed: \(error)")
                                @unknown default:
                                    self?.logger.info("Connection: unknown")
                                }
                            }.onServiceRegistrationUpdate { [weak self] _, change in
                                switch change {
                                case .add:
                                    self?.logger.info("Connection: add service")
                                case .remove:
                                    self?.logger.info("Connection: remove service")
                                @unknown default:
                                    self?.logger.info("Connection: unknown")
                                }
                            }.run { [weak self] connection in
                                self?.logger.info("Connection from endpoint")
                                self?.connectionContinuation.take()?.resume(
                                    returning: try WADeviceTransferSession(connection: connection),
                                )
                            }
                        } catch {
                            logger.info("Listener timeout try again")
                            try await Task.sleep(nanoseconds: 1.clampedNanoseconds)
                        }
                    }
                } catch {
                    logger.info("Error waiting for connection")
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
