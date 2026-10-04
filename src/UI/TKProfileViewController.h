#import <UIKit/UIKit.h>

// A creator's page: avatar, name, bio, counts and a grid of their recent posts (tap one: they play full screen,
// and you can swipe on through the rest). While they are live, a button opens the stream. No following - the feed
// finds videos on its own.
@interface TKProfileViewController : UIViewController
- (instancetype)initWithHandle:(NSString *)handle;
@property (nonatomic, copy, readonly) NSString *handle;
@end
