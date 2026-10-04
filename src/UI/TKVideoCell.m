#import "TKVideoCell.h"
#import "TKMediaProxy.h"
#import "TKTikTok.h"
#import "TKSettings.h"
#import "TKImageLoader.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"
#import <AVFoundation/AVFoundation.h>

static void *TKItemStatusCtx = &TKItemStatusCtx;

@interface TKVideoCell ()
@property (nonatomic, strong) TKVideo *video;
@property (nonatomic) BOOL playing;
@property (nonatomic) NSTimeInterval playedSeconds;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) AVPlayerItem *item;
@property (nonatomic, strong) id timeObserver;
@property (nonatomic, strong) TKImageView *coverView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIImageView *pauseBadge;
@property (nonatomic, strong) UILabel *authorLabel;
@property (nonatomic, strong) UILabel *descLabel;
@property (nonatomic, strong) UILabel *musicLabel;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) UIButton *saveButton;
@property (nonatomic, strong) UILabel *saveCountLabel;
@property (nonatomic, strong) UIButton *commentsButton;
@property (nonatomic, strong) UILabel *commentsCountLabel;
@property (nonatomic, strong) UIButton *shareButton;
@property (nonatomic, strong) UIView *progressBar;
@property (nonatomic) BOOL active;
@property (nonatomic) BOOL wantMuted;
@property (nonatomic) BOOL usingServerProxy;
@property (nonatomic) BOOL reachedEndOnce;
@end

@implementation TKVideoCell

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor blackColor];
        self.clipsToBounds = YES;

        _coverView = [[TKImageView alloc] initWithFrame:self.bounds];
        _coverView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _coverView.contentMode = UIViewContentModeScaleAspectFit;
        _coverView.backgroundColor = [UIColor blackColor];
        [self addSubview:_coverView];

        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        _spinner.hidesWhenStopped = YES;
        [self addSubview:_spinner];

        _pauseBadge = [[UIImageView alloc] initWithImage:[[TKTheme shared] playIcon]];
        _pauseBadge.alpha = 0.0;
        [self addSubview:_pauseBadge];

        _progressBar = [[UIView alloc] initWithFrame:CGRectZero];
        _progressBar.backgroundColor = [UIColor colorWithWhite:1 alpha:0.85];
        [self addSubview:_progressBar];

        _authorLabel = [self labelBold:YES size:16 color:[UIColor whiteColor]];
        _descLabel = [self labelBold:NO size:14 color:[UIColor whiteColor]];
        _descLabel.numberOfLines = 3;
        _musicLabel = [self labelBold:NO size:12 color:[UIColor colorWithWhite:0.9 alpha:1]];

        _errorLabel = [self labelBold:NO size:14 color:[UIColor colorWithWhite:0.9 alpha:1]];
        _errorLabel.numberOfLines = 0;
        _errorLabel.textAlignment = NSTextAlignmentCenter;
        _errorLabel.hidden = YES;

        _saveButton = [self iconButton:[[TKTheme shared] starIconFilled:NO color:[UIColor whiteColor] size:34] action:@selector(tapSave)];
        _saveCountLabel = [self labelBold:YES size:12 color:[UIColor whiteColor]];
        _saveCountLabel.textAlignment = NSTextAlignmentCenter;
        _commentsButton = [self iconButton:[[TKTheme shared] chatIconOn:YES] action:@selector(tapComments)];
        _commentsCountLabel = [self labelBold:YES size:12 color:[UIColor whiteColor]];
        _commentsCountLabel.textAlignment = NSTextAlignmentCenter;
        _shareButton = [self iconButton:[[TKTheme shared] skipIconForward:YES] action:@selector(tapShare)];

        for (UILabel *l in @[ _authorLabel, _descLabel, _musicLabel, _saveCountLabel, _commentsCountLabel ]) l.layer.shadowOpacity = 0.6, l.layer.shadowRadius = 2, l.layer.shadowOffset = CGSizeMake(0, 1);

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(togglePlay)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (UILabel *)labelBold:(BOOL)bold size:(CGFloat)size color:(UIColor *)color
{
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    l.textColor = color;
    l.backgroundColor = [UIColor clearColor];
    [self addSubview:l];
    return l;
}

