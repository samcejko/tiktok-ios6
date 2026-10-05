#import "TKSoundViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "TKLinkRouter.h"
#import "TKMediaProxy.h"
#import "TKTikTok.h"
#import "TKModels.h"
#import "TKImageLoader.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"

static const CGFloat TKCoverSize = 96;

@interface TKSoundHeaderView : UIView
@property (nonatomic, strong) TKImageView *cover;
@property (nonatomic, strong) UIButton *playButton;       // over the cover: hear the sound
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *authorButton;
@property (nonatomic, strong) UILabel *countsLabel;
@property (nonatomic, strong) UIView *rule;
- (void)showSound:(TKSound *)sound;
- (void)showPlaying:(BOOL)playing;
- (CGFloat)layoutForWidth:(CGFloat)width apply:(BOOL)apply;
@end

@implementation TKSoundHeaderView

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        TKTheme *theme = [TKTheme shared];
        self.backgroundColor = [theme backgroundColor];
        _cover = [[TKImageView alloc] initWithFrame:CGRectMake(0, 0, TKCoverSize, TKCoverSize)];
        _cover.contentMode = UIViewContentModeScaleAspectFill;
        _cover.clipsToBounds = YES;
        _cover.layer.cornerRadius = 8;
        _cover.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
        _cover.maxPixels = 300;
        _cover.userInteractionEnabled = NO;
        [self addSubview:_cover];
        _playButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _playButton.accessibilityLabel = L(@"Play");
        _playButton.layer.shadowOpacity = 0.7;
        _playButton.layer.shadowRadius = 3;
        _playButton.layer.shadowOffset = CGSizeMake(0, 1);
        [self addSubview:_playButton];
        [self showPlaying:NO];
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.font = [UIFont boldSystemFontOfSize:19];
        _titleLabel.textColor = [theme primaryTextColor];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.numberOfLines = 2;
        [self addSubview:_titleLabel];
        _authorButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _authorButton.titleLabel.font = [UIFont systemFontOfSize:15];
        _authorButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        [_authorButton setTitleColor:[theme secondaryTextColor] forState:UIControlStateNormal];
        [_authorButton setTitleColor:[theme linkColor] forState:UIControlStateHighlighted];
        [self addSubview:_authorButton];
        _countsLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _countsLabel.font = [UIFont systemFontOfSize:14];
        _countsLabel.textColor = [theme secondaryTextColor];
        _countsLabel.backgroundColor = [UIColor clearColor];
        [self addSubview:_countsLabel];
        _rule = [[UIView alloc] initWithFrame:CGRectZero];
        _rule.backgroundColor = [theme separatorColor];
        [self addSubview:_rule];
    }
    return self;
}

- (void)showPlaying:(BOOL)playing
{
    [self.playButton setImage:playing ? [[TKTheme shared] pauseIcon] : [[TKTheme shared] playIcon] forState:UIControlStateNormal];
    self.playButton.accessibilityLabel = playing ? L(@"Pause") : L(@"Play");
}

- (void)showSound:(TKSound *)s
{
    [self.cover setImageURL:s.coverURL placeholder:nil];
    self.titleLabel.text = s.title.length ? [TKUtils displayText:s.title] : L(@"Sound");
    NSString *author = s.authorHandle.length ? [@"@" stringByAppendingString:s.authorHandle] : (s.author ?: @"");
    [self.authorButton setTitle:[TKUtils displayText:author] forState:UIControlStateNormal];
    self.authorButton.enabled = s.authorHandle.length > 0;
    NSMutableArray *parts = [NSMutableArray array];
    if (s.videoCount) [parts addObject:[NSString stringWithFormat:L(@"%@ videos"), [TKUtils formatBigCount:s.videoCount]]];
    if (s.original) [parts addObject:L(@"Original sound")];
    if (s.durationSeconds) [parts addObject:[TKUtils formatDuration:s.durationSeconds]];
    self.countsLabel.text = [parts componentsJoinedByString:@"  ·  "];
    self.playButton.hidden = !s.playURL.length;
    [self setNeedsLayout];
}

