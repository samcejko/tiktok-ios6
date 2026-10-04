#import <Foundation/Foundation.h>
#import "TKModels.h"

@class TKHTTPTask;

// Talks to the Pi helper (the only server this app needs). All completions run on the main thread.
@interface TKTikTok : NSObject

+ (BOOL)configured;                          // a server base URL is set
+ (void)checkHealth:(void (^)(BOOL ok, NSString *info, NSError *error))completion;

// A fresh batch from TikTok's Explore feed for one topic (an Explore CategoryType). Ready to play: playURL and
// playHeaders are set, and every item carries the features the recommender learns from.
+ (TKHTTPTask *)discoverCategory:(NSInteger)category count:(NSInteger)count completion:(void (^)(NSArray *videos, NSError *error))completion;

// A creator's recent public videos (lightweight items; call resolveVideo: before playing one)
+ (TKHTTPTask *)videosForCreator:(NSString *)handle count:(NSInteger)count completion:(void (^)(NSArray *videos, NSError *error))completion;

// Fills in playURL + playHeaders (short-lived). Pass a TKVideo from a list, or build one with just videoId set.
+ (TKHTTPTask *)resolveVideo:(TKVideo *)video completion:(void (^)(TKVideo *resolved, NSError *error))completion;
+ (TKHTTPTask *)resolveId:(NSString *)videoId author:(NSString *)author completion:(void (^)(TKVideo *resolved, NSError *error))completion;

+ (TKHTTPTask *)commentsForVideo:(NSString *)videoId count:(NSInteger)count completion:(void (^)(NSArray *comments, NSError *error))completion;
+ (TKHTTPTask *)repliesForVideo:(NSString *)videoId comment:(NSString *)commentId count:(NSInteger)count completion:(void (^)(NSArray *replies, NSError *error))completion;

// A creator's page: who they are and their recent posts
+ (TKHTTPTask *)profileForUser:(NSString *)handle completion:(void (^)(TKProfile *profile, NSError *error))completion;

// Live: one room (is it on, its streams), and the rooms seen lately among Explore authors (NSDictionary: room, user,
// name, avatar) - the only way to find live streams without an account
+ (TKHTTPTask *)liveRoom:(NSString *)roomId completion:(void (^)(TKLiveRoom *room, NSError *error))completion;
+ (TKHTTPTask *)liveRooms:(void (^)(NSArray *rooms, NSError *error))completion;

// Where a (short) TikTok link leads
+ (TKHTTPTask *)expandLink:(NSString *)link completion:(void (^)(NSString *url, NSError *error))completion;

// The Pi /proxy URL that streams a resolved video's bytes through the Pi (fallback, and for use away from home)
+ (NSString *)proxyURLForPlayURL:(NSString *)playURL;

@end
