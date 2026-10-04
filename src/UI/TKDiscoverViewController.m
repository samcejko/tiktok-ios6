#import "TKDiscoverViewController.h"
#import "TKFeedViewController.h"
#import "TKTikTok.h"
#import "TKModels.h"
#import "TKSettings.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"

enum { SecActions, SecCreators, SecCount };

@interface TKDiscoverViewController () <UIAlertViewDelegate>
@end

@implementation TKDiscoverViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = L(@"Creators");
    [[TKTheme shared] applyToTableView:self.tableView];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addCreator)];
}

- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }

- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return SecCount; }

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s
{
    if (s == SecActions) return 2;
    return (NSInteger)[TKSettings creators].count;
}

- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s
{
    if (s == SecCreators) return [TKSettings creators].count ? L(@"Your creators") : nil;
    return nil;
}

- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s
{
    if (s == SecCreators && ![TKSettings creators].count) return L(@"Add a few creators. Your feed mixes their newest videos and learns what you watch.");
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    [[TKTheme shared] styleCell:cell];
    if (ip.section == SecActions) {
        cell.textLabel.text = ip.row == 0 ? L(@"Add a creator") : L(@"Open a video link");
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.textLabel.text = [@"@" stringByAppendingString:[TKSettings creators][(NSUInteger)ip.row]];
    }
    return cell;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [t deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == SecActions) { ip.row == 0 ? [self addCreator] : [self openLink]; return; }
}

- (BOOL)tableView:(UITableView *)t canEditRowAtIndexPath:(NSIndexPath *)ip { return ip.section == SecCreators; }

- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip
{
    if (style == UITableViewCellEditingStyleDelete) {
        [TKSettings removeCreator:[TKSettings creators][(NSUInteger)ip.row]];
        [t reloadData];
    }
}

- (void)addCreator
{
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:L(@"Add a creator") message:L(@"Enter a @handle or paste a TikTok profile link.") delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Add"), nil];
    a.alertViewStyle = UIAlertViewStylePlainTextInput;
    a.tag = 1;
    [a show];
}

- (void)openLink
{
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:L(@"Open a video link") message:L(@"Paste a TikTok video link.") delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Open"), nil];
    a.alertViewStyle = UIAlertViewStylePlainTextInput;
    a.tag = 2;
    [a show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) return;
    NSString *text = [[alertView textFieldAtIndex:0] text];
    if (!text.length) return;
    if (alertView.tag == 1) {
        [TKSettings addCreator:text];
        [TKSettings addRecentSearch:text];
        [self.tableView reloadData];
    } else {
        [self openVideoLink:text];
    }
}

- (void)openVideoLink:(NSString *)link
{
    NSString *vid = nil;
    NSRange r = [link rangeOfString:@"/video/"];
    if (r.location != NSNotFound) {
        NSString *tail = [link substringFromIndex:r.location + r.length];
        NSMutableString *digits = [NSMutableString string];
        for (NSUInteger i = 0; i < tail.length; i++) { unichar c = [tail characterAtIndex:i]; if (c >= '0' && c <= '9') [digits appendFormat:@"%C", c]; else break; }
        vid = digits;
    } else {
        NSMutableString *digits = [NSMutableString string];
        for (NSUInteger i = 0; i < link.length; i++) { unichar c = [link characterAtIndex:i]; if (c >= '0' && c <= '9') [digits appendFormat:@"%C", c]; }
        if (digits.length >= 6) vid = digits;
    }
    if (!vid.length) { [TKUtils alertWithTitle:L(@"Open a video link") message:L(@"That does not look like a TikTok video link.")]; return; }
    UIActivityIndicatorView *sp = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    [sp startAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:sp];
    [TKTikTok resolveId:vid author:nil completion:^(TKVideo *resolved, NSError *error) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addCreator)];
        if (!resolved) { [TKUtils alertWithTitle:L(@"Open a video link") message:error.localizedDescription ?: L(@"This video could not be loaded.")]; return; }
        TKFeedViewController *feed = [[TKFeedViewController alloc] initWithVideos:@[ resolved ] startIndex:0 title:resolved.author.length ? [@"@" stringByAppendingString:resolved.author] : L(@"Video")];
        feed.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:feed animated:YES completion:nil];
    }];
}

@end
