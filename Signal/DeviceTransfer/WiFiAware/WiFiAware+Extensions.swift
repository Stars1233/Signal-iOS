//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Network
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
