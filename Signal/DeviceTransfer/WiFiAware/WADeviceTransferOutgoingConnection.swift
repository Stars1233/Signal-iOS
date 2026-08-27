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
    private let logger = PrefixedLogger(prefix: "[DeviceTransfer][WiFiAware][Outgoing]")
    let selectedPeer: (any DeviceTransfer.PeerID)? = nil

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
                    let pairedDevices = updatedDeviceList.values.map { device in
                        self?.logger.debug("Discovered peer \(device)")
                        return WADeviceTransferPeerId(pairedDevice: device)
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

    func connect(peer: any DeviceTransfer.PeerID) async throws -> any DeviceTransfer.Session {
        logger.info("Start connect")
        guard let peer = peer as? WADeviceTransferPeerId else {
            throw OWSAssertionError("Incompatible peer type encountered")
        }
        let browser = NetworkBrowser(
            for: .wifiAware(.connecting(to: .selected([peer.pairedDevice]), from: .deviceTransferService)),
        ).onStateUpdate { [weak self] _, state in
            switch state {
            case .setup:
                self?.logger.info("Connection: setup")
            case .ready:
                self?.logger.info("Connection: ready")
            case .failed(let error):
                self?.logger.info("Connection: failed: \(error)")
            case .cancelled:
                // Cancelled is returned when `.finished` is returned during `run()` below
                self?.logger.info("Connection: finished")
            case .waiting(let error):
                self?.logger.info("Connection: failed: \(error)")
            @unknown default:
                self?.logger.info("Connection: unknown")
            }
        }

        logger.info("Waiting for endpoint")
        let endpoint = try await browser.run { [weak self] waEndpoints in
            for endpoint in waEndpoints {
                let discoveredPeer = WADeviceTransferPeerId(pairedDevice: endpoint.device)
                if discoveredPeer.peerID == peer.peerID {
                    self?.logger.debug("Found endpoint to connect to: \(discoveredPeer)")
                    return .finish(endpoint)
                } else {
                    self?.logger.debug("Found endpoint other than the selected one")
                    self?.logger.debug("\(discoveredPeer) != \(peer)")
                }
            }
            return .continue
        }

        logger.info("Connecting")
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

        logger.debug("Connected to endpoint")
        return try WADeviceTransferSession(connection: connection)
    }

    func stop(error: Error?) {
    }
}
