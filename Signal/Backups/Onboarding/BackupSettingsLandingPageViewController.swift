//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

class BackupSettingsLandingPageViewController: OWSTableViewController2 {
    private let backupSettingsStore: BackupSettingsStore
    private let localFileBackupsStore: LocalFileBackupStore
    private let db: DB

    override convenience init() {
        self.init(
            backupSettingsStore: BackupSettingsStore(),
            localFileBackupsStore: LocalFileBackupStore(),
            db: DependenciesBridge.shared.db,
        )
    }

    init(
        backupSettingsStore: BackupSettingsStore,
        localFileBackupsStore: LocalFileBackupStore,
        db: DB,
    ) {
        self.backupSettingsStore = backupSettingsStore
        self.localFileBackupsStore = localFileBackupsStore
        self.db = db
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = OWSLocalizedString(
            "SETTINGS_BACKUPS",
            comment: "Label for the 'backups' section of app settings.",
        )
        updateContents()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateContents()
    }

    private func updateContents() {
        let contents = OWSTableContents()

        let signalBackupsSection = OWSTableSection()
        signalBackupsSection.customHeaderView = buildSubtitleHeaderView()
        signalBackupsSection.add(buildSignalBackupsCardItem())
        contents.add(signalBackupsSection)

        let onDeviceSection = OWSTableSection()
        onDeviceSection.customHeaderView = buildOtherWaysHeaderView()
        onDeviceSection.footerTitle = OWSLocalizedString(
            "BACKUP_SETTINGS_LANDING_ON_DEVICE_BACKUPS_FOOTER",
            comment: "Footer text below the On-Device Backups row on the Backups settings landing page.",
        )
        onDeviceSection.add(buildOnDeviceBackupsItem())
        contents.add(onDeviceSection)

        self.contents = contents
    }

    // MARK: - Section headers

    private func buildSubtitleHeaderView() -> UIView {
        let label = UILabel()
        label.text = OWSLocalizedString(
            "BACKUP_SETTINGS_LANDING_PAGE_SUBTITLE",
            comment: "Subtitle on the Backups settings landing page.",
        )
        label.font = .dynamicTypeCaption1Clamped
        label.textColor = .Signal.secondaryLabel
        label.numberOfLines = 0

        let container = UIView()
        container.addSubview(label)
        label.autoPinEdge(toSuperviewEdge: .leading, withInset: Self.cellHInnerMargin)
        label.autoPinEdge(toSuperviewEdge: .trailing, withInset: Self.cellHInnerMargin)
        label.autoPinEdge(toSuperviewEdge: .top, withInset: 16)
        label.autoPinEdge(toSuperviewEdge: .bottom, withInset: 24)
        return container
    }

    private func buildOtherWaysHeaderView() -> UIView {
        let label = UILabel()
        label.text = OWSLocalizedString(
            "BACKUP_SETTINGS_LANDING_OTHER_WAYS_HEADER",
            comment: "Section header on the Backups settings landing page.",
        )
        label.font = .dynamicTypeHeadlineClamped
        label.textColor = .Signal.label
        label.numberOfLines = 0

        let container = UIView()
        container.addSubview(label)
        label.autoPinEdge(toSuperviewEdge: .leading, withInset: Self.cellHInnerMargin)
        label.autoPinEdge(toSuperviewEdge: .trailing, withInset: Self.cellHInnerMargin)
        label.autoPinEdge(toSuperviewEdge: .top, withInset: (defaultSpacingBetweenSections ?? 0) + 12)
        label.autoPinEdge(toSuperviewEdge: .bottom, withInset: 10)
        return container
    }

    // MARK: - Table items

    private func buildSignalBackupsCardItem() -> OWSTableItem {
        let shouldSkipBackupsOnboarding = db.read { tx in
            if backupSettingsStore.shouldOverrideShowBackupsOnboarding(tx: tx) {
                return false
            }

            return backupSettingsStore.haveBackupsEverBeenEnabled(tx: tx)
        }

        return OWSTableItem(
            customCellBlock: { [weak self] in
                guard let self else { return OWSTableItem.newCell() }
                return self.buildSignalBackupsCardCell(
                    shouldSkipBackupsOnboarding: shouldSkipBackupsOnboarding,
                )
            },
            actionBlock: { [weak self] in
                self?.showRemoteBackups(shouldSkipOnboarding: shouldSkipBackupsOnboarding)
            },
        )
    }

