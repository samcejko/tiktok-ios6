#import <Foundation/Foundation.h>
#import "TKModels.h"

// Our own "For You": it pulls the recent public videos of the creators you follow and orders them with a local
// score (creators whose videos you finish or save rise, ones you skip fall), plus some randomness. No TikTok
// account, no real FYP - just your sources, ranked by your behaviour.
@interface TKFeed : NSObject

@property (nonatomic, readonly) NSArray *videos;     // TKVideo, in feed order
@property (nonatomic, readonly) BOOL loading;

// Clears and loads the first batch from the followed creators.
- (void)reloadWithCompletion:(void (^)(NSError *error))completion;
// Makes sure there are items at least `count` past `index`, fetching/ranking more when needed.
- (void)ensureAhead:(NSInteger)index by:(NSInteger)count completion:(void (^)(BOOL added))completion;

// Behaviour feedback (drives the ranking and "seen" memory)
- (void)noteVideo:(TKVideo *)video completed:(BOOL)completed saved:(BOOL)saved skipped:(BOOL)skipped;

@end
