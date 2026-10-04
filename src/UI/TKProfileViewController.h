#import <UIKit/UIKit.h>

// A creator's page: avatar, name, bio, counts and a grid of their recent posts (tap one: they play full screen,
// and you can swipe on through the rest). No following - the feed finds videos on its own.
@interface TKProfileViewController : UIViewController
- (instancetype)initWithHandle:(NSString *)handle;
@end
