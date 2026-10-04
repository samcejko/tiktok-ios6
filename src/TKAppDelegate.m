#import "TKAppDelegate.h"
#import "TKFeedViewController.h"
#import "TKVideoCell.h"
#import "TKTaste.h"
#import "TKDiscoverViewController.h"
#import "TKTikTok.h"
#import "TKModels.h"
#import "TKMediaProxy.h"
#import "TKTLSSocket.h"
#import "TKImageLoader.h"
#import "TKSettings.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"
#include <dlfcn.h>
#include <signal.h>
#include <mach/mach.h>

static BOOL TKButtonMatches(UIButton *button, NSString *text)
{
    for (NSString *name in @[ button.currentTitle ?: @"", button.accessibilityLabel ?: @"" ])
        if (name.length && [name rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    return NO;
}

static BOOL TKViewContainsText(UIView *view, NSString *text)
{
    if ([view isKindOfClass:[UILabel class]]) {
        NSString *s = ((UILabel *)view).text;
        return s.length && [s rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound;
    }
    for (UIView *sub in view.subviews) { if ([sub isKindOfClass:[UIControl class]]) continue; if (TKViewContainsText(sub, text)) return YES; }
    return NO;
}

static BOOL TKPressView(UIView *v, NSString *text)
{
    if ([v isKindOfClass:[UIButton class]]) {
        if (!TKButtonMatches((UIButton *)v, text)) return NO;
        [(UIButton *)v sendActionsForControlEvents:UIControlEventTouchUpInside];
        return YES;
    }
    if ([v isKindOfClass:[UITableViewCell class]]) {
        UITableViewCell *cell = (UITableViewCell *)v;
        if (!TKViewContainsText(cell, text)) return NO;
        UIView *table = cell.superview;
        while (table && ![table isKindOfClass:[UITableView class]]) table = table.superview;
        NSIndexPath *ip = [(UITableView *)table indexPathForCell:cell];
        id<UITableViewDelegate> delegate = [(UITableView *)table delegate];
        if (!ip || ![delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) return NO;
        [delegate tableView:(UITableView *)table didSelectRowAtIndexPath:ip];
        return YES;
    }
    return NO;
}

@implementation TKAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    signal(SIGPIPE, SIG_IGN);
    [TKSettings registerDefaults];
    TKLog(@"Tikie %@ starting on %@ (iOS %@)", [TKUtils appVersion], [TKUtils deviceModel], [UIDevice currentDevice].systemVersion);
    [TKTLSSocket warmUp];
    [[TKImageLoader shared] pruneDisk];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.feed = [[TKFeedViewController alloc] init];
    self.window.rootViewController = self.feed;
    self.window.backgroundColor = [UIColor blackColor];
    [self.window makeKeyAndVisible];
    [application setStatusBarStyle:UIStatusBarStyleBlackOpaque animated:NO];
    return YES;
}

- (UIViewController *)topController
{
    UIViewController *top = self.window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    if ([top isKindOfClass:[UINavigationController class]]) top = [(UINavigationController *)top topViewController];
    return top;
}

- (void)playVideoId:(NSString *)vid author:(NSString *)author
{
    [TKTikTok resolveId:vid author:author completion:^(TKVideo *resolved, NSError *error) {
        if (!resolved) { [TKUtils alertWithTitle:L(@"Open a video link") message:error.localizedDescription ?: L(@"This video could not be loaded.")]; return; }
        TKFeedViewController *feed = [[TKFeedViewController alloc] initWithVideos:@[ resolved ] startIndex:0 title:resolved.author.length ? [@"@" stringByAppendingString:resolved.author] : L(@"Video")];
        feed.modalPresentationStyle = UIModalPresentationFullScreen;
        UIViewController *top = self.window.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;
        [top presentViewController:feed animated:YES completion:nil];
    }];
}

// tikie:add?u=@handle, tikie:play/<id>, and tiktok.com links. Debug commands (need Documents/debug): snapshot,
// screen, press?title=/n=, back, stats, swipe[?dir=down], remove?u=, taste[?reset=1], gesture?type=double|hold|scrub[&f=].
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    NSString *s = url.absoluteString ?: @"";
    NSString *lower = [s lowercaseString];
    if ([lower rangeOfString:@"tiktok.com"].location != NSNotFound && ([lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"])) {
        NSRange r = [s rangeOfString:@"/video/"];
        if (r.location != NSNotFound) {
            NSString *tail = [s substringFromIndex:r.location + r.length];
            NSMutableString *vid = [NSMutableString string];
            for (NSUInteger i = 0; i < tail.length; i++) { unichar c = [tail characterAtIndex:i]; if (c >= '0' && c <= '9') [vid appendFormat:@"%C", c]; else break; }
            if (vid.length) { [self playVideoId:vid author:nil]; return YES; }
        }
        return NO;
    }
    if (![lower hasPrefix:@"tikie:"]) return NO;
    NSString *target = [s substringFromIndex:@"tikie:".length];
    while ([target hasPrefix:@"/"]) target = [target substringFromIndex:1];
    NSString *query = nil;
    NSRange q = [target rangeOfString:@"?"];
    if (q.location != NSNotFound) { query = [target substringFromIndex:q.location + 1]; target = [target substringToIndex:q.location]; }
    NSDictionary *params = query.length ? [TKUtils parseQuery:query] : @{};
    if ([target hasPrefix:@"play/"]) { [self playVideoId:[target substringFromIndex:@"play/".length] author:nil]; return YES; }
    if ([target isEqualToString:@"add"] && [params[@"u"] length]) { [TKSettings addCreator:params[@"u"]]; return YES; }
    // tikie:server?url=<base>&key=<key> - set the helper address (also how you hand the app to other people)
    if ([target isEqualToString:@"server"]) {
        if ([params[@"url"] length]) [TKSettings setServerBaseURL:params[@"url"]];
        if (params[@"key"]) [TKSettings setServerKey:params[@"key"]];
        [TKUtils alertWithTitle:L(@"Settings") message:[TKSettings serverBaseURL].length ? [NSString stringWithFormat:@"%@%@", [TKSettings serverBaseURL], [TKSettings serverKey].length ? L(@" (key set)") : @""] : L(@"Not set")];
        return YES;
    }

    BOOL debug = [[NSFileManager defaultManager] fileExistsAtPath:[[TKUtils documentsPath] stringByAppendingPathComponent:@"debug"]];
    if (!debug) return YES;
    UIViewController *top = [self topController];
    if ([target isEqualToString:@"stats"]) {
        struct task_basic_info info; mach_msg_type_number_t count = TASK_BASIC_INFO_COUNT;
        if (task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &count) == KERN_SUCCESS)
            TKLog(@"Memory: %.1f MB resident", info.resident_size / 1048576.0);
        TKLog(@"Top: %@, server %@ (%@), creators %lu, saved %lu, proxy %@", NSStringFromClass([top class]), [TKSettings serverBaseURL],
              [TKSettings serverKey].length ? @"keyed" : @"no key", (unsigned long)[TKSettings creators].count, (unsigned long)[TKSettings savedVideos].count,
              [[TKMediaProxy shared] statsDescription]);
        return YES;
    }
    if ([target isEqualToString:@"proxylog"]) { [TKMediaProxy shared].logRequests = ![params[@"on"] isEqualToString:@"0"]; return YES; }
    if ([target isEqualToString:@"snapshot"] || [target isEqualToString:@"screen"]) {
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"screen.png"];
        BOOL ok = NO;
        if ([target isEqualToString:@"screen"]) {
            CGImageRef (*grab)(void) = (CGImageRef (*)(void))dlsym(RTLD_DEFAULT, "UIGetScreenImage");
            CGImageRef shot = grab ? grab() : NULL;
            if (shot) { ok = [UIImagePNGRepresentation([UIImage imageWithCGImage:shot]) writeToFile:path atomically:YES]; CGImageRelease(shot); }
        } else {
            CGSize size = [UIScreen mainScreen].bounds.size;
            UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
            for (UIWindow *w in [UIApplication sharedApplication].windows) if (!w.hidden && w.alpha > 0) [w.layer renderInContext:UIGraphicsGetCurrentContext()];
            ok = [UIImagePNGRepresentation(UIGraphicsGetImageFromCurrentImageContext()) writeToFile:path atomically:YES];
            UIGraphicsEndImageContext();
        }
        TKLog(@"%@ %@: %@", target, ok ? @"written" : @"failed", path);
        return YES;
    }
    if ([target isEqualToString:@"press"]) {
        NSString *byTitle = params[@"title"];
        NSInteger n = [params[@"n"] integerValue];
        NSMutableArray *views = [NSMutableArray array];
        for (UIWindow *w in [UIApplication sharedApplication].windows) [views addObject:w];
        BOOL pressed = NO;
        for (NSUInteger i = 0; i < views.count && !pressed; i++) {
            UIView *v = views[i];
            if (!byTitle.length && [v isKindOfClass:[UIActionSheet class]] && ((UIActionSheet *)v).visible) {
                UIActionSheet *sheet = (UIActionSheet *)v;
                if ([sheet.delegate respondsToSelector:@selector(actionSheet:clickedButtonAtIndex:)]) [sheet.delegate actionSheet:sheet clickedButtonAtIndex:n];
                [sheet dismissWithClickedButtonIndex:n animated:NO];
                pressed = YES;
            } else if (!byTitle.length && [v isKindOfClass:[UIAlertView class]] && ((UIAlertView *)v).visible) {
                UIAlertView *alert = (UIAlertView *)v;
                if ([alert.delegate respondsToSelector:@selector(alertView:clickedButtonAtIndex:)]) [alert.delegate alertView:alert clickedButtonAtIndex:n];
                [alert dismissWithClickedButtonIndex:n animated:NO];
                pressed = YES;
            } else if (byTitle.length && !v.hidden && TKPressView(v, byTitle)) {
                pressed = YES;
            } else {
                [views addObjectsFromArray:v.subviews];
            }
        }
        TKLog(@"Press %@: %@", query ?: @"", pressed ? @"done" : @"nothing found");
        return YES;
    }
    if ([target isEqualToString:@"swipe"]) {
        // move the feed by one page (up = next). The feed listens to its scroll view; nudge it directly.
        for (UIScrollView *sv in [self scrollViewsIn:top.view]) {
            if (sv.contentSize.height > sv.bounds.size.height + 1) {
                CGFloat dir = [params[@"dir"] isEqualToString:@"down"] ? -1 : 1;
                CGFloat y = MAX(0, MIN(sv.contentSize.height - sv.bounds.size.height, sv.contentOffset.y + dir * sv.bounds.size.height));
                [sv setContentOffset:CGPointMake(0, y) animated:YES];
                break;
            }
        }
        return YES;
    }
    if ([target isEqualToString:@"remove"] && [params[@"u"] length]) {
        [TKSettings removeCreator:params[@"u"]];
        TKLog(@"Creators now: %@", [[TKSettings creators] componentsJoinedByString:@", "]);
        return YES;
    }
    if ([target isEqualToString:@"taste"]) {
        if ([params[@"reset"] isEqualToString:@"1"]) [[TKTaste shared] reset];
        TKLog(@"%@", [[TKTaste shared] summary]);
        return YES;
    }
    // the gestures' actions on the page on screen: double (save), hold (menu), scrub&f=0.5 (seek to half)
    if ([target isEqualToString:@"gesture"]) {
        TKVideoCell *cell = [top isKindOfClass:[TKFeedViewController class]] ? [(TKFeedViewController *)top currentCell] : nil;
        NSString *type = params[@"type"];
        if (!cell) TKLog(@"Gesture %@: no video page on screen", type);
        else if ([type isEqualToString:@"double"]) [cell simulateDoubleTap];
        else if ([type isEqualToString:@"hold"]) [cell simulateLongPress];
        else if ([type isEqualToString:@"scrub"]) [cell simulateScrubTo:(CGFloat)[params[@"f"] doubleValue]];
        if (cell) TKLog(@"Gesture %@ done: %@ at %.1f / %.1f s, rate %.2f, 2x %d, saved %d", type, cell.video.videoId, cell.currentTime, cell.duration,
                        [cell playerRate], cell.fastPlayback, [TKSettings isSaved:cell.video.videoId]);
        return YES;
    }
    if ([target isEqualToString:@"back"]) {
        if (top != self.feed && [self topController].presentingViewController) [[self topController] dismissViewControllerAnimated:YES completion:nil];
        return YES;
    }
    return YES;
}

- (NSArray *)scrollViewsIn:(UIView *)view
{
    NSMutableArray *out = [NSMutableArray array];
    NSMutableArray *stack = [NSMutableArray arrayWithObject:view];
    while (stack.count) { UIView *v = stack.lastObject; [stack removeLastObject]; if ([v isKindOfClass:[UIScrollView class]]) [out addObject:v]; [stack addObjectsFromArray:v.subviews]; }
    return out;
}

- (void)applicationWillEnterForeground:(UIApplication *)application { [[TKMediaProxy shared] ensureRunning]; }
- (void)applicationDidEnterBackground:(UIApplication *)application { [TKSettings save]; }

@end