- (UIButton *)iconButton:(UIImage *)image action:(SEL)action
{
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setImage:image forState:UIControlStateNormal];
    b.layer.shadowOpacity = 0.6;
    b.layer.shadowRadius = 2;
    b.layer.shadowOffset = CGSizeMake(0, 1);
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:b];
    return b;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGRect b = self.bounds;
    if (self.playerLayer) self.playerLayer.frame = b;
    self.spinner.center = CGPointMake(b.size.width / 2, b.size.height / 2);
    self.pauseBadge.bounds = CGRectMake(0, 0, 70, 70);
    self.pauseBadge.center = CGPointMake(b.size.width / 2, b.size.height / 2);
    CGFloat railX = b.size.width - 64;
    CGFloat y = b.size.height - 250;
    self.saveButton.frame = CGRectMake(railX, y, 48, 48);
    self.saveCountLabel.frame = CGRectMake(railX - 6, y + 48, 60, 16);
    self.commentsButton.frame = CGRectMake(railX, y + 74, 48, 48);
    self.commentsCountLabel.frame = CGRectMake(railX - 6, y + 122, 60, 16);
    self.shareButton.frame = CGRectMake(railX, y + 148, 48, 48);
    CGFloat textW = b.size.width - 24 - 70;
    self.musicLabel.frame = CGRectMake(14, b.size.height - 44, textW, 16);
    CGSize ds = [self.descLabel.text sizeWithFont:self.descLabel.font constrainedToSize:CGSizeMake(textW, 60) lineBreakMode:NSLineBreakByTruncatingTail];
    self.descLabel.frame = CGRectMake(14, b.size.height - 48 - ds.height - 2, textW, ds.height);
    self.authorLabel.frame = CGRectMake(14, CGRectGetMinY(self.descLabel.frame) - 24, textW, 20);
    self.errorLabel.frame = CGRectMake(30, b.size.height / 2 - 40, b.size.width - 60, 80);
}

#pragma mark - Content

- (void)showVideo:(TKVideo *)video
{
    [self teardownPlayer];
    self.video = video;
    self.reachedEndOnce = NO;
    self.usingServerProxy = [TKSettings streamThroughServer];
    self.errorLabel.hidden = YES;
    self.authorLabel.text = video.author.length ? [@"@" stringByAppendingString:video.author] : (video.authorName ?: @"");
    self.descLabel.text = [TKUtils displayText:video.desc];
    self.musicLabel.text = video.music.length ? [NSString stringWithFormat:@"♪ %@", [TKUtils displayText:video.music]] : @"";
    self.saveCountLabel.text = video.likes ? [TKUtils formatCount:video.likes] : L(@"Save");
    self.commentsCountLabel.text = video.commentCount ? [TKUtils formatCount:video.commentCount] : @"";
    [self updateSavedState:[TKSettings isSaved:video.videoId]];
    self.coverView.hidden = NO;
    [self.coverView setImageURL:video.coverURL placeholder:nil];
    self.progressBar.frame = CGRectZero;
    [self setNeedsLayout];
}

- (void)updateSavedState:(BOOL)saved
{
    UIColor *color = saved ? [[TKTheme shared] accentColor] : [UIColor whiteColor];
    [self.saveButton setImage:[[TKTheme shared] starIconFilled:saved color:color size:34] forState:UIControlStateNormal];
}

- (void)showError:(NSString *)message
{
    [self.spinner stopAnimating];
    self.errorLabel.text = message;
    self.errorLabel.hidden = NO;
}

#pragma mark - Playback

- (NSString *)buildUpstreamAndHeaders:(NSDictionary **)outHeaders
{
    if (self.usingServerProxy) {
        *outHeaders = nil;
        return [TKTikTok proxyURLForPlayURL:self.video.playURL];
    }
    *outHeaders = self.video.playHeaders;
    return self.video.playURL;
}

- (void)startPlaybackMuted:(BOOL)muted
{
    self.wantMuted = muted;
    if (!self.video.playURL.length) { [self showError:L(@"This video could not be loaded.")]; return; }
    [[TKMediaProxy shared] ensureRunning];
    NSDictionary *headers = nil;
    NSString *upstream = [self buildUpstreamAndHeaders:&headers];
    NSString *local = [[TKMediaProxy shared] proxyURLForURL:[NSURL URLWithString:upstream] upstreamHeaders:headers];
    if (!local) { [self showError:L(@"The player could not start.")]; return; }
    self.errorLabel.hidden = YES;
    [self.spinner startAnimating];

    self.item = [AVPlayerItem playerItemWithURL:[NSURL URLWithString:local]];
    [self.item addObserver:self forKeyPath:@"status" options:0 context:TKItemStatusCtx];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemDidReachEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.item];
    self.player = [AVPlayer playerWithPlayerItem:self.item];
    self.player.volume = muted ? 0.0 : 1.0;
    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    self.playerLayer.frame = self.bounds;
    self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    [self.layer insertSublayer:self.playerLayer above:self.coverView.layer];

    __weak TKVideoCell *weakSelf = self;
    self.timeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 4) queue:NULL usingBlock:^(CMTime time) {
        [weakSelf tick:CMTimeGetSeconds(time)];
    }];
    if (self.active) [self.player play], self.playing = YES;
}

