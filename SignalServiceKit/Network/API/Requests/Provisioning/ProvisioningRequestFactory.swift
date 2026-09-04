//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public enum ProvisioningRequestFactory {

    public static func verifySecondaryDeviceRequest(
        verificationCode: String,
        aci: Aci,
        authPassword: String,
        attributes: AccountAttributes,
        apnRegistrationId: RegistrationRequestFactory.ApnRegistrationId?,
        prekeyBundles: RegistrationPreKeyUploadBundles,
    ) -> TSRequest {
        owsAssertDebug(!verificationCode.isEmpty)
        owsAssertDebug((apnRegistrationId != nil) != attributes.isManualMessageFetchEnabled)

        let urlPathComponents = URLPathComponents(
            ["v1", "devices", "link"],
        )

        var urlComponents = URLComponents()
        urlComponents.percentEncodedPath = urlPathComponents.percentEncoded
        let url = urlComponents.url!

        let request = LinkDeviceRequest(
            verificationCode: verificationCode,
            accountAttributes: attributes,
            aciSignedPreKey: OWSRequestFactory.SignedPreKey(prekeyBundles.aci.signedPreKey),
            aciPqLastResortPreKey: OWSRequestFactory.KyberPreKey(prekeyBundles.aci.lastResortPreKey),
            pniSignedPreKey: OWSRequestFactory.SignedPreKey(prekeyBundles.pni.signedPreKey),
            pniPqLastResortPreKey: OWSRequestFactory.KyberPreKey(prekeyBundles.pni.lastResortPreKey),
            apnToken: apnRegistrationId,
        )

        var result = TSRequest(url: url, method: "PUT", body: .encodable(request))
        // The "verify code" request handles auth differently.
        result.auth = .registration((username: aci.serviceIdString, password: authPassword))
        return result
    }

    private struct LinkDeviceRequest: Encodable {
        var verificationCode: String
        var accountAttributes: AccountAttributes
        var aciSignedPreKey: OWSRequestFactory.SignedPreKey
        var aciPqLastResortPreKey: OWSRequestFactory.KyberPreKey
        var pniSignedPreKey: OWSRequestFactory.SignedPreKey
        var pniPqLastResortPreKey: OWSRequestFactory.KyberPreKey
        var apnToken: RegistrationRequestFactory.ApnRegistrationId?
    }
}
