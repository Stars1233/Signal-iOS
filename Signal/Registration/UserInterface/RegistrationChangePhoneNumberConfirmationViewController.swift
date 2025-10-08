//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UIKit
import SignalUI

// MARK: - RegistrationChangePhoneNumberConfirmationPresenter

protocol RegistrationChangePhoneNumberConfirmationPresenter: AnyObject {
    func confirmChangeNumber(newE164: E164)

    func returnToPhoneNumberEntry()
}

// MARK: - RegistrationChangePhoneNumberConfirmationViewController

class RegistrationChangePhoneNumberConfirmationViewController: OWSViewController, OWSNavigationChildController {

    public var preferredNavigationBarStyle: OWSNavigationBarStyle {
        return .solid
    }

    public var navbarBackgroundColorOverride: UIColor? {
        return view.backgroundColor
    }

    private var state: RegistrationPhoneNumberViewState.ChangeNumberConfirmation
    private weak var presenter: RegistrationChangePhoneNumberConfirmationPresenter?

    private lazy var descriptionLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }()

    private lazy var phoneNumberLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeTitle2.semibold()
        label.textColor = .Signal.label
        label.textAlignment = .center
        return label
    }()

    private func reloadTextLabels() {
        let descriptionFormat = OWSLocalizedString(
            "SETTINGS_CHANGE_PHONE_NUMBER_CONFIRM_DESCRIPTION_FORMAT",
            comment: "Format for the description text in the 'change phone number splash' view. Embeds: {{ %1$@ the old phone number, %2$@ the new phone number }}."
        )
        let oldPhoneNumberFormatted = PhoneNumber.bestEffortLocalizedPhoneNumber(e164: state.oldE164.stringValue)
        let newPhoneNumberFormatted = PhoneNumber.bestEffortLocalizedPhoneNumber(e164: state.newE164.stringValue)
        let descriptionText = String(
            format: descriptionFormat,
            oldPhoneNumberFormatted,
            newPhoneNumberFormatted
        )
        let descriptionAttributedText = NSMutableAttributedString(
            string: descriptionText,
            attributes: [
                .foregroundColor: UIColor.Signal.secondaryLabel,
                .font: UIFont.dynamicTypeBody
            ]
        )
        descriptionAttributedText.setAttributes(
            [ .foregroundColor: UIColor.Signal.label ],
            forSubstring: oldPhoneNumberFormatted
        )
        descriptionAttributedText.setAttributes(
            [ .foregroundColor: UIColor.Signal.label ],
            forSubstring: newPhoneNumberFormatted
        )
        descriptionLabel.attributedText = descriptionAttributedText
        phoneNumberLabel.text = newPhoneNumberFormatted
   }

    private lazy var warningLabel: UILabel = {
        let label = UILabel()
        label.textColor = .ows_accentRed
        label.numberOfLines = 0
        label.font = .dynamicTypeSubheadlineClamped
        label.accessibilityIdentifier = "registration.phonenumber.validationWarningLabel"
        return label
    }()

    public init(
        state: RegistrationPhoneNumberViewState.ChangeNumberConfirmation,
        presenter: RegistrationChangePhoneNumberConfirmationPresenter
    ) {
        self.state = state
        self.presenter = presenter
        super.init()
    }

    public func updateState(_ state: RegistrationPhoneNumberViewState.ChangeNumberConfirmation) {
        self.state = state
        updateContents()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.groupedBackground
        title = OWSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_VIEW_TITLE",
                                  comment: "Title for the 'change phone number' views in settings.")

        // Text
        reloadTextLabels()
        let phoneNumberContainerView = UIView()
        phoneNumberContainerView.backgroundColor = .Signal.secondaryGroupedBackground
        phoneNumberContainerView.layer.cornerRadius = 10
        phoneNumberContainerView.directionalLayoutMargins = NSDirectionalEdgeInsets(margin: 24)
        phoneNumberContainerView.addSubview(phoneNumberLabel)
        phoneNumberLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            phoneNumberLabel.topAnchor.constraint(equalTo: phoneNumberContainerView.layoutMarginsGuide.topAnchor),
            phoneNumberLabel.leadingAnchor.constraint(equalTo: phoneNumberContainerView.layoutMarginsGuide.leadingAnchor),
            phoneNumberLabel.bottomAnchor.constraint(equalTo: phoneNumberContainerView.layoutMarginsGuide.bottomAnchor),
            phoneNumberLabel.trailingAnchor.constraint(equalTo: phoneNumberContainerView.layoutMarginsGuide.trailingAnchor),
        ])

        let stackView = UIStackView(arrangedSubviews: [ descriptionLabel, phoneNumberContainerView, warningLabel ])
        stackView.spacing = 20
        stackView.setCustomSpacing(12, after: phoneNumberContainerView)
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.preservesSuperviewLayoutMargins = true

        // Buttons
        let continueButton = UIButton(
            configuration: .largePrimary(title: OWSLocalizedString(
                "SETTINGS_CHANGE_PHONE_NUMBER_CONFIRM_BUTTON",
                comment: "Label for the 'confirm change phone number' button in the 'change phone number' views."
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapContinue()
            }
        )
        continueButton.isEnabled = state.rateLimitedError?.canSubmit(e164: self.state.newE164, dateProvider: Date.provider) ?? true
        let editButton = UIButton(
            configuration: .largeSecondary(title: OWSLocalizedString(
                "SETTINGS_CHANGE_PHONE_NUMBER_BACK_TO_EDIT_BUTTON",
                comment: "Label for the 'edit phone number' button in the 'change phone number' views."
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapEdit()
            }
        )
        let buttonContainer = UIView.container()
        buttonContainer.addSubview(continueButton)
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.addSubview(editButton)
        editButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            continueButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            continueButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor, constant: 22),
            continueButton.centerXAnchor.constraint(equalTo: buttonContainer.centerXAnchor),

            editButton.topAnchor.constraint(equalTo: continueButton.bottomAnchor, constant: 12),
            editButton.leadingAnchor.constraint(equalTo: continueButton.leadingAnchor),
            editButton.trailingAnchor.constraint(equalTo: continueButton.trailingAnchor),
            editButton.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor, constant: -16),
        ])

        // Constraints.
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(buttonContainer)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            buttonContainer.topAnchor.constraint(greaterThanOrEqualTo: stackView.bottomAnchor, constant: 24),
            buttonContainer.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            buttonContainer.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            buttonContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        updateContents()
    }

    private var rateLimitErrorTimer: Timer?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateContents()

        // We only need this timer if the user has been rate limited, but it's simpler to always
        // start it.
        rateLimitErrorTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateContents()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        rateLimitErrorTimer?.invalidate()
        rateLimitErrorTimer = nil
    }

    public override func themeDidChange() {
        super.themeDidChange()
        updateContents()
    }

    private func updateContents() {
        reloadTextLabels()

        let now = Date()
        if
            let rateLimitedError = state.rateLimitedError,
                !rateLimitedError.canSubmit(e164: self.state.newE164, dateProvider: { now })
        {
            warningLabel.text = rateLimitedError.warningLabelText(dateProvider: { now })
            warningLabel.isHiddenInStackView = false
        } else {
            warningLabel.isHiddenInStackView = true
        }
    }

    private func didTapEdit() {
        AssertIsOnMainThread()

        presenter?.returnToPhoneNumberEntry()
    }

    private func didTapContinue() {
        AssertIsOnMainThread()

        guard state.rateLimitedError?.canSubmit(e164: self.state.newE164, dateProvider: Date.provider) != false else {
            return
        }

        presenter?.confirmChangeNumber(newE164: state.newE164)
    }
}

// MARK: -

#if DEBUG

private class PreviewRegistrationChangePhoneNumberConfirmationPresenter: RegistrationChangePhoneNumberConfirmationPresenter {
    func confirmChangeNumber(newE164: E164) {
        print("confirmChangeNumber")
    }

    func returnToPhoneNumberEntry() {
        print("returnToPhoneNumberEntry")
    }
}

@available(iOS 17, *)
#Preview {
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        await MockSSKEnvironment.activate()
        semaphore.signal()
    }
    semaphore.wait()
    let presenter = PreviewRegistrationChangePhoneNumberConfirmationPresenter()
    return UINavigationController(
        rootViewController: RegistrationChangePhoneNumberConfirmationViewController(
            state: RegistrationPhoneNumberViewState.ChangeNumberConfirmation(
                oldE164: E164("+12395550180")!,
                newE164: E164("+12395550185")!,
                rateLimitedError: nil
            ),
            presenter: presenter
        )
    )
}

#endif
