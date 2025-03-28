//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSSyncConfigurationMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncConfigurationMessage ()

@property (nonatomic, readonly) BOOL areReadReceiptsEnabled;
@property (nonatomic, readonly) BOOL showUnidentifiedDeliveryIndicators;
@property (nonatomic, readonly) BOOL showTypingIndicators;
@property (nonatomic, readonly) BOOL sendLinkPreviews;

@end

@implementation OWSSyncConfigurationMessage

- (instancetype)initWithLocalThread:(TSContactThread *)localThread
                   readReceiptsEnabled:(BOOL)areReadReceiptsEnabled
    showUnidentifiedDeliveryIndicators:(BOOL)showUnidentifiedDeliveryIndicators
                  showTypingIndicators:(BOOL)showTypingIndicators
                      sendLinkPreviews:(BOOL)sendLinkPreviews
                           transaction:(DBReadTransaction *)transaction
{
    self = [super initWithLocalThread:localThread transaction:transaction];
    if (!self) {
        return nil;
    }

    _areReadReceiptsEnabled = areReadReceiptsEnabled;
    _showUnidentifiedDeliveryIndicators = showUnidentifiedDeliveryIndicators;
    _showTypingIndicators = showTypingIndicators;
    _sendLinkPreviews = sendLinkPreviews;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(DBReadTransaction *)transaction
{
    SSKProtoSyncMessageConfigurationBuilder *configurationBuilder = [SSKProtoSyncMessageConfiguration builder];
    configurationBuilder.readReceipts = self.areReadReceiptsEnabled;
    configurationBuilder.unidentifiedDeliveryIndicators = self.showUnidentifiedDeliveryIndicators;
    configurationBuilder.typingIndicators = self.showTypingIndicators;
    configurationBuilder.linkPreviews = self.sendLinkPreviews;
    configurationBuilder.provisioningVersion = OWSDeviceProvisionerConstant.provisioningVersion;

    SSKProtoSyncMessageBuilder *builder = [SSKProtoSyncMessage builder];
    builder.configuration = [configurationBuilder buildInfallibly];
    return builder;
}

- (BOOL)isUrgent
{
    return NO;
}

@end

NS_ASSUME_NONNULL_END
