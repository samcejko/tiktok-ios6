#import <UIKit/UIKit.h>

@class TKVideoCell;

// The vertical, full-screen video feed. Default mode draws from TKFeed (our own "For You" over TikTok's Explore
// topics, learned from how you watch). A fixed list (saved videos, or a single opened link) is shown with
// -initWithVideos:startIndex:title:.
@interface TKFeedViewController : UIViewController
- (instancetype)initWithVideos:(NSArray *)videos startIndex:(NSInteger)startIndex title:(NSString *)title;  // fixed list
- (TKVideoCell *)currentCell;      // the page on screen (for the debug commands)
@end
