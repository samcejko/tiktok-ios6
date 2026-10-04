#import <UIKit/UIKit.h>

// The vertical, full-screen video feed. Default mode draws from TKFeed (your creators, ranked locally). A fixed
// list (saved videos, or a single opened link) is shown with -initWithVideos:startIndex:title:.
@interface TKFeedViewController : UIViewController
- (instancetype)initWithVideos:(NSArray *)videos startIndex:(NSInteger)startIndex title:(NSString *)title;  // fixed list
@end
