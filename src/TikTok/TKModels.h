#import <Foundation/Foundation.h>

// One public TikTok video, as the Pi helper describes it. The lightweight list form has no playUrl yet; it is
// filled in by -[TKTikTok resolve:...] right before playback (the direct URL is short-lived).
@interface TKVideo : NSObject
@property (nonatomic, copy) NSString *videoId;
@property (nonatomic, copy) NSString *author;        // @handle without the @
@property (nonatomic, copy) NSString *authorName;    // display name
@property (nonatomic, copy) NSString *desc;
@property (nonatomic, copy) NSString *coverURL;
@property (nonatomic, copy) NSString *webURL;        // the tiktok.com page (for "open in...")
@property (nonatomic, copy) NSString *music;
@property (nonatomic) NSInteger likes;
@property (nonatomic) NSInteger commentCount;
@property (nonatomic) NSInteger plays;
@property (nonatomic) NSInteger durationSeconds;
@property (nonatomic) NSInteger width;
@property (nonatomic) NSInteger height;
// Filled by resolve:
@property (nonatomic, copy) NSString *playURL;       // the TikTok CDN URL
@property (nonatomic, copy) NSDictionary *playHeaders; // Referer/User-Agent/Cookie the CDN needs

+ (instancetype)videoFromJSON:(NSDictionary *)json;
- (NSDictionary *)toJSON;                             // for the local saved/cache store
- (NSString *)shareURL;
@end

@interface TKComment : NSObject
@property (nonatomic, copy) NSString *author;
@property (nonatomic, copy) NSString *text;
@property (nonatomic) NSInteger likes;
+ (instancetype)commentFromJSON:(NSDictionary *)json;
@end
