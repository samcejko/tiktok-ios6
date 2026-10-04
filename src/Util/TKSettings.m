#import "TKSettings.h"
#import "TKKeychain.h"
#import "TKCommon.h"

#define DEF [NSUserDefaults standardUserDefaults]
static NSString * const TKServerKeyName = @"tikie.serverKey";
static const NSUInteger TKMaxSaved = 500;
static const NSUInteger TKMaxSeen = 4000;

@implementation TKSettings

+ (void)registerDefaults
{
    [DEF registerDefaults:@{
        @"serverBaseURL": @"",
        @"streamThroughServer": @NO,
        @"startMuted": @NO,
        @"autoAdvance": @YES,
        @"darkTheme": @YES,
        @"verifyTLS": @YES,
        @"creators": @[],
        @"savedVideos": @[],
        @"seenVideos": @[],
        @"recentSearches": @[],
    }];
}

+ (void)save { [DEF synchronize]; }

+ (void)notify
{
    TKMain(^{ [[NSNotificationCenter defaultCenter] postNotificationName:TKSettingsDidChangeNotification object:nil]; });
}

+ (void)notifyLibrary
{
    TKMain(^{ [[NSNotificationCenter defaultCenter] postNotificationName:TKLibraryDidChangeNotification object:nil]; });
}

#pragma mark - Server

+ (NSString *)serverBaseURL
{
    NSString *s = [DEF stringForKey:@"serverBaseURL"] ?: @"";
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([s hasSuffix:@"/"]) s = [s substringToIndex:s.length - 1];
    return s;
}

+ (void)setServerBaseURL:(NSString *)value
{
    NSString *s = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    if (s.length && ![s hasPrefix:@"http://"] && ![s hasPrefix:@"https://"]) s = [@"https://" stringByAppendingString:s];
    [DEF setObject:s forKey:@"serverBaseURL"];
    [self notify];
}

+ (NSString *)serverKey { return [TKKeychain stringForKey:TKServerKeyName] ?: @""; }
+ (void)setServerKey:(NSString *)value { [TKKeychain setString:value forKey:TKServerKeyName]; }

+ (BOOL)serverConfigured { return [self serverBaseURL].length > 0; }

+ (BOOL)streamThroughServer { return [DEF boolForKey:@"streamThroughServer"]; }
+ (void)setStreamThroughServer:(BOOL)value { [DEF setBool:value forKey:@"streamThroughServer"]; [self notify]; }

#pragma mark - Playback / appearance / network

+ (BOOL)startMuted { return [DEF boolForKey:@"startMuted"]; }
+ (void)setStartMuted:(BOOL)value { [DEF setBool:value forKey:@"startMuted"]; [self notify]; }
+ (BOOL)autoAdvance { return [DEF boolForKey:@"autoAdvance"]; }
+ (void)setAutoAdvance:(BOOL)value { [DEF setBool:value forKey:@"autoAdvance"]; [self notify]; }
+ (BOOL)darkTheme { return [DEF boolForKey:@"darkTheme"]; }
+ (void)setDarkTheme:(BOOL)value { [DEF setBool:value forKey:@"darkTheme"]; }
+ (BOOL)verifyTLS { return [DEF boolForKey:@"verifyTLS"]; }
+ (void)setVerifyTLS:(BOOL)value { [DEF setBool:value forKey:@"verifyTLS"]; }

#pragma mark - Creators

