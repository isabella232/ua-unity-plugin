/*
 Copyright 2015 Urban Airship and Contributors
 */

#import "UAUnityPlugin.h"
#import "UnityInterface.h"
#import "UAPush.h"
#import "UAirship.h"
#import "NSJSONSerialization+UAAdditions.h"
#import "UAAction+Operators.h"
#import "UAActionArguments.h"
#import "UAActionRunner.h"
#import "UAActionResult.h"
#import "UALocationService.h"
#import "UAConfig.h"
#import "UAAnalytics.h"
#import "UACustomEvent.h"
#import "UAUtils.h"
#import "UADefaultMessageCenter.h"

static UAUnityPlugin *shared_;
static dispatch_once_t onceToken_;

@implementation UAUnityPlugin

+ (void)load {
    NSLog(@"UnityPlugin class loaded");
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:[UAUnityPlugin class] selector:@selector(performTakeOff:) name:UIApplicationDidFinishLaunchingNotification object:nil];
}

+ (void)performTakeOff:(NSNotification *)notification {
    NSLog(@"UnityPlugin taking off");
    [UAirship takeOff];

    // UAPush delegate and UAActionRegistry need to be set at load so that cold start launches get deeplinks
    [UAirship push].pushNotificationDelegate = [UAUnityPlugin shared];
    [UAirship push].registrationDelegate = [UAUnityPlugin shared];

    UAAction *customDLA = [UAAction actionWithBlock: ^(UAActionArguments *args, UAActionCompletionHandler handler)  {
        NSLog(@"Setting dl to: %@", args.value);
        [UAUnityPlugin shared].storedDeepLink = args.value;
        handler([UAActionResult emptyResult]);
    } acceptingArguments:^BOOL(UAActionArguments *arg)  {
        if (arg.situation == UASituationBackgroundPush) {
            return NO;
        }

        return [arg.value isKindOfClass:[NSString class]];
    }];

    // Replace the display inbox and landing page actions with modified versions that pause the game before display
    UAAction *dia = [[UAirship shared].actionRegistry registryEntryWithName:kUADisplayInboxActionDefaultRegistryName].action;
    UAAction *customDIA = [dia preExecution:^(UAActionArguments *args) {
        // This will ultimately trigger the OnApplicationPause event
        UnityWillPause();
    }];

    UAAction *lpa = [[UAirship shared].actionRegistry registryEntryWithName:kUALandingPageActionDefaultRegistryName].action;
    UAAction *customLPA = [lpa preExecution:^(UAActionArguments *args) {
        // This will ultimately trigger the OnApplicationPause event
        UnityWillPause();
    }];


    [[UAirship shared].actionRegistry updateAction:customDLA forEntryWithName:kUADeepLinkActionDefaultRegistryName];
    [[UAirship shared].actionRegistry updateAction:customDIA forEntryWithName:kUADisplayInboxActionDefaultRegistryName];
    [[UAirship shared].actionRegistry updateAction:customLPA forEntryWithName:kUALandingPageActionDefaultRegistryName];
}

+ (UAUnityPlugin *)shared {
    dispatch_once(&onceToken_, ^{
        shared_ = [[UAUnityPlugin alloc] init];
    });

    return shared_;
}

- (id)init {
    self = [super init];
    return self;
}


#pragma mark -
#pragma mark Listeners

void UAUnityPlugin_setListener(const char* listener) {
    [UAUnityPlugin shared].listener = [NSString stringWithUTF8String:listener];
    NSLog(@"UAUnityPlugin_setListener %@",[UAUnityPlugin shared].listener);
}

#pragma mark -
#pragma mark Deep Links

const char* UAUnityPlugin_getDeepLink(bool clear) {
    NSLog(@"UnityPlugin getDeepLink clear %d",clear);

    const char* dl = [UAUnityPlugin convertToJson:[UAUnityPlugin shared].storedDeepLink];
    if (clear) {
        [UAUnityPlugin shared].storedDeepLink = nil;
    }
    return dl;
}

#pragma mark -
#pragma mark UA Push Functions
const char* UAUnityPlugin_getIncomingPush(bool clear) {
    NSLog(@"UnityPlugin getIncomingPush clear %d",clear);

    if (![UAUnityPlugin shared].storedNotification) {
        return nil;
    }

    const char* payload = [UAUnityPlugin convertPushToJson:[UAUnityPlugin shared].storedNotification];

    if (clear) {
        [UAUnityPlugin shared].storedNotification = nil;
    }

    return payload;
}

bool UAUnityPlugin_getUserNotificationsEnabled() {
    NSLog(@"UnityPlugin getUserNotificationsEnabled");
    return [UAirship push].userPushNotificationsEnabled ? true : false;
}

void UAUnityPlugin_setUserNotificationsEnabled(bool enabled) {
    NSLog(@"UnityPlugin setUserNotificationsEnabled: %d", enabled);
    [UAirship push].userPushNotificationsEnabled = enabled ? YES : NO;
}

