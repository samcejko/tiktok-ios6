#import "TKLinkRouter.h"
#import "TKFeedViewController.h"
#import "TKProfileViewController.h"
#import "TKLivePlayerViewController.h"
#import "TKTikTok.h"
#import "TKModels.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"

@implementation TKLinkRouter

+ (UIViewController *)topController
{
    UIViewController *top = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

+ (void)presentInNavigation:(UIViewController *)controller
{
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:controller];
    [[TKTheme shared] applyToNavigationBar:nav.navigationBar];
    if (TKIsPad()) nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [[self topController] presentViewController:nav animated:YES completion:nil];
}

+ (void)busy:(BOOL)busy { [UIApplication sharedApplication].networkActivityIndicatorVisible = busy; }

// The digits that follow `marker` in `s` ("/video/123..." -> "123..."), nil when there are none
+ (NSString *)digitsAfter:(NSString *)marker in:(NSString *)s
{
    NSRange r = [s rangeOfString:marker];
    if (r.location == NSNotFound) return nil;
    NSMutableString *d = [NSMutableString string];
    for (NSUInteger i = r.location + r.length; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c < '0' || c > '9') break;
        [d appendFormat:@"%C", c];
    }
    return d.length >= 6 ? d : nil;
}

// "@handle" in a path ("/@name/video/1" -> "name")
+ (NSString *)handleIn:(NSString *)path
{
    NSRange at = [path rangeOfString:@"/@"];
    if (at.location == NSNotFound) return nil;
    NSString *rest = [path substringFromIndex:at.location + 2];
    NSString *handle = [[rest componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/?#"]] firstObject];
    return handle.length ? handle : nil;
}

+ (BOOL)openLink:(NSString *)link { return [self openLink:link expanded:NO]; }

+ (BOOL)openLink:(NSString *)link expanded:(BOOL)expanded
{
    NSString *s = [link stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    if (!s.length) return NO;
    // a bare video id
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if (s.length >= 6 && [s rangeOfCharacterFromSet:nonDigits].location == NSNotFound) { [self openVideoId:s author:nil]; return YES; }
    if ([[s lowercaseString] rangeOfString:@"tiktok.com"].location == NSNotFound) return NO;
    if (![[s lowercaseString] hasPrefix:@"http"]) s = [@"https://" stringByAppendingString:s];
    NSURL *url = [NSURL URLWithString:s];
    NSString *host = [url.host lowercaseString] ?: @"";
    NSString *path = url.path ?: @"";
    if (![host isEqualToString:@"tiktok.com"] && ![host hasSuffix:@".tiktok.com"]) return NO;

    // short links lead somewhere else: ask the helper where (once)
    BOOL shortLink = [host hasPrefix:@"vm."] || [host hasPrefix:@"vt."] || [path hasPrefix:@"/t/"];
    if (shortLink && !expanded) {
        [self busy:YES];
        [TKTikTok expandLink:s completion:^(NSString *target, NSError *error) {
            [self busy:NO];
            if (!target.length || ![self openLink:target expanded:YES])
                [TKUtils alertWithTitle:L(@"Open a link") message:error.localizedDescription ?: L(@"That does not look like a TikTok link.")];
        }];
        return YES;
    }
    NSString *handle = [self handleIn:path];
    NSString *vid = [self digitsAfter:@"/video/" in:path] ?: [self digitsAfter:@"/photo/" in:path];
    if (vid) { [self openVideoId:vid author:handle]; return YES; }
    if (handle && [[[path lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]] hasSuffix:@"/live"]) {
        [self openLiveOf:handle];
        return YES;
    }
    if (handle) { [self openProfile:handle]; return YES; }
    return NO;
}

// "tiktok.com/@name/live": the room comes from their profile; when they are not live, the profile itself
+ (void)openLiveOf:(NSString *)handle
{
    [self busy:YES];
    [TKTikTok profileForUser:handle completion:^(TKProfile *profile, NSError *error) {
        [self busy:NO];
        if (profile.liveRoom.length) { [self openLiveRoom:profile.liveRoom]; return; }
        [self openProfile:handle];
        if (profile) [TKUtils alertWithTitle:L(@"Live now") message:[NSString stringWithFormat:L(@"@%@ is not live right now."), profile.handle.length ? profile.handle : handle]];
    }];
}

+ (void)openVideoId:(NSString *)videoId author:(NSString *)author
{
    [self busy:YES];
    [TKTikTok resolveId:videoId author:author completion:^(TKVideo *resolved, NSError *error) {
        [self busy:NO];
        if (!resolved) { [TKUtils alertWithTitle:L(@"Open a link") message:error.localizedDescription ?: L(@"This video could not be loaded.")]; return; }
        TKFeedViewController *feed = [[TKFeedViewController alloc] initWithVideos:@[ resolved ] startIndex:0 title:resolved.author.length ? [@"@" stringByAppendingString:resolved.author] : L(@"Video")];
        feed.modalPresentationStyle = UIModalPresentationFullScreen;
        [[self topController] presentViewController:feed animated:YES completion:nil];
    }];
}

+ (void)openProfile:(NSString *)handle
{
    if (!handle.length) return;
    [self presentInNavigation:[[TKProfileViewController alloc] initWithHandle:handle]];
}

+ (void)openLiveRoom:(NSString *)roomId
{
    NSString *digits = [[roomId componentsSeparatedByCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]] componentsJoinedByString:@""];
    if (!digits.length) return;
    TKLivePlayerViewController *live = [[TKLivePlayerViewController alloc] initWithRoomId:digits];
    live.modalPresentationStyle = UIModalPresentationFullScreen;
    UIViewController *top = [self topController];
    if ([top isKindOfClass:[TKLivePlayerViewController class]]) {
        // another stream on screen (a link from another app): this one takes its place
        UIViewController *under = top.presentingViewController;
        [under dismissViewControllerAnimated:NO completion:^{ [under presentViewController:live animated:YES completion:nil]; }];
        return;
    }
    [top presentViewController:live animated:YES completion:nil];
}

@end