+ (NSString *)normHandle:(NSString *)handle
{
    NSString *h = [[handle stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if ([h hasPrefix:@"@"]) h = [h substringFromIndex:1];
    // allow a pasted profile URL
    NSRange at = [h rangeOfString:@"tiktok.com/@"];
    if (at.location != NSNotFound) {
        h = [h substringFromIndex:at.location + at.length];
        h = [h componentsSeparatedByString:@"/"].firstObject ?: h;
        h = [h componentsSeparatedByString:@"?"].firstObject ?: h;
    }
    NSMutableString *clean = [NSMutableString string];
    NSCharacterSet *ok = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789_."];
    for (NSUInteger i = 0; i < h.length; i++) {
        unichar c = [h characterAtIndex:i];
        if ([ok characterIsMember:c]) [clean appendFormat:@"%C", c];
    }
    return clean;
}

+ (NSArray *)creators { return [DEF arrayForKey:@"creators"] ?: @[]; }

+ (BOOL)hasCreator:(NSString *)handle
{
    NSString *h = [self normHandle:handle];
    for (NSString *c in [self creators]) if ([c isEqualToString:h]) return YES;
    return NO;
}

+ (void)addCreator:(NSString *)handle
{
    NSString *h = [self normHandle:handle];
    if (!h.length) return;
    NSMutableArray *list = [[self creators] mutableCopy];
    [list removeObject:h];
    [list insertObject:h atIndex:0];
    [DEF setObject:list forKey:@"creators"];
    [self save];
    [self notifyLibrary];
}

+ (void)removeCreator:(NSString *)handle
{
    NSString *h = [self normHandle:handle];
    NSMutableArray *list = [[self creators] mutableCopy];
    [list removeObject:h];
    [DEF setObject:list forKey:@"creators"];
    [self save];
    [self notifyLibrary];
}

#pragma mark - Saved

+ (NSArray *)savedVideos { return [DEF arrayForKey:@"savedVideos"] ?: @[]; }

+ (BOOL)isSaved:(NSString *)videoId
{
    if (!videoId.length) return NO;
    for (NSDictionary *d in [self savedVideos]) if ([TKStr(d[@"id"]) isEqualToString:videoId]) return YES;
    return NO;
}

+ (void)saveVideoJSON:(NSDictionary *)json
{
    NSString *vid = TKStr(json[@"id"]);
    if (!vid.length) return;
    NSMutableArray *list = [[self savedVideos] mutableCopy];
    for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--) if ([TKStr(list[(NSUInteger)i][@"id"]) isEqualToString:vid]) [list removeObjectAtIndex:(NSUInteger)i];
    [list insertObject:json atIndex:0];
    while (list.count > TKMaxSaved) [list removeLastObject];
    [DEF setObject:list forKey:@"savedVideos"];
    [self save];
    [self notifyLibrary];
}

+ (void)unsaveVideo:(NSString *)videoId
{
    NSMutableArray *list = [[self savedVideos] mutableCopy];
    for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--) if ([TKStr(list[(NSUInteger)i][@"id"]) isEqualToString:videoId]) [list removeObjectAtIndex:(NSUInteger)i];
    [DEF setObject:list forKey:@"savedVideos"];
    [self save];
    [self notifyLibrary];
}

#pragma mark - Seen videos

+ (BOOL)hasSeenVideo:(NSString *)videoId
{
    if (!videoId.length) return NO;
    return [[DEF arrayForKey:@"seenVideos"] containsObject:videoId];
}

+ (void)markVideoSeen:(NSString *)videoId
{
    if (!videoId.length) return;
    NSMutableArray *seen = [[DEF arrayForKey:@"seenVideos"] mutableCopy] ?: [NSMutableArray array];
    [seen removeObject:videoId];
    [seen addObject:videoId];
    while (seen.count > TKMaxSeen) [seen removeObjectAtIndex:0];
    [DEF setObject:seen forKey:@"seenVideos"];
}

#pragma mark - Recent searches

+ (NSArray *)recentSearches { return [DEF arrayForKey:@"recentSearches"] ?: @[]; }

+ (void)addRecentSearch:(NSString *)query
{
    NSString *q = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!q.length) return;
    NSMutableArray *list = [[self recentSearches] mutableCopy];
    [list removeObject:q];
    [list insertObject:q atIndex:0];
    while (list.count > 20) [list removeLastObject];
    [DEF setObject:list forKey:@"recentSearches"];
    [self save];
}

@end
