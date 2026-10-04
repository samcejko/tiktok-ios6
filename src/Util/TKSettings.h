#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// User preferences in NSUserDefaults (the server key is in the keychain). Setters post TKSettingsDidChangeNotification.
@interface TKSettings : NSObject

+ (void)registerDefaults;
+ (void)save;

// The Pi helper
+ (NSString *)serverBaseURL;            // e.g. http://192.168.1.154:8730 or https://ytdlp.samcejko.eu
+ (void)setServerBaseURL:(NSString *)value;
+ (NSString *)serverKey;                // keychain; "" when none
+ (void)setServerKey:(NSString *)value;
+ (BOOL)serverConfigured;
+ (BOOL)streamThroughServer;            // force video through the Pi /proxy (for use away from home); default NO
+ (void)setStreamThroughServer:(BOOL)value;

// Playback
+ (BOOL)startMuted;
+ (void)setStartMuted:(BOOL)value;
+ (BOOL)autoAdvance;                    // move to the next video when one ends
+ (void)setAutoAdvance:(BOOL)value;

// Appearance
+ (BOOL)darkTheme;
+ (void)setDarkTheme:(BOOL)value;

// Network
+ (BOOL)verifyTLS;
+ (void)setVerifyTLS:(BOOL)value;

// Followed creators (optional): their videos join the feed now and then (handles without @, newest added first)
+ (NSArray *)creators;
+ (void)addCreator:(NSString *)handle;
+ (void)removeCreator:(NSString *)handle;
+ (BOOL)hasCreator:(NSString *)handle;

// Saved videos (each is TKVideo -toJSON; newest first)
+ (NSArray *)savedVideos;
+ (BOOL)isSaved:(NSString *)videoId;
+ (void)saveVideoJSON:(NSDictionary *)json;
+ (void)unsaveVideo:(NSString *)videoId;

// Videos already shown (the feed does not bring them back; the taste itself lives in TKTaste)
+ (BOOL)hasSeenVideo:(NSString *)videoId;
+ (void)markVideoSeen:(NSString *)videoId;

// Searches/creators the user has typed (for quick re-add)
+ (NSArray *)recentSearches;
+ (void)addRecentSearch:(NSString *)query;

@end
