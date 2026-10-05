#import <UIKit/UIKit.h>

// Opens a web link outside the app: in Surfari, the iOS 6 browser of this family, when it is installed, else in Safari.
@interface TKExternalOpen : NSObject

// Whether Surfari is installed (its URL scheme answers)
+ (BOOL)surfariAvailable;
// "Open in Surfari" or "Open in Safari", whichever openInBrowser: will use
+ (NSString *)openInBrowserTitle;
+ (void)openInBrowser:(NSURL *)url;

@end
