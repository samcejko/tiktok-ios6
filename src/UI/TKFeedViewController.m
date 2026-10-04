#import "TKFeedViewController.h"
#import "TKVideoCell.h"
#import "TKFeed.h"
#import "TKTikTok.h"
#import "TKModels.h"
#import "TKSettings.h"
#import "TKTasteViewController.h"
#import "TKLinkRouter.h"
#import "TKSavedViewController.h"
#import "TKSettingsViewController.h"
#import "TKCommentsViewController.h"
#import "TKLivePlayerViewController.h"
#import "TKLivesViewController.h"
#import "TKExternalOpen.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"

enum { TKSheetMenu = 1, TKSheetVideo = 2 };

// Auto-advance without anyone touching the screen: the first few moves still teach (mildly), later ones are
// probably an unattended iPad and teach nothing, and after a few more the feed stops moving on and just loops.
static const NSInteger TKAutoAdvancesThatTeach = 2;
static const NSInteger TKAutoAdvancesMax = 5;

// The feed pages vertically only: a sideways drag belongs to the video under it (its scrubber).
@interface TKPagerScrollView : UIScrollView
@end

@implementation TKPagerScrollView
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g
{
    if (g == self.panGestureRecognizer) {
        CGPoint v = [self.panGestureRecognizer velocityInView:self];
        if (fabs(v.x) > fabs(v.y)) return NO;
    }
    return [super gestureRecognizerShouldBegin:g];
}
@end

@interface TKFeedViewController () <UIScrollViewDelegate, TKVideoCellDelegate, UIActionSheetDelegate, UIAlertViewDelegate>
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) TKFeed *feed;              // live mode
@property (nonatomic, strong) NSArray *fixedVideos;      // fixed mode (saved / single link)
@property (nonatomic, strong) NSMutableDictionary *cells;   // index -> TKVideoCell
@property (nonatomic) NSInteger currentIndex;
@property (nonatomic) BOOL fixedMode;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIButton *messageButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIButton *menuButton;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic) BOOL muted;
@property (nonatomic) BOOL appeared;
@property (nonatomic) BOOL visible;        // on screen (not covered by a full-screen controller)
@property (nonatomic) NSInteger liveScreens;          // live streams on screen over it
@property (nonatomic, readonly) BOOL pausedForLive;   // (one or more)
@property (nonatomic, weak) TKVideoCell *menuCell;       // the page whose menu (hold) is open
@property (nonatomic, weak) UIActionSheet *videoMenu;     // that menu while it is up
@property (nonatomic) NSInteger autoAdvanceStreak;        // moves on by itself since the viewer last did anything
@property (nonatomic) BOOL autoAdvancing;                 // the page change under way is one of those
@property (nonatomic, strong) UINavigationController *panelNav;   // landscape iPad: comments beside the feed
@property (nonatomic, strong) TKCommentsViewController *panel;
@end

@implementation TKFeedViewController

- (instancetype)init
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _feed = [[TKFeed alloc] init];
        _cells = [NSMutableDictionary dictionary];
        _muted = [TKSettings startMuted];
    }
    return self;
}

- (instancetype)initWithVideos:(NSArray *)videos startIndex:(NSInteger)startIndex title:(NSString *)title
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _fixedMode = YES;
        _fixedVideos = videos ?: @[];
        _currentIndex = startIndex;
        _cells = [NSMutableDictionary dictionary];
        _muted = [TKSettings startMuted];
        self.title = title;
    }
    return self;
}