- (void)tick:(NSTimeInterval)seconds
{
    if (seconds > self.playedSeconds) self.playedSeconds = seconds;
    if (self.item.status == AVPlayerItemStatusReadyToPlay) {
        self.coverView.hidden = YES;
        [self.spinner stopAnimating];
    }
    Float64 dur = CMTimeGetSeconds(self.item.duration);
    if (dur > 0 && !isnan(dur)) {
        CGFloat w = self.bounds.size.width * (CGFloat)(seconds / dur);
        self.progressBar.frame = CGRectMake(0, self.bounds.size.height - 2, w, 2);
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context != TKItemStatusCtx) { [super observeValueForKeyPath:keyPath ofObject:object change:change context:context]; return; }
    TKMain(^{
        if (self.item.status == AVPlayerItemStatusReadyToPlay) {
            self.coverView.hidden = YES;
            [self.spinner stopAnimating];
            if (self.active && !self.playing) { [self.player play]; self.playing = YES; }
        } else if (self.item.status == AVPlayerItemStatusFailed) {
            // the direct CDN URL can refuse a device on a different network than the Pi; fall back through the Pi
            if (!self.usingServerProxy && [TKTikTok proxyURLForPlayURL:self.video.playURL].length) {
                TKLog(@"play failed direct, retrying via server proxy: %@", self.item.error.localizedDescription);
                self.usingServerProxy = YES;
                [self teardownPlayer];
                [self startPlaybackMuted:self.wantMuted];
            } else {
                [self showError:L(@"This video could not be played.")];
            }
        }
    });
}

- (void)itemDidReachEnd:(NSNotification *)note
{
    if (note.object != self.item) return;
    self.reachedEndOnce = YES;
    [self.delegate videoCellDidReachEnd:self];
    [self.item seekToTime:kCMTimeZero];
    if (self.active) [self.player play];
}

- (void)setActive:(BOOL)active
{
    self.active = active;
    if (active) {
        if (self.player) { [self.player play]; self.playing = YES; }
    } else {
        [self.player pause];
        self.playing = NO;
        if (self.item) [self.item seekToTime:kCMTimeZero];
    }
}

- (void)setMuted:(BOOL)muted
{
    self.wantMuted = muted;
    self.player.volume = muted ? 0.0 : 1.0;
}

- (void)togglePlay
{
    if (!self.player) return;
    if (self.playing) {
        [self.player pause];
        self.playing = NO;
        [self flashPauseBadge:YES];
    } else {
        [self.player play];
        self.playing = YES;
        [self flashPauseBadge:NO];
    }
}

- (void)flashPauseBadge:(BOOL)paused
{
    self.pauseBadge.image = paused ? [[TKTheme shared] playIcon] : nil;
    self.pauseBadge.alpha = paused ? 0.8 : 0.0;
    if (!paused) return;
    [UIView animateWithDuration:0.25 delay:0.4 options:0 animations:^{ self.pauseBadge.alpha = 0.0; } completion:nil];
}

#pragma mark - Buttons

- (void)tapSave { [self.delegate videoCellDidTapSave:self]; }
- (void)tapComments { [self.delegate videoCellDidTapComments:self]; }
- (void)tapShare { [self.delegate videoCellDidTapShare:self]; }

#pragma mark - Teardown

- (void)teardownPlayer
{
    if (self.timeObserver) { [self.player removeTimeObserver:self.timeObserver]; self.timeObserver = nil; }
    if (self.item) {
        @try { [self.item removeObserver:self forKeyPath:@"status" context:TKItemStatusCtx]; } @catch (__unused NSException *e) {}
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.item];
    }
    [self.player pause];
    [self.playerLayer removeFromSuperlayer];
    self.playerLayer = nil;
    self.player = nil;
    self.item = nil;
    self.playing = NO;
    self.playedSeconds = 0;
    self.coverView.hidden = NO;
}

- (void)teardown
{
    [self teardownPlayer];
    [self.coverView setImageURL:nil placeholder:nil];
    self.video = nil;
}

- (void)dealloc
{
    [self teardownPlayer];
}

@end