const char* UAUnityPlugin_getTags() {
    NSLog(@"UnityPlugin getTags");
    return [UAUnityPlugin convertToJson:[UAirship push].tags];
}

void UAUnityPlugin_addTag(const char* tag) {
    NSString *tagString = [NSString stringWithUTF8String:tag];

    NSLog(@"UnityPlugin addTag %@", tagString);
    [[UAirship push] addTag:tagString];
    [[UAirship push] updateRegistration];
}

void UAUnityPlugin_removeTag(const char* tag) {
    NSString *tagString = [NSString stringWithUTF8String:tag];

    NSLog(@"UnityPlugin removeTag %@", tagString);
    [[UAirship push] removeTag:tagString];
    [[UAirship push] updateRegistration];
}

const char* UAUnityPlugin_getAlias() {
    NSLog(@"UnityPlugin getAlias");
    return MakeStringCopy([[UAirship push].alias UTF8String]);
}

void UAUnityPlugin_setAlias(const char* alias) {
    NSString *aliasString = [NSString stringWithUTF8String:alias];

    NSLog(@"UnityPlugin setAlias %@", aliasString);
    [UAirship push].alias = aliasString;
    [[UAirship push] updateRegistration];
}

const char* UAUnityPlugin_getChannelId() {
    NSLog(@"UnityPlugin getChannelId");
    return MakeStringCopy([[UAirship push].channelID UTF8String]);
}

#pragma mark -
#pragma mark UA Location Functions

bool UAUnityPlugin_isLocationEnabled() {
    NSLog(@"UnityPlugin isLocationEnabled");
    return [UALocationService airshipLocationServiceEnabled] ? true : false;
}

void UAUnityPlugin_setLocationEnabled(bool enabled) {
    NSLog(@"UnityPlugin setLocationEnabled: %d", enabled);

    if (enabled) {
        [UALocationService setAirshipLocationServiceEnabled:YES];
        [[UAirship shared].locationService startReportingSignificantLocationChanges];
    } else {
        [UALocationService setAirshipLocationServiceEnabled:NO];
        [[UAirship shared].locationService stopReportingSignificantLocationChanges];
    }
}

bool UAUnityPlugin_isBackgroundLocationAllowed() {
    NSLog(@"UnityPlugin isBackgroundLocationAllowed");
    return [UAirship shared].locationService.backgroundLocationServiceEnabled ? true : false;
}

void UAUnityPlugin_setBackgroundLocationAllowed(bool enabled) {
    NSLog(@"UnityPlugin setBackgroundLocationAllowed: %d", enabled);
    [UAirship shared].locationService.backgroundLocationServiceEnabled = enabled ? YES : NO;
}

void UAUnityPlugin_addCustomEvent(const char *customEvent) {
    NSString *customEventString = [NSString stringWithUTF8String:customEvent];
    NSLog(@"UnityPlugin addCustomEvent");
    id obj = [NSJSONSerialization objectWithString:customEventString];

    UACustomEvent *ce = [UACustomEvent eventWithName:[UAUnityPlugin stringOrNil:obj[@"eventName"]]];

    NSString *valueString = [UAUnityPlugin stringOrNil:obj[@"eventValue"]];
    if (valueString) {
        ce.eventValue = [NSDecimalNumber decimalNumberWithString:valueString];
    }

    ce.interactionID = [UAUnityPlugin stringOrNil:obj[@"interactionId"]];
    ce.interactionType = [UAUnityPlugin stringOrNil:obj[@"interactionType"]];
    ce.transactionID = [UAUnityPlugin stringOrNil:obj[@"transactionID"]];

    for (id property in obj[@"properties"]) {
        NSString *name = [UAUnityPlugin stringOrNil:property[@"name"]];
        id value;
        NSString *type = property[@"type"];
        if ([type isEqualToString:@"s"]) {
            value = property[@"stringValue"];
            [ce setStringProperty:value forKey:name];
        } else if ([type isEqualToString:@"d"]) {
            value = property[@"doubleValue"];
            [ce setNumberProperty:value forKey:name];
        } else if ([type isEqualToString:@"b"]) {
            value = property[@"boolValue"];
            [ce setBoolProperty:value forKey:name];
        } else if ([type isEqualToString:@"sa"]) {
            value = property[@"stringArrayValue"];
            [ce setStringArrayProperty:value forKey:name];
        }
    }

    [[UAirship shared].analytics addEvent:ce];
}

void UAUnityPlugin_setNamedUserID(const char *namedUserID) {
    NSString *namedUserIDString = [NSString stringWithUTF8String:namedUserID];
    NSLog(@"UnityPlugin setNamedUserID %@", namedUserIDString);
    [UAirship push].namedUser.identifier = namedUserIDString;
}

const char* UAUnityPlugin_getNamedUserID() {
    return MakeStringCopy([[UAirship push].namedUser.identifier UTF8String]);
}


#pragma mark -
#pragma mark MessageCenter

