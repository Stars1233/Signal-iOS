//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import WiFiAware

@available(iOS 26.0, *)
struct WADeviceTransferPeerId: DeviceTransfer.PeerID {
    var peerID: String { pairedDevice.displayName }
    let pairedDevice: WAPairedDevice
}
