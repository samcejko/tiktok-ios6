#import <UIKit/UIKit.h>

// Opens what a TikTok link points to: a video or photo post (resolved, then shown full screen), a creator's profile,
// a live room. Short links (vm.tiktok.com, vt.tiktok.com, /t/...) are expanded by the helper first. Used by the
// "Open a link" menu, the tikie: URL scheme and links handed over by other apps (Surfari).
@interface TKLinkRouter : NSObject

+ (BOOL)openLink:(NSString *)link;                                  // NO when it is not a TikTok link at all
+ (void)openVideoId:(NSString *)videoId author:(NSString *)author;
+ (void)openProfile:(NSString *)handle;
+ (void)openLiveRoom:(NSString *)roomId;

+ (UIViewController *)topController;                               // what is on screen (the one to present from)
+ (void)presentInNavigation:(UIViewController *)controller;         // a sheet (form sheet on the iPad) with a bar

@end
