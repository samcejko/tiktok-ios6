#import "TKExternalOpen.h"
#import "TKUtils.h"
#import "TKCommon.h"

@implementation TKExternalOpen

+ (BOOL)surfariAvailable
{
    return [[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"surfari://open?url=https://youtube.com/"]];
}

+ (NSURL *)surfariURLForURL:(NSURL *)url
{
    NSString *encoded = [TKUtils urlEncode:url.absoluteString ?: @""];
    return [NSURL URLWithString:[@"surfari://open?url=" stringByAppendingString:encoded]];
}

+ (NSString *)openInBrowserTitle { return [self surfariAvailable] ? L(@"Open in Surfari") : L(@"Open in Safari"); }

+ (void)openInBrowser:(NSURL *)url
{
    if (!url || ![[url.scheme lowercaseString] hasPrefix:@"http"]) return;
    [[UIApplication sharedApplication] openURL:[self surfariAvailable] ? [self surfariURLForURL:url] : url];
}

@end