- (NSInteger)count { return self.fixedMode ? (NSInteger)self.fixedVideos.count : (NSInteger)self.feed.videos.count; }
- (TKVideo *)videoAt:(NSInteger)i { NSArray *a = self.fixedMode ? self.fixedVideos : self.feed.videos; return (i >= 0 && i < (NSInteger)a.count) ? a[(NSUInteger)i] : nil; }

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.wantsFullScreenLayout = YES;

    self.scroll = [[TKPagerScrollView alloc] initWithFrame:self.view.bounds];
    self.scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scroll.pagingEnabled = YES;
    self.scroll.showsVerticalScrollIndicator = NO;
    self.scroll.showsHorizontalScrollIndicator = NO;
    self.scroll.delegate = self;
    self.scroll.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.scroll];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    self.messageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.messageLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1];
    self.messageLabel.font = [UIFont systemFontOfSize:16];
    self.messageLabel.numberOfLines = 0;
    self.messageLabel.textAlignment = NSTextAlignmentCenter;
    self.messageLabel.backgroundColor = [UIColor clearColor];
    self.messageLabel.hidden = YES;
    [self.view addSubview:self.messageLabel];

    self.messageButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [self.messageButton setTitle:L(@"Set up") forState:UIControlStateNormal];
    [self.messageButton addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    self.messageButton.hidden = YES;
    [self.view addSubview:self.messageButton];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.backgroundColor = [UIColor clearColor];
    self.titleLabel.text = self.title ?: L(@"For You");
    self.titleLabel.layer.shadowOpacity = 0.7;
    self.titleLabel.layer.shadowRadius = 2;
    [self.view addSubview:self.titleLabel];

    self.menuButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.menuButton setImage:[[TKTheme shared] gearIconWhite] forState:UIControlStateNormal];
    self.menuButton.accessibilityLabel = self.fixedMode ? L(@"Mute") : L(@"Menu");   // (icon only: for VoiceOver)
    self.menuButton.layer.shadowOpacity = 0.7;
    [self.menuButton addTarget:self action:@selector(openMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.menuButton];

    if (self.fixedMode) {
        UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
        [close setImage:[[TKTheme shared] closeIconWhite] forState:UIControlStateNormal];
        close.accessibilityLabel = L(@"Close");
        close.frame = CGRectMake(8, 24, 40, 40);
        close.layer.shadowOpacity = 0.7;
        [close addTarget:self action:@selector(closeFixed) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:close];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(libraryChanged) name:TKLibraryDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(settingsChanged) name:TKSettingsDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(livePlaybackChanged:) name:TKLivePlaybackNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

// A landscape iPad shows the comments of the page on screen in a panel beside the feed
- (BOOL)wantsPanel { return TKIsPad() && self.view.bounds.size.width > self.view.bounds.size.height; }

- (void)ensurePanel
{
    if (self.panel) return;
    self.panel = [[TKCommentsViewController alloc] initAsPanel];
    self.panelNav = [[UINavigationController alloc] initWithRootViewController:self.panel];
    [[TKTheme shared] applyToNavigationBar:self.panelNav.navigationBar];
    [self addChildViewController:self.panelNav];
    [self.view addSubview:self.panelNav.view];
    [self.panelNav didMoveToParentViewController:self];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGRect all = self.view.bounds;
    CGRect pager = all;
    if ([self wantsPanel]) {
        pager.size.width = floorf(all.size.width * 0.58f);
        [self ensurePanel];
        self.panelNav.view.frame = CGRectMake(CGRectGetMaxX(pager), 20, all.size.width - pager.size.width, all.size.height - 20);
        self.panelNav.view.hidden = NO;
        [self.panel showVideo:[self videoAt:self.currentIndex]];
    } else {
        self.panelNav.view.hidden = YES;
    }
    self.scroll.frame = pager;
    CGSize s = pager.size;
    self.scroll.contentSize = CGSizeMake(s.width, s.height * MAX(1, [self count]));
    for (NSNumber *k in self.cells) {
        TKVideoCell *cell = self.cells[k];
        cell.frame = CGRectMake(0, s.height * k.integerValue, s.width, s.height);
    }
    self.scroll.contentOffset = CGPointMake(0, s.height * self.currentIndex);
    self.spinner.center = CGPointMake(s.width / 2, s.height / 2);
    self.messageLabel.frame = CGRectMake(30, s.height / 2 - 70, s.width - 60, 90);
    self.messageButton.frame = CGRectMake(s.width / 2 - 80, s.height / 2 + 30, 160, 40);
    self.titleLabel.frame = CGRectMake(s.width / 2 - 100, 26, 200, 20);
    self.menuButton.frame = CGRectMake(s.width - 48, 24, 40, 40);
}

- (BOOL)prefersStatusBarHidden { return YES; }
// Every orientation on the iPad (on its side the comments sit beside the video); a phone stays upright
- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations
{
    return TKIsPad() ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    self.visible = YES;
    if (self.appeared) { [self setActiveIndex:self.currentIndex]; return; }
    self.appeared = YES;
    if (self.fixedMode) {
        [self.view setNeedsLayout];
        [self refreshWindow];
        [self setActiveIndex:self.currentIndex];
    } else {
        [self loadFeed];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    self.visible = NO;
    [[self cellAt:self.currentIndex] setActive:NO];
}

- (TKVideoCell *)currentCell { return [self cellAt:self.currentIndex]; }

#pragma mark - Live feed loading

- (void)loadFeed
{
    if (self.fixedMode) return;
    if (![TKTikTok configured]) {
        [self showMessage:L(@"Set your server address to start.\nSettings are behind the gear.") button:L(@"Open Settings") action:@selector(openSettings)];
        return;
    }
    [self showMessage:nil button:nil action:nil];
    [self.spinner startAnimating];
    [self.feed reloadWithCompletion:^(NSError *error) {
        [self.spinner stopAnimating];
        if (error) {
            if ([self count] == 0) [self showMessage:error.localizedDescription button:L(@"Try again") action:@selector(loadFeed)];
            return;
        }
        // a fresh list: the pages on screen belong to the old one
        [self removeAllCells];
        self.currentIndex = 0;
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
        [self refreshWindow];
        // A video link opened while the feed was loading covers it: playing now would sound under that video.
        // viewDidAppear starts the page once the feed is on screen again.
        if (self.visible && !self.pausedForLive) [self setActiveIndex:0];
    }];
}

- (void)showMessage:(NSString *)message button:(NSString *)button action:(SEL)action
{
    self.messageLabel.text = message;
    self.messageLabel.hidden = message == nil;
    self.messageButton.hidden = button == nil;
    if (button) {
        [self.messageButton setTitle:button forState:UIControlStateNormal];
        [self.messageButton removeTarget:self action:NULL forControlEvents:UIControlEventTouchUpInside];
        [self.messageButton addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    }
}

- (void)libraryChanged
{
    if (!self.fixedMode && self.appeared && [self count] == 0 && !self.feed.loading) [self loadFeed];
}

// the server address was just set: the empty feed can start now
- (void)settingsChanged
{
    if (!self.fixedMode && self.appeared && [self count] == 0 && !self.feed.loading && [TKTikTok configured]) [self loadFeed];
}

#pragma mark - Cell window

- (TKVideoCell *)cellAt:(NSInteger)index { return self.cells[@(index)]; }

- (TKVideoCell *)ensureCellAt:(NSInteger)index
{
    if (index < 0 || index >= [self count]) return nil;
    TKVideoCell *cell = self.cells[@(index)];
    if (cell) return cell;
    CGSize s = self.scroll.bounds.size;
    cell = [[TKVideoCell alloc] initWithFrame:CGRectMake(0, s.height * index, s.width, s.height)];
    cell.delegate = self;
    [cell showVideo:[self videoAt:index]];
    [self.scroll addSubview:cell];
    self.cells[@(index)] = cell;
    return cell;
}

- (void)removeAllCells
{
    for (NSNumber *k in [self.cells allKeys]) { [self.cells[k] teardown]; [self.cells[k] removeFromSuperview]; }
    [self.cells removeAllObjects];
}

// keep cells for [current-1 .. current+1], tear down the rest
- (void)refreshWindow
{
    NSInteger lo = self.currentIndex - 1, hi = self.currentIndex + 1;
    for (NSNumber *k in [self.cells allKeys]) {
        NSInteger i = k.integerValue;
        if (i < lo || i > hi) { [self.cells[k] teardown]; [self.cells[k] removeFromSuperview]; [self.cells removeObjectForKey:k]; }
    }
    for (NSInteger i = lo; i <= hi; i++) [self ensureCellAt:i];
}

- (void)setActiveIndex:(NSInteger)index
{
    for (NSNumber *k in self.cells) [self.cells[k] setActive:(k.integerValue == index)];
    [self prepareIndex:index play:YES];
    [self prepareIndex:index + 1 play:NO];   // buffer the next one, so the swipe starts at once
    if (self.panel && !self.panelNav.view.hidden) [self.panel showVideo:[self videoAt:index]];
}

// resolve the direct URL if needed, then play (or prepare: buffer without a picture)
- (void)prepareIndex:(NSInteger)index play:(BOOL)play
{
    TKVideo *video = [self videoAt:index];
    TKVideoCell *cell = [self cellAt:index];
    if (!video || !cell) return;
    if (video.playable) {
        if (play || index == self.currentIndex) [cell startPlaybackMuted:self.muted];
        else [cell preparePlayback];
        return;
    }
    [TKTikTok resolveVideo:video completion:^(TKVideo *resolved, NSError *error) {
        if (error || !resolved.playable) {
            if (index == self.currentIndex) [cell showError:error.localizedDescription ?: L(@"This video could not be loaded.")];
            return;
        }
        TKVideoCell *stillThere = [self cellAt:index];
        if (!stillThere) return;
        if (index == self.currentIndex || play) [stillThere startPlaybackMuted:self.muted];
        else [stillThere preparePlayback];
    }];
}

#pragma mark - Scroll paging

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView { [self viewerIsHere]; }
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView { [self pageSettled]; }
- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView { [self pageSettled]; }

- (void)viewerIsHere { self.autoAdvanceStreak = 0; }

- (void)pageSettled
{
    CGFloat h = self.scroll.bounds.size.height;
    NSInteger page = h > 0 ? (NSInteger)(self.scroll.contentOffset.y / h + 0.5) : 0;
    if (page < 0) page = 0;
    if (page >= [self count]) page = [self count] - 1;
    if (page == self.currentIndex) return;

    // the lesson: how long the page we leave was really watched (an unattended feed teaches nothing)
    BOOL passive = self.autoAdvancing;
    self.autoAdvancing = NO;
    TKVideo *leaving = [self videoAt:self.currentIndex];
    TKVideoCell *leavingCell = [self cellAt:self.currentIndex];
    if (leaving && leavingCell) {
        NSTimeInterval watched = [leavingCell takeWatchedSeconds];
        if (!self.fixedMode && !(passive && self.autoAdvanceStreak > TKAutoAdvancesThatTeach))
            [self.feed noteWatched:leaving seconds:watched duration:leavingCell.duration passive:passive];
        [TKSettings markVideoSeen:leaving.videoId];
    }

    self.currentIndex = page;
    [self refreshWindow];
    [self setActiveIndex:page];

    if (!self.fixedMode && page >= [self count] - 4) {
        [self.feed ensureAhead:page by:8 completion:^(BOOL added) {
            if (!added) return;
            [self.view setNeedsLayout];
            [self.view layoutIfNeeded];
            [self refreshWindow];
            [self prepareIndex:self.currentIndex + 1 play:NO];
        }];
    }
}

- (void)advance
{
    NSInteger next = self.currentIndex + 1;
    if (next < [self count]) [self.scroll setContentOffset:CGPointMake(0, self.scroll.bounds.size.height * next) animated:YES];
}

#pragma mark - Cell delegate

- (void)saveVideoOf:(TKVideoCell *)cell
{
    TKVideo *v = cell.video;
    if (!v || [TKSettings isSaved:v.videoId]) return;
    [TKSettings saveVideoJSON:[v toJSON]];
    [cell updateSavedState:YES];
    if (!self.fixedMode) [self.feed noteSaved:v];
}

- (void)videoCellWasTouched:(TKVideoCell *)cell { [self viewerIsHere]; }

- (void)videoCellDidTapAuthor:(TKVideoCell *)cell
{
    [self viewerIsHere];
    if (cell.video.author.length) [TKLinkRouter openProfile:cell.video.author];
}

- (void)videoCellDidTapLive:(TKVideoCell *)cell
{
    [self viewerIsHere];
    [TKLinkRouter openLiveRoom:cell.video.authorLiveRoom];
}

// A live stream on screen (over a sheet, where UIKit does not tell the feed it is covered): the page waits. Counted:
// when one stream takes another's place, the new one may come before the old one has gone.
- (void)livePlaybackChanged:(NSNotification *)note
{
    self.liveScreens = MAX(0, self.liveScreens + ([note.userInfo[@"playing"] boolValue] ? 1 : -1));
    if (self.pausedForLive) [[self cellAt:self.currentIndex] setActive:NO];
    else if (self.visible) [self setActiveIndex:self.currentIndex];
}

- (BOOL)pausedForLive { return self.liveScreens > 0; }

- (void)videoCellDidTapSave:(TKVideoCell *)cell
{
    [self viewerIsHere];
    TKVideo *v = cell.video;
    if ([TKSettings isSaved:v.videoId]) {
        [TKSettings unsaveVideo:v.videoId];
        [cell updateSavedState:NO];
    } else {
        [self saveVideoOf:cell];
    }
}

// double tap only ever saves (like a like: a second double tap does not undo it)
- (void)videoCellDidDoubleTap:(TKVideoCell *)cell { [self viewerIsHere]; [self saveVideoOf:cell]; }

- (void)videoCellDidTapComments:(TKVideoCell *)cell
{
    [self viewerIsHere];
    if (!self.fixedMode) [self.feed noteEngaged:cell.video weight:0.4];
    // in a navigation controller like the other sheets: its bar carries the title and the Done button
    // (presented bare, the sheet had no way to close)
    if (self.panel && !self.panelNav.view.hidden) return;   // (landscape: they are already beside the video)
    [self present:[[TKCommentsViewController alloc] initWithVideo:cell.video]];
}

- (void)videoCellDidTapShare:(TKVideoCell *)cell
{
    [self viewerIsHere];
    if (!self.fixedMode) [self.feed noteEngaged:cell.video weight:0.5];
    [TKExternalOpen presentShareSheetForURL:[NSURL URLWithString:[cell.video shareURL]] from:self anchor:cell];
}

- (void)videoCellDidReachEnd:(TKVideoCell *)cell
{
    if (cell != [self cellAt:self.currentIndex]) return;
    if (![TKSettings autoAdvance]) return;
    if (self.videoMenu.visible) return;                        // its menu is open: stay (it loops)
    if (self.autoAdvanceStreak >= TKAutoAdvancesMax) {         // nobody seems to be watching: loop instead
        if (self.autoAdvanceStreak == TKAutoAdvancesMax) { [cell showToast:L(@"Auto-advance paused")]; self.autoAdvanceStreak++; }   // (said once)
        return;
    }
    self.autoAdvanceStreak++;
    self.autoAdvancing = YES;
    [self advance];
}

// hold = the video's menu
- (void)videoCell:(TKVideoCell *)cell didLongPressAt:(CGPoint)point
{
    [self viewerIsHere];
    if (cell != [self cellAt:self.currentIndex] || !cell.video || self.videoMenu.visible) return;
    self.menuCell = cell;
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    sheet.tag = TKSheetVideo;
    self.videoMenu = sheet;
    [sheet addButtonWithTitle:cell.fastPlayback ? L(@"Play at normal speed") : L(@"Play at 2× speed")];
    [sheet addButtonWithTitle:L(@"Not interested")];
    [sheet addButtonWithTitle:L(@"Copy link")];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:L(@"Cancel")];
    if (TKIsPad()) [sheet showFromRect:CGRectMake(point.x - 1, point.y - 1, 2, 2) inView:cell animated:YES];
    else [sheet showInView:self.view];
}

- (void)videoMenuChose:(NSInteger)index
{
    TKVideoCell *cell = self.menuCell;
    TKVideo *v = cell.video;
    if (!cell || !v) return;
    if (index == 0) {
        BOOL fast = !cell.fastPlayback;
        if ([cell setFastPlayback:fast]) [cell showToast:fast ? L(@"2× speed") : L(@"Normal speed")];
        else [cell showToast:L(@"This video cannot play faster.")];
    } else if (index == 1) {
        if (!self.fixedMode) [self.feed noteNotInterested:v];
        [TKSettings markVideoSeen:v.videoId];
        [cell showToast:L(@"Got it, fewer like this")];
        [self performSelector:@selector(advance) withObject:nil afterDelay:0.6];
    } else if (index == 2) {
        [UIPasteboard generalPasteboard].string = [v shareURL];
        [cell showToast:L(@"Link copied")];
        if (!self.fixedMode) [self.feed noteEngaged:v weight:0.5];
    }
}

#pragma mark - Menu

- (void)openMenu
{
    if (self.fixedMode) { [self toggleMute]; return; }
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    sheet.tag = TKSheetMenu;
    [sheet addButtonWithTitle:self.muted ? L(@"Unmute") : L(@"Mute")];
    [sheet addButtonWithTitle:L(@"Saved")];
    [sheet addButtonWithTitle:L(@"Live now")];
    [sheet addButtonWithTitle:L(@"What it learned")];
    [sheet addButtonWithTitle:L(@"Open a link")];
    [sheet addButtonWithTitle:L(@"Refresh feed")];
    [sheet addButtonWithTitle:L(@"Settings")];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:L(@"Cancel")];
    [sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index
{
    if (index < 0 || index == sheet.cancelButtonIndex) return;
    if (sheet.tag == TKSheetVideo) { [self videoMenuChose:index]; return; }
    switch (index) {
        case 0: [self toggleMute]; break;
        case 1: [self openSaved]; break;
        case 2: [self present:[[TKLivesViewController alloc] init]]; break;
        case 3: [self present:[[TKTasteViewController alloc] init]]; break;
        case 4: [self askForLink]; break;
        case 5: [self loadFeed]; break;
        case 6: [self openSettings]; break;
        default: break;
    }
}

- (void)askForLink
{
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:L(@"Open a link") message:L(@"Paste a TikTok link: a video, a profile or a live stream.")
                                               delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Open"), nil];
    a.alertViewStyle = UIAlertViewStylePlainTextInput;
    [a textFieldAtIndex:0].text = [UIPasteboard generalPasteboard].string ?: @"";
    [a show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) return;
    NSString *link = [alertView textFieldAtIndex:0].text;
    if (![TKLinkRouter openLink:link]) [TKUtils alertWithTitle:L(@"Open a link") message:L(@"That does not look like a TikTok link.")];
}

- (void)toggleMute
{
    self.muted = !self.muted;
    [[self cellAt:self.currentIndex] setMuted:self.muted];
}

- (void)openSaved { [self present:[[TKSavedViewController alloc] init]]; }
- (void)openSettings { [self present:[[TKSettingsViewController alloc] initWithStyle:UITableViewStyleGrouped]]; }

- (void)present:(UIViewController *)vc
{
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [[TKTheme shared] applyToNavigationBar:nav.navigationBar];
    if (TKIsPad()) nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)closeFixed { [self dismissViewControllerAnimated:YES completion:nil]; }

@end
