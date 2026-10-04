#import <UIKit/UIKit.h>
@class TKVideo;

// Read-only comments for one video (from the Pi helper, best effort).
@interface TKCommentsViewController : UITableViewController
- (instancetype)initWithVideo:(TKVideo *)video;
@end
