//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

// MARK: - RegistrationTransferStatusPresenter

protocol RegistrationTransferStatusPresenter: AnyObject {
    func cancelTransfer()
    func transferFailed(error: Error)
}

class RegistrationDeviceTransferStatusViewController: DeviceTransferStatusViewController {

    private var pairedPeerListenTask: Task<Void, Error>?

    init(
        coordinator: DeviceTransferCoordinator,
        presenter: RegistrationTransferStatusPresenter? = nil,
    ) {
        super.init(coordinator: coordinator)

        self.pairedPeerListenTask = Task {
            for try await _ in coordinator.pairedPeerStream {
                self.presentedViewController?.dismiss(animated: true)
            }
        }

        coordinator.cancelTransferBlock = {
            presenter?.cancelTransfer()
        }

        coordinator.onFailure = { error in
            presenter?.transferFailed(error: error)
        }
    }

    deinit {
        self.pairedPeerListenTask.take()?.cancel()
    }
}
