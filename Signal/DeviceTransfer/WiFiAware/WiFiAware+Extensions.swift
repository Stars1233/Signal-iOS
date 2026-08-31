//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Network
import SignalServiceKit
public import WiFiAware

@available(iOS 26.0, *)
enum WiFiAware {
    enum Constants {
        static let deviceTransferServiceName = "_sgnl-transfer._tcp"
        static let appPerformanceMode: WAPerformanceMode = .bulk
        static let appAccessCategory: WAAccessCategory = .bestEffort
        static let appServiceClass: NWParameters.ServiceClass = appAccessCategory.serviceClass
    }

    enum NetworkEvent: Codable, Sendable {
        case done
        case appBackgrounded
        case resourceBegin(file: String, size: UInt64)
        case resourceData(file: String, data: Data)
        case resourceEnd(file: String)
    }

    static func createPeerDiscoveryObserver(logger: PrefixedLogger) -> (
        AsyncThrowingStream<[any DeviceTransfer.Peer], any Error>,
        Task<Void, Never>,
    ) {
        let (stream, sink) = AsyncThrowingStream<[any DeviceTransfer.Peer], any Error>.makeStream()
        let task = Task {
            do {
                for try await updatedDeviceList in WAPairedDevice.allDevices {
                    let newDevices = updatedDeviceList.values
                    let pairedDevices = newDevices.reduce(into: [String: WADeviceTransferPeer]()) { devices, device in
                        let peer = WADeviceTransferPeer(pairedDevice: device)
                        if let existingPeer = devices[peer.displayName] {
                            logger.debug("Discovered existing peer \(device)")
                            if peer.pairedDevice.id > existingPeer.pairedDevice.id {
                                devices[peer.displayName] = peer
                            }
                        } else {
                            logger.debug("Discovered new peer \(device)")
                            devices[peer.displayName] = peer
                        }
                    }
                    if !pairedDevices.isEmpty {
                        logger.info("Discovered \(pairedDevices.count) peers")
                        let sortedList = pairedDevices.values.sorted { $0.pairedDevice.id > $1.pairedDevice.id }
                        sink.yield(sortedList)
                    }
                }
            } catch is CancellationError {
                sink.finish()
            } catch {
                sink.finish(throwing: error)
            }
        }
        return (stream, task)
    }
}

@available(iOS 26.0, *)
typealias WiFiAwareConnection = NetworkConnection<Coder<WiFiAware.NetworkEvent, WiFiAware.NetworkEvent, NetworkJSONCoder>>

@available(iOS 26.0, *)
extension WAPublishableService {
    public static var deviceTransferService: WAPublishableService {
        allServices[WiFiAware.Constants.deviceTransferServiceName]!
    }
}

@available(iOS 26.0, *)
extension WASubscribableService {
    public static var deviceTransferService: WASubscribableService {
        allServices[WiFiAware.Constants.deviceTransferServiceName]!
    }
}

@available(iOS 26.0, *)
extension WAAccessCategory {
    var serviceClass: NWParameters.ServiceClass {
        switch self {
        case .bestEffort: .bestEffort
        case .background: .background
        case .interactiveVideo: .interactiveVideo
        case .interactiveVoice: .interactiveVoice
        default: .bestEffort
        }
    }
}

@available(iOS 26.0, *)
extension WAPairedDevice {
    var displayName: String {
        let displayName = self.name ?? self.pairingInfo?.pairingName ?? ""
        return "\(displayName) (\(self.pairingInfo?.vendorName ?? ""))"
    }
}
