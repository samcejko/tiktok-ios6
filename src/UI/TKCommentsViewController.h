#import <UIKit/UIKit.h>
@class TKVideo;

// Read-only comments for one video (from the Pi helper, best effort), with the replies under a comment on a tap.
// As a sheet it has a Done button; as the side panel of the feed on a landscape iPad it follows the page on screen.
@interface TKCommentsViewController : UITableViewController
- (instancetype)initWithVideo:(TKVideo *)video;
- (instancetype)initAsPanel;
- (void)showVideo:(TKVideo *)video;          // (the panel) switch to another video's comments
@end
