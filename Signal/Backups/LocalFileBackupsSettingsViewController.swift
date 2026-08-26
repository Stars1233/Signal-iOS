//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI
import UIKit

class LocalFileBackupsSettingsViewController: OWSTableViewController2 {
    private let localFileBackupExportJobRunner: LocalFileBackupExportJobRunner
    private let localFileBackupStore: LocalFileBackupStore
    private let db: DB
    private let accountKeyStore: AccountKeyStore
    private let localFileBackupManager: LocalFileBackupManager
    private let localFileBackupExportJobStore: LocalFileBackupExportJobStore
    private let backupFailureStateManager: BackupFailureStateManager

    // Archive progress
    private var latestArchiveProgressUpdate: OWSSequentialProgress<LocalFileBackupExportJobStage>?
    private var progressUpdatesTask: Task<Void, Never>?
    private weak var archiveProgressLabel: UILabel?

    // Restore progress
    private var latestAttachmentRestoreProgressUpdate: OWSProgress?
    private let localFileBackupAttachmentRestoreProgress: LocalFileBackupAttachmentRestoreProgress
    private var attachmentRestoreObserver: LocalFileBackupAttachmentRestoreProgressObserver?
    private weak var attachmentRestoreProgressLabel: UILabel?

    // Only ever one of archive/restore is visible; they share the hosting controller
    private lazy var progressBarHostingController = UIHostingController(rootView: PulsingProgressBar(value: 0))

    init(
        localFileBackupExportJobRunner: LocalFileBackupExportJobRunner,
        localFileBackupStore: LocalFileBackupStore,
        db: DB,
        accountKeyStore: AccountKeyStore,
        localFileBackupManager: LocalFileBackupManager,
        localFileBackupExportJobStore: LocalFileBackupExportJobStore,
        backupFailureStateManager: BackupFailureStateManager,
        localFileBackupAttachmentRestoreProgress: LocalFileBackupAttachmentRestoreProgress,
    ) {
        self.localFileBackupExportJobRunner = localFileBackupExportJobRunner
        self.localFileBackupStore = localFileBackupStore
        self.db = db
        self.accountKeyStore = accountKeyStore
        self.localFileBackupManager = localFileBackupManager
        self.localFileBackupExportJobStore = localFileBackupExportJobStore
        self.backupFailureStateManager = backupFailureStateManager
        self.localFileBackupAttachmentRestoreProgress = localFileBackupAttachmentRestoreProgress
    }

    deinit {
        progressUpdatesTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SETTINGS_LOCAL_FILE_BACKUPS",
            comment: "Title for the 'on-device backups' settings page.",
        )
        OWSTableViewController2.removeBackButtonText(viewController: self)

        view.backgroundColor = UIColor.Signal.groupedBackground

