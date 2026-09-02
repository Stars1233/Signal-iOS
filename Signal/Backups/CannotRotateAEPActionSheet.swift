//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class CannotRotateAEPActionSheet: ActionSheetController {
    init?(reason: CanRotateAEPResult, fromViewController: UIViewController) {
        let message: String
        let primaryButtonTitle: String
        let primaryButtonAction: () -> Void

        switch reason {
        case .localFileBackupsEnabled:
            message = OWSLocalizedString(
                "AEP_MANAGER_LOCAL_BACKUPS_DISABLE_REQUIRED",
                comment: "Message shown in an action sheet when attempting to rotate AEP, but local backups is enabled.",
            )
            primaryButtonTitle = OWSLocalizedString(
                "AEP_MANAGER_ON_DEVICE_BACKUP_SETTINGS_BUTTON",
                comment: "Button in an action sheet that takes the user to On-Device Backup settings.",
            )
            primaryButtonAction = { [weak fromViewController] in
                fromViewController?.dismiss(animated: true) {
                    SignalApp.shared.showAppSettings(mode: .backups(page: .local))
                }
            }
        case .success:
            owsFailDebug("Should not present CannotRotateAEPActionSheet when result is .success")
            return nil
        }

        super.init()
        setTitle(nil, message: message)
        addAction(ActionSheetAction(
            title: primaryButtonTitle,
            handler: { _ in primaryButtonAction() },
        ))
        addAction(.ok)
    }
}