void UAUnityPlugin_displayMessageCenter() {
    NSLog(@"UnityPlugin displayMessageCenter");
    UnityWillPause();
    [[UAirship defaultMessageCenter] display];
}

#pragma mark -
#pragma mark Tag Groups

void UAUnityPlugin_editChannelTagGroups(const char *payload) {
    NSLog(@"UnityPlugin editChannelTagGroups");
    id payloadMap = [NSJSONSerialization objectWithString:[NSString stringWithUTF8String:payload]];
    id operations = payloadMap[@"values"];

    for (NSDictionary *operation in operations) {
        NSString *group = operation[@"tagGroup"];
        if ([operation[@"operation"] isEqualToString:@"add"]) {
            [[UAirship push] addTags:operation[@"tags"] group:group];
        } else if ([operation[@"operation"] isEqualToString:@"remove"]) {
            [[UAirship push] removeTags:operation[@"tags"] group:group];
        }
    }

    [[UAirship push] updateRegistration];
}

void UAUnityPlugin_editNamedUserTagGroups(const char *payload) {
    NSLog(@"UnityPlugin editNamedUserTagGroups");
    id payloadMap = [NSJSONSerialization objectWithString:[NSString stringWithUTF8String:payload]];
    id operations = payloadMap[@"values"];

    UANamedUser *namedUser = [UAirship push].namedUser;

    for (NSDictionary *operation in operations) {
        NSString *group = operation[@"tagGroup"];
        if ([operation[@"operation"] isEqualToString:@"add"]) {
            [namedUser addTags:operation[@"tags"] group:group];
        } else if ([operation[@"operation"] isEqualToString:@"remove"]) {
            [namedUser removeTags:operation[@"tags"] group:group];
        }
    }

    [namedUser updateTags];
}


#pragma mark -
#pragma mark Actions!

#pragma mark -
#pragma mark UAPushNotificationDelegate
/**
 * Called when a push notification is received while the app is running in the foreground.
 *
 * @param notification The notification dictionary.
 */
- (void)receivedForegroundNotification:(NSDictionary *)notification {
    NSLog(@"receivedForegroundNotification %@",notification);
    if (self.listener) {
        UnitySendMessage(MakeStringCopy([self.listener UTF8String]),
                     "OnPushReceived",
                     [UAUnityPlugin convertPushToJson:notification]);
    }
}


/**
 * Called when the app is started or resumed because a user opened a notification.
 *
 * @param notification The notification dictionary.
 */
- (void)launchedFromNotification:(NSDictionary *)notification {
    NSLog(@"launchedFromNotification %@",notification);
    self.storedNotification = notification;
}

#pragma mark -
#pragma mark UARegistrationDelegate


/**
 * Called when the device channel registers with Urban Airship. Successful
 * registrations could be disabling push, enabling push, or updating the device
 * registration settings.
 *
 * The device token will only be available once the application successfully
 * registers with APNS.
 *
 * When registration finishes in the background, any async tasks that are triggered
 * from this call should request a background task.
 * @param channelID The channel ID string.
 * @param deviceToken The device token string.
 */
- (void)registrationSucceededForChannelID:(NSString *)channelID deviceToken:(NSString *)deviceToken {
    NSLog(@"registrationSucceededForChannelID: %@", channelID);
    if (self.listener) {
        UnitySendMessage(MakeStringCopy([self.listener UTF8String]),
                         "OnChannelUpdated",
                         MakeStringCopy([channelID UTF8String]));
    }
}

#pragma mark -
#pragma mark Helpers

+ (NSString *)stringOrNil:(NSString *)string {
    return string.length > 0 ? string : nil;
}

+ (const char *) convertPushToJson:(NSDictionary *)push {
    NSString *alert = push[@"aps"][@"alert"];
    NSString *identifier = push[@"_"];
    NSMutableDictionary *extras = [NSMutableDictionary dictionary];
    for (NSString *key in push) {
        if (![key isEqualToString:@"_"] && ! [key isEqualToString:@"aps"]) {
            id value = push[key];
            if ([value isKindOfClass:[NSString class]]) {
                [extras setValue:value forKey:key];
            } else {
                [extras setValue:[NSJSONSerialization stringWithObject:value] forKey:key];
            }
        }
    }

    NSMutableDictionary *serializedPayload = [NSMutableDictionary dictionary];
    [serializedPayload setValue:alert forKey:@"alert"];
    [serializedPayload setValue:identifier forKey:@"identifier"];

    if (extras.count) {
        [serializedPayload setValue:extras forKey:@"extras"];
    }

    return [UAUnityPlugin convertToJson:serializedPayload];
}

+ (const char *) convertToJson:(NSObject*) obj {
    NSString *JSONString = [NSJSONSerialization stringWithObject:obj acceptingFragments:YES];
    return MakeStringCopy([JSONString UTF8String]);
}

// Helper method to create C string copy
char* MakeStringCopy (const char* string) {
    if (string == NULL) {
        return NULL;
    }

    char* res = (char*)malloc(strlen(string) + 1);
    strcpy(res, string);
    return res;
}

@end