        updateTableContents()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(lastLocalBackupDetailsDidChange),
            name: .lastLocalBackupDetailsDidChange,
            object: nil,
        )

        addChild(progressBarHostingController)
        progressBarHostingController.view.backgroundColor = .clear
        progressBarHostingController.view.tintColor = .Signal.accent
        progressBarHostingController.didMove(toParent: self)

        observeExportJobUpdates()

        let observer = localFileBackupAttachmentRestoreProgress.addObserver { progress in
            Task { @MainActor [weak self] in
                self?.onRestoreProgressUpdate(progress)
            }
        }
        attachmentRestoreObserver = observer
    }

    private func observeExportJobUpdates() {
        let stream = localFileBackupExportJobRunner.updates()
        progressUpdatesTask = Task { @MainActor [weak self] in
            for await update in stream {
                guard let self else { return }
                let previous = self.latestArchiveProgressUpdate
                switch update {
                case .progress(let progress):
                    self.latestArchiveProgressUpdate = progress
                case .completion(let result):
                    self.latestArchiveProgressUpdate = nil
                    switch result {
                    case .success:
                        break
                    case .failure(let error):
                        showSheetForLocalFileBackupExportJobError(error)
                    }
                case nil:
                    self.latestArchiveProgressUpdate = nil
                }

                // Avoid rebuilding the whole table contents every time.
                let hadRow = previous != nil
                let hasRow = self.latestArchiveProgressUpdate != nil
                if hadRow != hasRow {
                    self.updateTableContents()
                } else if hasRow {
                    self.updateArchiveProgressCellInPlace()
                }
            }
        }
    }

    override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }

    @objc
    private func lastLocalBackupDetailsDidChange() {
        updateTableContents()
    }

    override func topHeader() -> UIView? {
        let label = UILabel()
        label.text = OWSLocalizedString(
            "SETTINGS_LOCAL_FILE_BACKUPS_HEADER_DESCRIPTION",
            comment: "Description shown at the top of the on-device backups settings page.",
        )
        label.font = .dynamicTypeCaption1Clamped
        label.textColor = .Signal.secondaryLabel
        label.numberOfLines = 0

        let container = UIView()
        container.addSubview(label)
        label.autoPinEdge(toSuperviewEdge: .leading, withInset: 32)
        label.autoPinEdge(toSuperviewEdge: .trailing, withInset: 32)
        label.autoPinEdge(toSuperviewEdge: .top, withInset: 12)
        label.autoPinEdge(toSuperviewEdge: .bottom, withInset: 8)
        container.backgroundColor = UIColor.Signal.groupedBackground
        return container
    }

    private func updateTableContents() {
        let contents = OWSTableContents()

        var sections: [OWSTableSection] = []
        if let archiveProgressSection = makeArchiveProgressSection() {
            sections.append(archiveProgressSection)
        } else if let restoreProgressSection = makeRestoreProgressSection() {
            sections.append(restoreProgressSection)
        } else {
            sections.append(makeBackUpNowSection())
        }
        sections.append(makeDetailsSection())
        sections.append(makeTurnOffSection())

        contents.add(sections: sections)

        self.contents = contents
    }

    // MARK: - Restore Progress

    @MainActor
    private func onRestoreProgressUpdate(_ progress: OWSProgress) {
        let previous = self.latestAttachmentRestoreProgressUpdate

        if progress.isFinished || progress.totalUnitCount == 0 {
            latestAttachmentRestoreProgressUpdate = nil
        } else {
            latestAttachmentRestoreProgressUpdate = progress
        }

        // Avoid rebuilding the whole table contents every time.
        let hadRow = previous != nil
        let hasRow = self.latestAttachmentRestoreProgressUpdate != nil
        if hadRow != hasRow {
            self.updateTableContents()
        } else if hasRow {
            self.updateRestoreProgressCellInPlace()
        }
    }

    private func makeRestoreProgressSection() -> OWSTableSection? {
        guard let latestAttachmentRestoreProgressUpdate else {
            return nil
        }
        let section = OWSTableSection()
        section.add(OWSTableItem(
            customCellBlock: { [weak self] in
                let cell = OWSTableItem.newCell()
                cell.preservesSuperviewLayoutMargins = true
                cell.contentView.preservesSuperviewLayoutMargins = true
                cell.selectionStyle = .none

                guard let self else { return UITableViewCell() }

                let (percent, labelText) = self.restoreProgressDisplay(progress: latestAttachmentRestoreProgressUpdate)
                let hostingController = self.progressBarHostingController
                hostingController.rootView = PulsingProgressBar(value: percent)

                let label = UILabel()
                label.font = .monospacedDigitSystemFont(
                    ofSize: UIFont.dynamicTypeSubheadlineClamped.pointSize,
                    weight: .regular,
                )
                label.textColor = .Signal.secondaryLabel
                label.numberOfLines = 0
                label.adjustsFontForContentSizeCategory = true
                label.text = labelText

                let stack = UIStackView(arrangedSubviews: [hostingController.view, label])
                stack.axis = .vertical
                stack.spacing = 12
                stack.alignment = .fill
                stack.isLayoutMarginsRelativeArrangement = true
                stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 0)

                cell.contentView.addSubview(stack)
                stack.autoPinEdgesToSuperviewMargins()

                self.attachmentRestoreProgressLabel = label

                return cell
            },
            actionBlock: nil,
        ))

        return section
    }

    private func updateRestoreProgressCellInPlace() {
        guard
            let update = latestAttachmentRestoreProgressUpdate,
            let attachmentRestoreProgressLabel
        else {
            return
        }
        let (percent, labelText) = restoreProgressDisplay(progress: update)
        progressBarHostingController.rootView = PulsingProgressBar(value: percent)

        let oldText = attachmentRestoreProgressLabel.text
        attachmentRestoreProgressLabel.text = labelText

        if oldText != labelText {
            tableView.recomputeRowHeights()
        }
    }

    private func restoreProgressDisplay(progress: OWSProgress) -> (percent: Float, label: String) {
        let totalBytes = progress.totalUnitCount
        let completedBytes = progress.completedUnitCount
        let label = String.nonPluralLocalizedStringWithFormat(
            OWSLocalizedString(
                "SETTINGS_LOCAL_FILE_BACKUPS_PROGRESS_RESTORING_ATTACHMENTS",
                comment: "Label for a progress bar while attachments are being restored for an on-device backup. Embeds {{%1$@ completed bytes restored, %2$@ total bytes to restore  }}.",
            ),
            completedBytes.formatted(.owsByteCount()),
            totalBytes.formatted(.owsByteCount()),
        )
        return (progress.percentComplete, label)
    }

    // MARK: - Archive progress

    private func makeArchiveProgressSection() -> OWSTableSection? {
        guard let update = latestArchiveProgressUpdate else { return nil }

        let section = OWSTableSection()
        section.add(OWSTableItem(
            customCellBlock: { [weak self] in
                let cell = OWSTableItem.newCell()
                cell.preservesSuperviewLayoutMargins = true
                cell.contentView.preservesSuperviewLayoutMargins = true
                cell.selectionStyle = .none

                guard let self else { return UITableViewCell() }

                let (percent, labelText) = self.archiveProgressDisplay(for: update)
                let hostingController = self.progressBarHostingController
                hostingController.rootView = PulsingProgressBar(value: percent)

                let label = UILabel()
                label.font = .monospacedDigitSystemFont(
                    ofSize: UIFont.dynamicTypeSubheadlineClamped.pointSize,
                    weight: .regular,
                )
                label.textColor = .Signal.secondaryLabel
                label.numberOfLines = 0
                label.adjustsFontForContentSizeCategory = true
                label.text = labelText

                let stack = UIStackView(arrangedSubviews: [hostingController.view, label])
                stack.axis = .vertical
                stack.spacing = 12
                stack.alignment = .fill
                stack.isLayoutMarginsRelativeArrangement = true
                stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 0)

                cell.contentView.addSubview(stack)
                stack.autoPinEdgesToSuperviewMargins()

                self.archiveProgressLabel = label

                return cell
            },
            actionBlock: nil,
        ))
        section.add(OWSTableItem(
            customCellBlock: {
                let cell = OWSTableItem.newCell()
                cell.preservesSuperviewLayoutMargins = true
                cell.contentView.preservesSuperviewLayoutMargins = true

                let label = UILabel()
                label.text = OWSLocalizedString(
                    "BACKUP_SETTINGS_MANUAL_BACKUP_CANCEL_BUTTON",
                    comment: "Title for a button shown under a progress bar tracking a manual backup, which lets the user cancel the backup.",
                )
                label.font = OWSTableItem.primaryLabelFont
                label.textColor = Theme.primaryTextColor
                label.adjustsFontForContentSizeCategory = true

                cell.contentView.addSubview(label)
                label.autoPinEdgesToSuperviewMargins()

                return cell
            },
            actionBlock: { [weak self] in
                guard let self else { return }
                _ = self.localFileBackupExportJobRunner.cancelIfRunning()
            },
        ))

        return section
    }

    private func updateArchiveProgressCellInPlace() {
        guard
            let update = latestArchiveProgressUpdate,
            let archiveProgressLabel
        else {
            return
        }
        let (percent, labelText) = archiveProgressDisplay(for: update)
        progressBarHostingController.rootView = PulsingProgressBar(value: percent)

        let oldText = archiveProgressLabel.text
        archiveProgressLabel.text = labelText

        if oldText != labelText {
            tableView.recomputeRowHeights()
        }
    }

    private func archiveProgressDisplay(
        for update: OWSSequentialProgress<LocalFileBackupExportJobStage>,
    ) -> (percent: Float, label: String) {
        switch update.currentStep {
        case .attachmentMetadataPrep:
            let percent = update.progress(for: .attachmentMetadataPrep)?.percentComplete ?? 0
            let label = String.nonPluralLocalizedStringWithFormat(
                OWSLocalizedString(
                    "SETTINGS_LOCAL_FILE_BACKUPS_PROGRESS_PREPARING_ATTACHMENTS",
                    comment: "Label for a progress bar while the attachments are being prepared for an on-device backup. Embeds 1:{{ percentage complete }}.",
                ),
                percent.formatted(.owsPercent()),
            )
            return (percent, label)
        case .backupFileExport:
            let percent = update.progress(for: .backupFileExport)?.percentComplete ?? 0
            let label = String.nonPluralLocalizedStringWithFormat(
                OWSLocalizedString(
                    "SETTINGS_LOCAL_FILE_BACKUPS_PROGRESS_PREPARING_BACKUP",
                    comment: "Label for a progress bar while the on-device backup is being prepared. Embeds 1:{{ percentage complete }}.",
                ),
                percent.formatted(.owsPercent()),
            )
            return (percent, label)
        case .attachmentCopy:
            let percent = update.progress(for: .attachmentCopy)?.percentComplete ?? 0
            let label = String.nonPluralLocalizedStringWithFormat(
                OWSLocalizedString(
                    "SETTINGS_LOCAL_FILE_BACKUPS_PROGRESS_COPYING_ATTACHMENTS",
                    comment: "Label for a progress bar while attachments are being copied for an on-device backup. Embeds 1:{{ percentage complete }}.",
                ),
                percent.formatted(.owsPercent()),
            )
            return (percent, label)
        }
    }

    private class YellowBadgeView: UIImageView {
        init() {
            super.init(image: UIImage(systemName: "circle.fill"))
            tintColor = UIColor.Signal.yellow
            preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 10)
            translatesAutoresizingMaskIntoConstraints = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }

    // MARK: - Sections

    private func makeBackUpNowSection() -> OWSTableSection {
        let section = OWSTableSection()
        let hasFailedLocalBackup = db.read { tx in
            backupFailureStateManager.hasFailedLocalBackup(tx: tx)
        }

        if hasFailedLocalBackup {
            section.add(OWSTableItem(
                customCellBlock: {
                    let cell = OWSTableItem.newCell()
                    cell.preservesSuperviewLayoutMargins = true
                    cell.contentView.preservesSuperviewLayoutMargins = true

                    let iconView = YellowBadgeView()
                    iconView.setContentHuggingHorizontalHigh()
                    iconView.setCompressionResistanceHorizontalHigh()

                    let label = UILabel()
                    label.text = OWSLocalizedString(
                        "BACKUP_SETTINGS_BACKUP_FAILED_MESSAGE",
                        comment: "Message describing to the user that the last backup failed.",
                    )
                    label.font = .dynamicTypeSubheadlineClamped
                    label.textColor = Theme.primaryTextColor
                    label.adjustsFontForContentSizeCategory = true
                    label.numberOfLines = 0
                    label.textAlignment = .natural

                    let stack = UIStackView(arrangedSubviews: [iconView, label])
                    stack.axis = .horizontal
                    stack.alignment = .firstBaseline
                    stack.spacing = 12

                    cell.contentView.addSubview(stack)
                    stack.autoPinEdgesToSuperviewMargins()

                    return cell
                },
            ))
        }

        section.add(OWSTableItem(
            customCellBlock: {
                let cell = OWSTableItem.newCell()
                cell.preservesSuperviewLayoutMargins = true
                cell.contentView.preservesSuperviewLayoutMargins = true

                let iconView = UIImageView(image: .backup)
                iconView.contentMode = .scaleAspectFit
                iconView.tintColor = Theme.primaryIconColor
                iconView.autoSetDimensions(to: .square(24))
                iconView.setContentHuggingHorizontalHigh()
                iconView.setCompressionResistanceHorizontalHigh()

                let label = UILabel()
                label.text = OWSLocalizedString(
                    "SETTINGS_LOCAL_FILE_BACKUPS_BACK_UP_NOW",
                    comment: "Label for the button that starts a manual on-device backup.",
                )
                label.font = OWSTableItem.primaryLabelFont
                label.textColor = Theme.primaryTextColor
                label.adjustsFontForContentSizeCategory = true

                let stack = UIStackView(arrangedSubviews: [iconView, label])
                stack.axis = .horizontal
                stack.alignment = .center
                stack.spacing = 12

                cell.contentView.addSubview(stack)
                stack.autoPinEdgesToSuperviewMargins()

                return cell
            },
            actionBlock: { [weak self] in
                guard let self else { return }
                let task = localFileBackupExportJobRunner.startIfNecessary(mode: .manual)
                Task { @MainActor [weak self] in
                    do {
                        try await task.value
                    } catch BackupExportLockError.remoteBackupInProgress {
                        let actionSheet = ActionSheetController(
                            message: OWSLocalizedString(
                                "SETTINGS_LOCAL_FILE_BACKUPS_REMOTE_BACKUP_IN_PROGRESS_MESSAGE",
                                comment: "Message for an action sheet when a user cannot perform a local backup because a remote backup is in progress",
                            ),
                        )
                        actionSheet.addAction(.ok)
                        self?.presentActionSheet(actionSheet)
                    } catch {
                        Logger.error("Unexpected error encountered: \(error)")
                    }
                }
            },
        ))

        return section
    }

    private func makeDetailsSection() -> OWSTableSection {
        let section = OWSTableSection()

        let lastBackupDetails = db.read { tx in
            localFileBackupStore.lastBackupDetails(tx: tx)
        }

        if let lastBackupDate = lastBackupDetails?.date {
            let lastBackupMessage = BackupSettingsView.Strings.lastBackupString(date: lastBackupDate)
            section.add(OWSTableItem(
                customCellBlock: {
                    let cell = OWSTableItem.buildCell(
                        itemName: OWSLocalizedString(
                            "SETTINGS_LOCAL_FILE_BACKUPS_LAST_BACKUP_DATE",
                            comment: "Label for the row showing when the last on-device backup occurred.",
                        ),
                        accessoryText: lastBackupMessage,
                    )
                    cell.selectionStyle = .none
                    return cell
                },
                actionBlock: nil,
            ))
        }

        if let lastBackupSizeBytes = lastBackupDetails?.backupTotalSizeBytes {
            section.add(OWSTableItem(
                customCellBlock: {
                    let cell = OWSTableItem.buildCell(
                        itemName: OWSLocalizedString(
                            "SETTINGS_LOCAL_FILE_BACKUPS_BACKUP_SIZE",
                            comment: "Label for the row showing the size of the on-device backup.",
                        ),
                        accessoryText: lastBackupSizeBytes.formatted(.owsByteCount()),
                    )
                    cell.selectionStyle = .none
                    return cell
                },
                actionBlock: nil,
            ))
        }

        if let localFileBackupLocation = try? localFileBackupManager.getSavedSecurityScopedBookmark(type: .archive)?.lastPathComponent {
            section.add(.disclosureItem(
                withText: OWSLocalizedString(
                    "SETTINGS_LOCAL_FILE_BACKUPS_BACKUP_FOLDER",
                    comment: "Label for the row that lets the user choose the folder for on-device backups.",
                ),
                accessoryText: localFileBackupLocation,
                actionBlock: { [weak self] in
                    guard let self else { return }

                    present(
                        LocalFileBackupSelectFolderHeroSheetViewController(
                            onContinue: { [weak self] in
                                guard let self else { return }
                                LocalFileBackupArchiveFolderPicker.present(
                                    fromViewController: self,
                                    manager: self.localFileBackupManager,
                                    onSuccess: { [weak self] in
                                        self?.presentToast(
                                            text: OWSLocalizedString(
                                                "SETTINGS_LOCAL_FILE_BACKUP_FOLDER_UPDATED",
                                                comment: "Text for a toast confirming the user changed their local file backup location.",
                                            ),
                                            image: .checkCircle,
                                        )
                                        self?.lastLocalBackupDetailsDidChange()
                                    },
                                )
                            },
                        ),
                        animated: true,
                    )
                },
            ))
        }

        section.add(.disclosureItem(
            withText: OWSLocalizedString(
                "SETTINGS_LOCAL_FILE_BACKUPS_VIEW_RECOVERY_KEY",
                comment: "Label for the row that shows the on-device backup recovery key.",
            ),
            actionBlock: { [weak self] in
                self?.showViewRecoveryKey()
            },
        ))

        return section
    }

    fileprivate func showViewRecoveryKey() {
        Task { await _showViewRecoveryKey() }
    }

    private func _showViewRecoveryKey() async {
        guard
            let navigationController,
            let authSuccess = await LocalDeviceAuthentication().performBiometricAuth(),
            let aep = db.read(block: { accountKeyStore.getAccountEntropyPool(tx: $0) })
        else {
            return
        }

        let saveAndConfirmKeyCoordinator = BackupSaveAndConfirmKeyCoordinator(
            navigationController: navigationController,
        )
        saveAndConfirmKeyCoordinator.present(
            aepMode: .current(aep, authSuccess),
            options: [
                .showSaveKeyToPasswordManager(onConfirmed: { [weak self, weak navigationController] in
                    guard let self, let navigationController else { return }

                    navigationController.popToViewController(self, animated: true) {
                        self.presentToast(
                            text: OWSLocalizedString(
                                "BACKUP_SETTINGS_CONFIRM_KEY_SUCCESS_TOAST",
                                comment: "Toast shown when the user's Recovery Key has been confirmed successfully.",
                            ),
                            image: .checkCircle,
                        )
                    }
                }),
            ],
        )
    }

    private func makeTurnOffSection() -> OWSTableSection {
        let section = OWSTableSection()

        section.add(.item(
            name: OWSLocalizedString(
                "SETTINGS_LOCAL_FILE_BACKUPS_TURN_OFF",
                comment: "Label for the button that turns off on-device backups.",
            ),
            textColor: .Signal.red,
            actionBlock: { [weak self] in
                guard let self else { return }
                ModalActivityIndicatorViewController.present(
                    fromViewController: self,
                    asyncBlock: { [weak self] modal in
                        guard let self else {
                            modal.dismiss()
                            return
                        }

                        // Stop any running backups before we delete the folder.
                        if let cancelTask = localFileBackupExportJobRunner.cancelIfRunning() {
                            _ = try? await cancelTask.value
                        }

                        let cleanUpState: () -> Void = { [weak self] in
                            guard let self else { return }
                            db.write { [localFileBackupStore, localFileBackupExportJobStore] tx in
                                localFileBackupStore.setLocalBackupsEnabled(value: false, tx: tx)

                                // Clear any reminders or details associated with the local backup.
                                // Don't clear the restore bookmark data in case we're still restoring a previous local file backup.
                                localFileBackupStore.clearLastBackupDetails(tx: tx)
                                localFileBackupStore.clearChooseNewLocalBackupLocation(tx: tx)
                                localFileBackupStore.clearShouldPromptUserToEnableLocalBackups(tx: tx)
                                localFileBackupStore.clearArchiveBookmarkData(tx: tx)
                                localFileBackupStore.clearLastEnumeratedAttachmentRowId(tx: tx)
                                localFileBackupStore.clearLastBackupEnabledDetails(tx: tx)
                                localFileBackupStore.clearErrorStateStore(tx: tx)
                                localFileBackupExportJobStore.wipe(tx: tx)
                            }
                        }

                        do {
                            try await localFileBackupManager.deleteLocalFileBackup()
                            cleanUpState()
                            modal.dismiss { [weak self] in
                                self?.navigationController?.popViewController(animated: true)
                            }
                        } catch {
                            if DebugFlags.internalLogging {
                                Logger.error("Error deleting local file backup: \(error)")
                            } else {
                                Logger.error("Error deleting local file backup \(error.shortDescription)")
                            }
                            modal.dismiss { [weak self] in
                                guard let self else { return }

                                let localFileBackupLocation = try? localFileBackupManager.getSavedSecurityScopedBookmark(type: .archive)?.lastPathComponent
                                let fileLocation: String
                                // If we know the parent folder, use it in the error message, otherwise, just use general root folder name.
                                if let localFileBackupLocation {
                                    fileLocation = localFileBackupLocation + " > " + LocalFileBackupManager.FileStructure.rootDirectory.rawValue
                                } else {
                                    fileLocation = LocalFileBackupManager.FileStructure.rootDirectory.rawValue
                                }

                                let message = OWSLocalizedString(
                                    "SETTINGS_LOCAL_FILE_BACKUPS_TURNING_OFF_ERROR_MESSAGE_FORMAT",
                                    comment: "Message shown on an action sheet when a user's backup fails to delete. Embeds {{ local file backup location }}",
                                )

                                let actionSheet = ActionSheetController(
                                    title: OWSLocalizedString("SETTINGS_LOCAL_FILE_BACKUPS_TURNING_OFF_ERROR_TITLE", comment: "Title shown on an action sheet when a user's backup fails to delete"),
                                    message: String.nonPluralLocalizedStringWithFormat(message, fileLocation),
                                )

                                actionSheet.addAction(ActionSheetAction(
                                    title: CommonStrings.okButton,
                                    handler: { [weak self] sheet in
                                        cleanUpState()
                                        self?.navigationController?.popViewController(animated: true)
                                    },
                                ))
                                actionSheet.addAction(.cancel)
                                presentActionSheet(actionSheet)
                            }
                        }
                    },
                )
            },
        ))

        let font = UIFont.dynamicTypeCaption1Clamped
        section.footerAttributedTitle = NSAttributedString.composed(of: [
            OWSLocalizedString(
                "SETTINGS_LOCAL_FILE_BACKUPS_RESTORE_FOOTER",
                comment: "Footer text on the on-device backups settings page explaining how to restore a backup.",
            ),
            " ",
            CommonStrings.learnMore.styled(
                with: .link(URL.Support.backups),
                .font(font),
            ),
        ])
        .styled(
            with: .font(font),
            .color(Self.defaultFooterTextColor),
        )

        return section
    }

    // MARK: -

    private func showSheetForLocalFileBackupExportJobError(_ error: Error) {
        let actionSheet: ActionSheetController
        switch error {
        case is CancellationError:
            return
        case is NotRegisteredError:
            actionSheet = ActionSheetController(
                message: OWSLocalizedString(
                    "BACKUP_SETTINGS_BACKUP_EXPORT_ERROR_SHEET_NOT_REGISTERED",
                    comment: "Message for an action sheet explaining that you must be registered to make a Backup.",
                ),
            )
            actionSheet.addAction(.okay)
        case LocalFileBackupError.unableToAccessLocalFile:
            actionSheet = ActionSheetController(
                message: OWSLocalizedString(
                    "LOCAL_FILE_BACKUP_CHOOSE_NEW_FOLDER_SHEET_MESSAGE",
                    comment: "Message for a sheet asking the user to choose a new local file backup folder.",
                ),
            )
            actionSheet.addAction(ActionSheetAction(
                title: OWSLocalizedString(
                    "LOCAL_FILE_BACKUP_CHOOSE_NEW_FOLDER_SHEET_BUTTON",
                    comment: "Button for a sheet asking the user to choose a new local file backup folder",
                ),
                handler: { _ in
                    LocalFileBackupArchiveFolderPicker.present(
                        fromViewController: self,
                        manager: self.localFileBackupManager,
                        onSuccess: { [weak self] in
                            self?.presentToast(
                                text: OWSLocalizedString(
                                    "SETTINGS_LOCAL_FILE_BACKUP_FOLDER_UPDATED",
                                    comment: "Text for a toast confirming the user changed their local file backup location.",
                                ),
                                image: .checkCircle,
                            )
                            self?.lastLocalBackupDetailsDidChange()
                        },
                    )
                },
            ))
            actionSheet.addAction(.cancel)
        default:
            actionSheet = ActionSheetController(
                message: OWSLocalizedString(
                    "BACKUP_SETTINGS_BACKUP_EXPORT_ERROR_SHEET_GENERIC_ERROR",
                    comment: "Message for an action sheet explaining that performing a backup failed with a generic error.",
                ),
            )
            actionSheet.addAction(.contactSupport(
                emailFilter: .backupExportFailed,
                fromViewController: self,
            ))
            actionSheet.addAction(.okay)
        }

        presentActionSheet(actionSheet)
    }

}