- (CGFloat)layoutForWidth:(CGFloat)w apply:(BOOL)apply
{
    CGFloat x = 16 + TKCoverSize + 14, textW = w - x - 16, y = 18;
    if (apply) {
        self.cover.frame = CGRectMake(16, y, TKCoverSize, TKCoverSize);
        self.playButton.frame = self.cover.frame;
        CGSize t = [self.titleLabel.text ?: @"" sizeWithFont:self.titleLabel.font constrainedToSize:CGSizeMake(textW, 46) lineBreakMode:NSLineBreakByWordWrapping];
        CGFloat th = MAX(24, ceilf(t.height));
        self.titleLabel.frame = CGRectMake(x, y + 2, textW, th);
        self.authorButton.frame = CGRectMake(x, y + 4 + th, textW, 24);
        self.countsLabel.frame = CGRectMake(x, y + 30 + th, textW, 20);
    }
    y += TKCoverSize + 16;
    if (apply) self.rule.frame = CGRectMake(0, y - 1, w, 1);
    return y;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    [self layoutForWidth:self.bounds.size.width apply:YES];
}

@end

@interface TKSoundViewController ()
@property (nonatomic, copy) NSString *soundId;
@property (nonatomic, copy) NSString *givenTitle;
@property (nonatomic, strong) TKSound *sound;
@property (nonatomic, strong) TKSoundHeaderView *header;
@property (nonatomic) long long cursor;
@property (nonatomic, strong) AVPlayer *player;          // the sound itself, while it is heard
@end

@implementation TKSoundViewController

- (instancetype)initWithSoundId:(NSString *)soundId title:(NSString *)title
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _soundId = [soundId copy] ?: @"";
        _givenTitle = [title copy];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_player pause];
}

- (void)viewDidLoad
{
    self.title = self.givenTitle.length ? [TKUtils displayText:self.givenTitle] : L(@"Sound");
    [super viewDidLoad];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self stopSound];      // (a video opened from the grid has its own sound)
}

- (TKHTTPTask *)fetchPageAfterFirst:(BOOL)more completion:(void (^)(NSArray *, BOOL, NSError *))completion
{
    return [TKTikTok sound:self.soundId cursor:more ? self.cursor : 0 completion:^(TKVideoPage *page, NSError *error) {
        if (!page) { completion(nil, NO, error); return; }
        if (!more && page.sound) {
            self.sound = page.sound;
            if (page.sound.title.length) self.title = [TKUtils displayText:page.sound.title];
            [self.header showSound:page.sound];
        }
        self.cursor = page.cursor;
        completion(page.videos, page.hasMore, nil);
    }];
}

- (UIView *)headerView
{
    if (!self.sound) return nil;
    if (!self.header) {
        self.header = [[TKSoundHeaderView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 130)];
        [self.header.playButton addTarget:self action:@selector(togglePlay) forControlEvents:UIControlEventTouchUpInside];
        [self.header.authorButton addTarget:self action:@selector(openAuthor) forControlEvents:UIControlEventTouchUpInside];
        [self.header showSound:self.sound];
    }
    return self.header;
}

- (CGFloat)headerHeightForWidth:(CGFloat)width { return [(TKSoundHeaderView *)[self headerView] layoutForWidth:width apply:NO]; }
- (NSString *)emptyMessage { return self.sound ? L(@"No videos to show.") : L(@"This sound was not found."); }
- (NSString *)feedTitle { return self.title; }

- (void)openAuthor
{
    if (self.sound.authorHandle.length) [TKLinkRouter openProfile:self.sound.authorHandle];
}

#pragma mark - Hearing it

- (void)togglePlay
{
    if (self.player) { [self stopSound]; return; }
    if (!self.sound.playURL.length) return;
    TKMediaProxy *proxy = [TKMediaProxy shared];
    [proxy ensureRunning];
    NSString *local = [proxy proxyURLForURL:[NSURL URLWithString:self.sound.playURL] upstreamHeaders:self.sound.headers];
    if (!local) return;
    self.player = [AVPlayer playerWithURL:[NSURL URLWithString:local]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(soundEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.player.currentItem];
    [self.player play];
    [self.header showPlaying:YES];
}

- (void)soundEnded:(NSNotification *)note
{
    if (note.object == self.player.currentItem) [self stopSound];
}

- (void)stopSound
{
    if (!self.player) return;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [self.player pause];
    self.player = nil;
    [self.header showPlaying:NO];
}

@end
