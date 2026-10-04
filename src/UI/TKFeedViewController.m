#import "TKFeedViewController.h"
#import "TKVideoCell.h"
#import "TKFeed.h"
#import "TKTikTok.h"
#import "TKModels.h"
#import "TKSettings.h"
#import "TKDiscoverViewController.h"
#import "TKSavedViewController.h"
#import "TKSettingsViewController.h"
#import "TKCommentsViewController.h"
#import "TKExternalOpen.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"

@interface TKFeedViewController () <UIScrollViewDelegate, TKVideoCellDelegate, UIActionSheetDelegate>
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

    self.scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
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
    [self.messageButton addTarget:self action:@selector(openDiscover) forControlEvents:UIControlEventTouchUpInside];
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
    self.menuButton.layer.shadowOpacity = 0.7;
    [self.menuButton addTarget:self action:@selector(openMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.menuButton];

    if (self.fixedMode) {
        UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
        [close setImage:[[TKTheme shared] closeIconWhite] forState:UIControlStateNormal];
        close.frame = CGRectMake(8, 24, 40, 40);
        close.layer.shadowOpacity = 0.7;
        [close addTarget:self action:@selector(closeFixed) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:close];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(libraryChanged) name:TKLibraryDidChangeNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGSize s = self.view.bounds.size;
    self.scroll.frame = self.view.bounds;
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
- (BOOL)shouldAutorotate { return !self.fixedMode ? NO : NO; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
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
    [[self cellAt:self.currentIndex] setActive:NO];
}

#pragma mark - Live feed loading

- (void)loadFeed
{
    if (![TKTikTok configured]) {
        [self showMessage:L(@"Set your server address to start.\nSettings are behind the gear.") button:L(@"Open Settings") action:@selector(openSettings)];
        return;
    }
    if (![TKSettings creators].count) {
        [self showMessage:L(@"Add a creator and your feed fills up with their videos.") button:L(@"Add creators") action:@selector(openDiscover)];
        return;
    }
    [self showMessage:nil button:nil action:nil];
    [self.spinner startAnimating];
    [self.feed reloadWithCompletion:^(NSError *error) {
        [self.spinner stopAnimating];
        if (error && [self count] == 0) {
            [self showMessage:error.localizedDescription button:L(@"Try again") action:@selector(loadFeed)];
            return;
        }
        self.currentIndex = 0;
        [self.view setNeedsLayout];
        [self refreshWindow];
        [self setActiveIndex:0];
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
    if (!self.fixedMode && self.appeared && [self count] == 0) [self loadFeed];
}

#pragma mark - Cell window

- (TKVideoCell *)cellAt:(NSInteger)index { return self.cells[@(index)]; }

- (TKVideoCell *)ensureCellAt:(NSInteger)index
{
    if (index < 0 || index >= [self count]) return nil;
    TKVideoCell *cell = self.cells[@(index)];
    if (cell) return cell;
    CGSize s = self.view.bounds.size;
    cell = [[TKVideoCell alloc] initWithFrame:CGRectMake(0, s.height * index, s.width, s.height)];
    cell.delegate = self;
    [cell showVideo:[self videoAt:index]];
    [self.scroll addSubview:cell];
    self.cells[@(index)] = cell;
    return cell;
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
    [self prepareIndex:index + 1 play:NO];   // prefetch the next
}

// resolve the direct URL if needed, then play (or just prepare)
- (void)prepareIndex:(NSInteger)index play:(BOOL)play
{
    TKVideo *video = [self videoAt:index];
    TKVideoCell *cell = [self cellAt:index];
    if (!video || !cell) return;
    if (video.playURL.length) {
        if (play || index == self.currentIndex) [cell startPlaybackMuted:self.muted];
        return;
    }
    [TKTikTok resolveVideo:video completion:^(TKVideo *resolved, NSError *error) {
        if (error || !resolved.playURL.length) {
            if (index == self.currentIndex) [cell showError:error.localizedDescription ?: L(@"This video could not be loaded.")];
            return;
        }
        TKVideoCell *stillThere = [self cellAt:index];
        if (!stillThere) return;
        if (index == self.currentIndex || play) [stillThere startPlaybackMuted:self.muted];
    }];
}

#pragma mark - Scroll paging

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView { [self pageSettled]; }
- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView { [self pageSettled]; }

- (void)pageSettled
{
    CGFloat h = self.view.bounds.size.height;
    NSInteger page = h > 0 ? (NSInteger)(self.scroll.contentOffset.y / h + 0.5) : 0;
    if (page < 0) page = 0;
    if (page >= [self count]) page = [self count] - 1;
    if (page == self.currentIndex) return;

    TKVideo *leaving = [self videoAt:self.currentIndex];
    TKVideoCell *leavingCell = [self cellAt:self.currentIndex];
    BOOL completed = leavingCell.playedSeconds >= MAX(2.0, leaving.durationSeconds * 0.6);
    if (!self.fixedMode && leaving) [self.feed noteVideo:leaving completed:completed saved:[TKSettings isSaved:leaving.videoId] skipped:(!completed)];
    if (leaving) [TKSettings markVideoSeen:leaving.videoId];

    self.currentIndex = page;
    [self refreshWindow];
    [self setActiveIndex:page];

    if (!self.fixedMode && page >= [self count] - 3) {
        [self.feed ensureAhead:page by:6 completion:^(BOOL added) {
            if (added) { [self.view setNeedsLayout]; [self refreshWindow]; }
        }];
    }
}

#pragma mark - Cell delegate

- (void)videoCellDidTapSave:(TKVideoCell *)cell
{
    TKVideo *v = cell.video;
    if ([TKSettings isSaved:v.videoId]) {
        [TKSettings unsaveVideo:v.videoId];
        [cell updateSavedState:NO];
    } else {
        [TKSettings saveVideoJSON:[v toJSON]];
        [cell updateSavedState:YES];
        if (!self.fixedMode) [self.feed noteVideo:v completed:NO saved:YES skipped:NO];
    }
}

- (void)videoCellDidTapComments:(TKVideoCell *)cell
{
    TKCommentsViewController *c = [[TKCommentsViewController alloc] initWithVideo:cell.video];
    if (TKIsPad()) c.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:c animated:YES completion:nil];
}

- (void)videoCellDidTapShare:(TKVideoCell *)cell
{
    [TKExternalOpen presentShareSheetForURL:[NSURL URLWithString:[cell.video shareURL]] from:self anchor:cell];
}

- (void)videoCellDidReachEnd:(TKVideoCell *)cell
{
    if (cell != [self cellAt:self.currentIndex]) return;
    if (![TKSettings autoAdvance]) return;
    NSInteger next = self.currentIndex + 1;
    if (next < [self count]) [self.scroll setContentOffset:CGPointMake(0, self.view.bounds.size.height * next) animated:YES];
}

#pragma mark - Menu

- (void)openMenu
{
    if (self.fixedMode) { [self toggleMute]; return; }
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    [sheet addButtonWithTitle:self.muted ? L(@"Unmute") : L(@"Mute")];
    [sheet addButtonWithTitle:L(@"Creators")];
    [sheet addButtonWithTitle:L(@"Saved")];
    [sheet addButtonWithTitle:L(@"Refresh feed")];
    [sheet addButtonWithTitle:L(@"Settings")];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:L(@"Cancel")];
    [sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index
{
    switch (index) {
        case 0: [self toggleMute]; break;
        case 1: [self openDiscover]; break;
        case 2: [self openSaved]; break;
        case 3: [self loadFeed]; break;
        case 4: [self openSettings]; break;
        default: break;
    }
}

- (void)toggleMute
{
    self.muted = !self.muted;
    [[self cellAt:self.currentIndex] setMuted:self.muted];
}

- (void)openDiscover { [self present:[[TKDiscoverViewController alloc] init]]; }
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