    private func buildSignalBackupsCardCell(
        shouldSkipBackupsOnboarding: Bool,
    ) -> UITableViewCell {
        let cell = OWSTableItem.newCell()

        let titleText = OWSLocalizedString(
            "BACKUP_SETTINGS_LANDING_SIGNAL_BACKUPS_TITLE",
            comment: "Title for the Signal Secure Backups cell on the Backups settings landing page.",
        )

        let bodyText = OWSLocalizedString(
            "BACKUP_SETTINGS_LANDING_SIGNAL_BACKUPS_BODY",
            comment: "Description of Signal Secure Backups on the Backups settings landing page.",
        )

        let actionText: String = if shouldSkipBackupsOnboarding {
            OWSLocalizedString(
                "BACKUP_SETTINGS_LANDING_VIEW_SETTINGS_BUTTON",
                comment: "Button to view settings for remote backups on the Backups settings landing page.",
            )
        } else {
            OWSLocalizedString(
                "BACKUP_SETTINGS_LANDING_SET_UP_BUTTON",
                comment: "Button to begin setting up Signal Secure Backups on the Backups settings landing page.",
            )
        }

        let titleLabel = UILabel()
        titleLabel.text = titleText
        titleLabel.font = .dynamicTypeHeadlineClamped
        titleLabel.textColor = .Signal.label
        titleLabel.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.text = bodyText
        bodyLabel.font = .dynamicTypeSubheadlineClamped
        bodyLabel.textColor = .Signal.secondaryLabel
        bodyLabel.numberOfLines = 0

        var buttonConfig = UIButton.Configuration.gray()
        buttonConfig.title = actionText
        buttonConfig.cornerStyle = .capsule
        buttonConfig.baseBackgroundColor = .Signal.tertiaryFill
        buttonConfig.baseForegroundColor = .Signal.label
        buttonConfig.titleTextAttributesTransformer = .defaultFont(.dynamicTypeSubheadlineClamped.medium())
        buttonConfig.contentInsets = .init(top: 6, leading: 16, bottom: 6, trailing: 16)

        let remoteBackupsButton = UIButton(configuration: buttonConfig)
        remoteBackupsButton.isUserInteractionEnabled = false // Button is decorative. Tapping anywhere on row performs the action.
        remoteBackupsButton.isAccessibilityElement = false
        remoteBackupsButton.setContentHuggingHorizontalHigh()

        let textStack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel, remoteBackupsButton])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 8
        textStack.setCustomSpacing(15, after: bodyLabel)

        let logoImageView = UIImageView(image: UIImage(named: "backups-logo"))
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.autoSetDimensions(to: CGSize(square: 56))
        logoImageView.setContentHuggingHorizontalHigh()
        logoImageView.setCompressionResistanceHorizontalHigh()
        logoImageView.isAccessibilityElement = false

        let contentStack = UIStackView(arrangedSubviews: [textStack, logoImageView])
        contentStack.axis = .horizontal
        contentStack.alignment = .top
        contentStack.spacing = 12

        cell.contentView.addSubview(contentStack)
        contentStack.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(hMargin: 20, vMargin: 20))

        cell.isAccessibilityElement = true
        cell.accessibilityTraits = .button
        cell.accessibilityLabel = "\(titleText), \(bodyText), \(actionText)"

        return cell
    }

    private func buildOnDeviceBackupsItem() -> OWSTableItem {
        let (shouldSkipLocalBackupsOnboarding, localBackupsEnabled) = db.read { tx in
            let localBackupsEnabled = localFileBackupsStore.localBackupsEnabled(tx: tx)
            let skipOnboarding: Bool = {
                if localFileBackupsStore.shouldOverrideShowLocalBackupsOnboarding(tx: tx) {
                    return false
                }
                return localBackupsEnabled
            }()
            return (skipOnboarding, localBackupsEnabled)
        }

        return OWSTableItem(
            customCellBlock: {
                OWSTableItem.buildImageCell(
                    image: UIImage(named: "device-phone")?.withRenderingMode(.alwaysTemplate),
                    itemName: OWSLocalizedString(
                        "BACKUP_SETTINGS_LANDING_ON_DEVICE_BACKUPS",
                        comment: "Label for the On-Device Backups option on the Backups settings landing page.",
                    ),
                    accessoryText: localBackupsEnabled ? CommonStrings.switchOn : nil,
                    accessoryType: .disclosureIndicator,
                )
            },
            actionBlock: { [weak self] in
                guard let navigationController = self?.navigationController else { return }
                navigationController.pushViewController(
                    BackupOnboardingCoordinator(
                        backupType: .local,
                    ).prepareForPresentation(
                        inNavController: navigationController,
                        shouldSkipOnboarding: shouldSkipLocalBackupsOnboarding,
                    ),
                    animated: true,
                )
            },
        )
    }

    // MARK: - Actions

    private func showRemoteBackups(shouldSkipOnboarding: Bool) {
        guard let navigationController else { return }

        navigationController.pushViewController(
            BackupOnboardingCoordinator(
                backupType: .remote,
            ).prepareForPresentation(
                inNavController: navigationController,
                shouldSkipOnboarding: shouldSkipOnboarding,
            ),
            animated: true,
        )
    }
}
