#import "WMFAnnouncementsFetcher.h"
#import "WMFAnnouncement.h"
#import <WMF/WMF-Swift.h>

@interface WMFAnnouncementsFetcher ()

@property (nonatomic, strong) WMFSession *session;

@end

@implementation WMFAnnouncementsFetcher

- (instancetype)init {
    self = [super init];
    if (self) {
        self.session = [WMFSession shared];
    }
    return self;
}

- (void)fetchAnnouncementsForURL:(NSURL *)siteURL force:(BOOL)force failure:(WMFErrorHandler)failure success:(void (^)(NSArray<WMFAnnouncement *> *announcements))success {
    NSParameterAssert(siteURL);
    if (siteURL == nil) {
        NSError *error = [NSError wmf_errorWithType:WMFErrorTypeInvalidRequestParameters
                                           userInfo:nil];
        failure(error);
        return;
    }

    NSURL *url = [WMFConfiguration.current mobileAppsServicesAPIURLForHost:siteURL.host withPath:@"/feed/announcements"];
    
    [self.session getJSONDictionaryFromURL:url ignoreCache:YES completionHandler:^(NSDictionary<NSString *,id> * _Nullable result, NSHTTPURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            failure(error);
            return;
        }
        
        if (response.statusCode == 304) {
            failure([NSError wmf_errorWithType:WMFErrorTypeNoNewData userInfo:nil]);
            return;
        }
        
        NSArray *announcementJSONs = [result objectForKey:@"announce"];
        if (![announcementJSONs isKindOfClass:[NSArray class]]) {
            failure([NSError wmf_errorWithType:WMFErrorTypeUnexpectedResponseType
                                      userInfo:nil]);
            return;
        }
        
        NSError *mantleError = nil;
        NSArray<WMFAnnouncement *> *announcements = [MTLJSONAdapter modelsOfClass:[WMFAnnouncement class] fromJSONArray:announcementJSONs error:&mantleError];
        if (mantleError){
            failure(mantleError);
            return;
        }
        
        WMFAnnouncement *announcement = announcements.firstObject;
        if (![announcement isKindOfClass:[WMFAnnouncement class]]) {
            failure([NSError wmf_errorWithType:WMFErrorTypeUnexpectedResponseType
                                      userInfo:nil]);
            return;
        }

        NSString *geoIPCookie = [self geoIPCookieString];
        NSString *setCookieHeader = nil;
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            setCookieHeader = [(NSHTTPURLResponse *)response allHeaderFields][@"Set-Cookie"];
        }
        NSArray<WMFAnnouncement *> *announcementsFilteredByCountry = [self filterAnnouncements:announcements withCurrentCountryInIPHeader:setCookieHeader geoIPCookieValue:geoIPCookie];
        NSArray<WMFAnnouncement *> *filteredAnnouncements = [self filterAnnouncementsForiOSPlatform:announcementsFilteredByCountry];
        success(filteredAnnouncements);
    }];
}

- (NSArray<WMFAnnouncement *> *)filterAnnouncements:(NSArray<WMFAnnouncement *> *)announcements withCurrentCountryInIPHeader:(NSString *)header geoIPCookieValue:(NSString *)cookieValue {

    NSArray<WMFAnnouncement *> *validAnnouncements = [announcements wmf_select:^BOOL(WMFAnnouncement *obj) {
        if (![obj isKindOfClass:[WMFAnnouncement class]]) {
            return NO;
        }
        NSArray *countries = [obj countries];
        if (countries.count == 0) {
            return YES;
        }
        __block BOOL valid = NO;
        [countries enumerateObjectsUsingBlock:^(NSString *_Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
            if ([header containsString:[NSString stringWithFormat:@"GeoIP=%@", obj]]) {
                valid = YES;
                *stop = YES;
            }
            if ([header length] < 1 && [cookieValue hasPrefix:obj]) {
                valid = YES;
                *stop = YES;
            }
        }];
        return valid;
    }];
    return validAnnouncements;
}

- (NSArray<WMFAnnouncement *> *)filterAnnouncementsForiOSPlatform:(NSArray<WMFAnnouncement *> *)announcements {

    NSArray<WMFAnnouncement *> *validAnnouncements = [announcements wmf_select:^BOOL(WMFAnnouncement *obj) {
        if (![obj isKindOfClass:[WMFAnnouncement class]]) {
            return NO;
        }
        if ([obj.platforms containsObject:@"iOSAppV2"]) {
            return YES;
        } else {
            return NO;
        }
    }];
    return validAnnouncements;
}

- (NSString *)geoIPCookieString {
    NSArray<NSHTTPCookie *> *cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies];
    NSHTTPCookie *cookie = [cookies wmf_match:^BOOL(NSHTTPCookie *obj) {
        if ([[obj name] containsString:@"GeoIP"]) {
            return YES;
        } else {
            return NO;
        }
    }];

    return [cookie value];
}

@end
