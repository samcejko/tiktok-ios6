#import "TKSettingsViewController.h"
#import "TKLanguagesViewController.h"
#import "TKTasteViewController.h"
#import "TKTikTok.h"
#import "TKSettings.h"
#import "TKImageLoader.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"

enum { SecServer, SecFeed, SecPlayback, SecAppearance, SecNetwork, SecData, SecAbout, SecCount };

@interface TKSettingsViewController () <UIAlertViewDelegate>
@end

@implementation TKSettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = L(@"Settings");
    [[TKTheme shared] applyToTableView:self.tableView];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
}

- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }   // (back from the languages)
- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return SecCount; }

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s
{
    switch (s) {
        case SecServer: return 4;
        case SecFeed: return 2;
        case SecPlayback: return 2;
        case SecAppearance: return 1;
        case SecNetwork: return 1;
        case SecData: return 2;
        case SecAbout: return 1;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s
{
    switch (s) {
        case SecServer: return L(@"Server (your Raspberry Pi)");
        case SecFeed: return L(@"For You");
        case SecPlayback: return L(@"Playback");
        case SecAppearance: return L(@"Appearance");
        case SecNetwork: return L(@"Network");
        case SecData: return L(@"Data");
        case SecAbout: return L(@"About");
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s
{
    if (s == SecServer) return L(@"The helper on your Pi finds the videos. Enter its address, e.g. https://ytdlp.samcejko.eu. 'Stream through the server' routes the video through the Pi too - slower, but needed away from home.");
    if (s == SecAbout) return L(@"TikTak is an unofficial viewer of public TikTok content. No login, no posting. Not affiliated with TikTok or ByteDance.");
    return nil;
}

- (UISwitch *)switchOn:(BOOL)on tag:(NSInteger)tag
{
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
    sw.on = on;
    sw.tag = tag;
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    return sw;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    [[TKTheme shared] styleCell:cell];
    NSInteger s = ip.section, r = ip.row;
    if (s == SecServer) {
        if (r == 0) { cell.textLabel.text = L(@"Address"); cell.detailTextLabel.text = [TKSettings serverBaseURL].length ? [TKSettings serverBaseURL] : L(@"Not set"); cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; }
        else if (r == 1) { cell.textLabel.text = L(@"Key"); cell.detailTextLabel.text = [TKSettings serverKey].length ? @"••••••" : L(@"None"); cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; }
        else if (r == 2) { cell.textLabel.text = L(@"Test connection"); cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; }
        else { cell.textLabel.text = L(@"Stream through the server"); cell.accessoryView = [self switchOn:[TKSettings streamThroughServer] tag:10]; cell.selectionStyle = UITableViewCellSelectionStyleNone; }
    } else if (s == SecFeed) {
        if (r == 0) {
            cell.textLabel.text = L(@"Video languages");
            NSUInteger hidden = [TKSettings hiddenLanguages].count;
            cell.detailTextLabel.text = hidden ? [NSString stringWithFormat:L(@"%lu hidden"), (unsigned long)hidden] : L(@"All");
        } else {
            cell.textLabel.text = L(@"What it learned");
        }
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (s == SecPlayback) {
        if (r == 0) { cell.textLabel.text = L(@"Start muted"); cell.accessoryView = [self switchOn:[TKSettings startMuted] tag:20]; }
        else { cell.textLabel.text = L(@"Auto-advance"); cell.accessoryView = [self switchOn:[TKSettings autoAdvance] tag:21]; }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (s == SecAppearance) {
        cell.textLabel.text = L(@"Dark theme"); cell.accessoryView = [self switchOn:[TKTheme shared].isDark tag:30]; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (s == SecNetwork) {
        cell.textLabel.text = L(@"Verify certificates"); cell.accessoryView = [self switchOn:[TKSettings verifyTLS] tag:40]; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (s == SecData) {
        cell.textLabel.text = r == 0 ? L(@"Clear image cache") : L(@"Clear saved videos");
        if (r == 1) cell.textLabel.textColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:1];
    } else if (s == SecAbout) {
        cell.textLabel.text = L(@"Version"); cell.detailTextLabel.text = [TKUtils appVersion]; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return cell;
}

- (void)switchChanged:(UISwitch *)sw
{
    switch (sw.tag) {
        case 10: [TKSettings setStreamThroughServer:sw.on]; break;
        case 20: [TKSettings setStartMuted:sw.on]; break;
        case 21: [TKSettings setAutoAdvance:sw.on]; break;
        case 30: [[TKTheme shared] setDark:sw.on]; break;
        case 40: [TKSettings setVerifyTLS:sw.on]; [TKSettings save]; break;
    }
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [t deselectRowAtIndexPath:ip animated:YES];
    NSInteger s = ip.section, r = ip.row;
    if (s == SecServer && r == 0) {
        UIAlertView *a = [[UIAlertView alloc] initWithTitle:L(@"Server address") message:@"https://ytdlp.samcejko.eu" delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Save"), nil];
        a.alertViewStyle = UIAlertViewStylePlainTextInput;
        a.tag = 1;
        [a textFieldAtIndex:0].text = [TKSettings serverBaseURL];
        [a textFieldAtIndex:0].keyboardType = UIKeyboardTypeURL;
        [a textFieldAtIndex:0].autocapitalizationType = UITextAutocapitalizationTypeNone;
        [a show];
    } else if (s == SecServer && r == 1) {
        UIAlertView *a = [[UIAlertView alloc] initWithTitle:L(@"Server key") message:L(@"The key you set on the Pi (leave empty for none).") delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Save"), nil];
        a.alertViewStyle = UIAlertViewStyleSecureTextInput;
        a.tag = 2;
        [a show];
    } else if (s == SecServer && r == 2) {
        [self testConnection];
    } else if (s == SecFeed) {
        UIViewController *next = r == 0 ? [[TKLanguagesViewController alloc] init] : [[TKTasteViewController alloc] init];
        [self.navigationController pushViewController:next animated:YES];
    } else if (s == SecData && r == 0) {
        [[TKImageLoader shared] clearMemory];
        [[TKImageLoader shared] clearDiskWithCompletion:^{ [TKUtils alertWithTitle:nil message:L(@"Image cache cleared.")]; }];
    } else if (s == SecData && r == 1) {
        UIAlertView *a = [[UIAlertView alloc] initWithTitle:L(@"Clear saved videos") message:L(@"Remove every saved video?") delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Clear"), nil];
        a.tag = 3;
        [a show];
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) return;
    if (alertView.tag == 1) { [TKSettings setServerBaseURL:[alertView textFieldAtIndex:0].text]; }
    else if (alertView.tag == 2) { [TKSettings setServerKey:[alertView textFieldAtIndex:0].text]; }
    else if (alertView.tag == 3) { for (NSDictionary *d in [TKSettings savedVideos]) [TKSettings unsaveVideo:TKStr(d[@"id"])]; }
    [self.tableView reloadData];
}

- (void)testConnection
{
    UIActivityIndicatorView *sp = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    [sp startAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:sp];
    [TKTikTok checkHealth:^(BOOL ok, NSString *info, NSError *error) {
        self.navigationItem.rightBarButtonItem = nil;
        if (ok) [TKUtils alertWithTitle:L(@"Connected") message:[NSString stringWithFormat:L(@"The server is up (yt-dlp %@)."), info ?: @"?"]];
        else [TKUtils alertWithTitle:L(@"Not connected") message:error.localizedDescription ?: L(@"The server did not answer.")];
    }];
}

@end
