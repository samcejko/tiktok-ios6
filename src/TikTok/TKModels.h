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
// What the recommender learns from (a /discover item carries all of it; other sources fill what they can)
@property (nonatomic) NSInteger category;            // TikTok's topic id (Explore CategoryType), 0 = unknown
@property (nonatomic, copy) NSArray *tags;           // hashtags, lowercased, without the #
@property (nonatomic, copy) NSString *musicId;
@property (nonatomic) BOOL musicOriginal;            // the creator's own sound: unique to the video, says nothing
@property (nonatomic, copy) NSString *lang;          // TikTok's guess of the caption language ("en", "cs", "un")
@property (nonatomic) NSTimeInterval createdAt;      // posted (Unix time), 0 = unknown
@property (nonatomic, copy) NSString *authorAvatarURL;
@property (nonatomic, copy) NSString *authorLiveRoom; // set while the author is live (a room id)
// A photo post (slideshow) instead of a video: its pictures and, when TikTok gives one to a visitor, its sound
@property (nonatomic) BOOL isPhoto;
@property (nonatomic, copy) NSArray *imageURLs;      // NSString, JPEG
@property (nonatomic, copy) NSString *audioURL;
// Filled by resolve (or handed out ready by /discover):
@property (nonatomic, copy) NSString *playURL;       // the TikTok CDN URL
@property (nonatomic, copy) NSDictionary *playHeaders; // Referer/User-Agent/Cookie the CDN needs
@property (nonatomic) NSTimeInterval fetchedAt;      // when playURL was handed out (it lasts about two days)
@property (nonatomic, readonly) BOOL playable;        // has what it needs to show: a play URL, or pictures

+ (instancetype)videoFromJSON:(NSDictionary *)json;
- (NSDictionary *)toJSON;                             // for the local saved/cache store
- (NSString *)shareURL;
@end

@interface TKComment : NSObject
@property (nonatomic, copy) NSString *commentId;
@property (nonatomic, copy) NSString *author;
@property (nonatomic, copy) NSString *text;
@property (nonatomic) NSInteger likes;
@property (nonatomic) NSInteger replyCount;
@property (nonatomic) BOOL pinned;
@property (nonatomic) BOOL isReply;
+ (instancetype)commentFromJSON:(NSDictionary *)json;
@end

// A creator's profile page
@interface TKProfile : NSObject
@property (nonatomic, copy) NSString *handle;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *bio;
@property (nonatomic, copy) NSString *avatarURL;
@property (nonatomic, copy) NSString *liveRoom;       // set while they are live
@property (nonatomic) BOOL verified;
@property (nonatomic) long long followers;
@property (nonatomic) long long likes;
@property (nonatomic) NSInteger videoCount;
@property (nonatomic, copy) NSArray *videos;         // TKVideo (lightweight: resolved when played)
+ (instancetype)profileFromJSON:(NSDictionary *)json;
@end

// A live room and the streams TikTok hands a visitor
@interface TKLiveRoom : NSObject
@property (nonatomic, copy) NSString *roomId;
@property (nonatomic) BOOL live;
@property (nonatomic, copy) NSString *title;
@property (nonatomic) NSInteger viewers;
@property (nonatomic, copy) NSString *coverURL;
@property (nonatomic, copy) NSString *ownerHandle;
@property (nonatomic, copy) NSString *ownerName;
@property (nonatomic, copy) NSString *ownerAvatarURL;
@property (nonatomic, copy) NSArray *streams;        // NSDictionary: quality, flv, hls, vcodec, resolution
@property (nonatomic, copy) NSDictionary *headers;
+ (instancetype)roomFromJSON:(NSDictionary *)json;
@end
