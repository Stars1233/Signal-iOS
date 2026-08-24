//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

enum RegistrationUtils {

    static func showReRegistrationPrompt(fromViewController viewController: UIViewController) {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        owsPrecondition(tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice == true)

        let actionSheet = ActionSheetController(
            title: NSLocalizedString(
                "DEREGISTRATION_REREGISTER_PROMPT_TITLE",
                comment: "Title for prompt that lets users re-register using the same phone number.",
            ),
        )
        actionSheet.addAction(ActionSheetAction(
            title: NSLocalizedString(
                "DEREGISTRATION_REREGISTER_BUTTON",
                comment: "Button that lets users re-register using the same phone number.",
            ),
            style: .default,
            handler: { _ in
                showReRegistration()
            },
        ))
        actionSheet.addAction(OWSActionSheets.cancelAction)
        viewController.presentActionSheet(actionSheet)
    }

    private static func fetchIdentifiers() -> (Aci, E164)? {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard
            let localIdentifiers = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction,
            let phoneNumber = E164(localIdentifiers.phoneNumber)
        else {
            return nil
        }
        return (localIdentifiers.aci, phoneNumber)
    }

    static func showReLinking() {
        Logger.info("showReLinking")

        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let preferences = SSKEnvironment.shared.preferencesRef
        let registrationStateChangeManager = DependenciesBridge.shared.registrationStateChangeManager
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        owsPrecondition(tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice == false)

        guard let (localAci, localPhoneNumber) = fetchIdentifiers() else {
            owsFailDebug("couldn't fetch identifiers for re-linking")
            return
        }

        databaseStorage.write { tx in
            registrationStateChangeManager.resetForReregistration(
                localPhoneNumber: localPhoneNumber,
                localAci: localAci,
                wasPrimaryDevice: false,
                tx: tx,
            )
        }
        preferences.unsetRecordedAPNSTokens()
        ProvisioningController.presentRelinkingFlow()
    }

    static func showReRegistration() {
        let logger = PrefixedLogger(prefix: "[ReReg]")
        logger.info("showReRegistration")

        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let preferences = SSKEnvironment.shared.preferencesRef
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        owsPrecondition(tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice == true)

        guard let (localAci, localPhoneNumber) = fetchIdentifiers() else {
            owsFailDebug("couldn't fetch identifiers for re-registration")
            return
        }
        let dependencies = RegistrationCoordinatorDependencies.from(NSObject())
        let desiredMode = RegistrationMode.reRegistering(RegistrationMode.ReregistrationParams(
            e164: localPhoneNumber,
            aci: localAci,
        ))
        let loader = RegistrationCoordinatorLoaderImpl(dependencies: dependencies)
        let coordinator = databaseStorage.write {
            return loader.coordinator(
                forDesiredMode: desiredMode,
                transaction: $0,
                logger: logger,
            )
        }
        preferences.unsetRecordedAPNSTokens()
        let navController = RegistrationNavigationController.withCoordinator(coordinator)
        let window: UIWindow = CurrentAppContext().mainWindow!
        window.rootViewController = navController
    }
}
