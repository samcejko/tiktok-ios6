#import "TKVideoCell.h"
#import "TKMediaProxy.h"
#import "TKTikTok.h"
#import "TKSettings.h"
#import "TKImageLoader.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

static void *TKItemStatusCtx = &TKItemStatusCtx;
static const CGFloat TKScrubZoneHeight = 34;

// The FourCC of a codec name ("avc1", "hvc1", ...), as a video track's format description reports it
static FourCharCode TKFourCC(const char *s)
{
    return ((FourCharCode)(unsigned char)s[0] << 24) | ((FourCharCode)(unsigned char)s[1] << 16) |
           ((FourCharCode)(unsigned char)s[2] << 8) | (FourCharCode)(unsigned char)s[3];
}

@interface TKVideoCell () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) TKVideo *video;
@property (nonatomic) BOOL playing;
@property (nonatomic) NSTimeInterval playedSeconds;
@property (nonatomic) NSTimeInterval watchedSeconds;
@property (nonatomic) NSTimeInterval lastTickTime;           // -1 = no tick yet since a jump
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;    // only while the page is meant to be seen
@property (nonatomic, strong) AVPlayerItem *item;
@property (nonatomic, strong) id timeObserver;
@property (nonatomic, strong) TKImageView *coverView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIImageView *pauseBadge;
@property (nonatomic, strong) UILabel *authorLabel;
@property (nonatomic, strong) UIButton *authorButton;        // over the name: the profile
@property (nonatomic, strong) UIButton *avatarButton;        // on top of the right-hand buttons: the profile
@property (nonatomic, strong) TKImageView *avatarImage;
@property (nonatomic, strong) UILabel *descLabel;
@property (nonatomic, strong) UILabel *musicLabel;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) UILabel *noteLabel;
@property (nonatomic, strong) UILabel *toastLabel;
@property (nonatomic, strong) UIButton *saveButton;
@property (nonatomic, strong) UILabel *saveCountLabel;
@property (nonatomic, strong) UIButton *commentsButton;
@property (nonatomic, strong) UILabel *commentsCountLabel;
@property (nonatomic, strong) UIButton *shareButton;
@property (nonatomic, strong) UIView *progressBar;
@property (nonatomic, strong) UIView *scrubZone;
@property (nonatomic, strong) UILabel *scrubLabel;
@property (nonatomic, strong) UIPanGestureRecognizer *scrubPan;
@property (nonatomic) BOOL scrubbing;
@property (nonatomic) BOOL resumeAfterScrub;
@property (nonatomic) float playbackRate;
@property (nonatomic) BOOL active;
@property (nonatomic) BOOL wantMuted;
@property (nonatomic) BOOL usingServerProxy;
@property (nonatomic) BOOL undecodableVideo;          // the picture uses a codec the device has no decoder for
@property (nonatomic) NSUInteger proxyGeneration;     // the media proxy's generation the player's URL belongs to
@end

@implementation TKVideoCell

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor blackColor];
        self.clipsToBounds = YES;
        _playbackRate = 1.0f;
        _lastTickTime = -1;

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

        _noteLabel = [self labelBold:NO size:13 color:[UIColor whiteColor]];
        _noteLabel.numberOfLines = 0;
        _noteLabel.textAlignment = NSTextAlignmentCenter;
        _noteLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
        _noteLabel.layer.cornerRadius = 6;
        _noteLabel.layer.masksToBounds = YES;
        _noteLabel.hidden = YES;

        _saveButton = [self iconButton:[[TKTheme shared] starIconFilled:NO color:[UIColor whiteColor] size:34] action:@selector(tapSave)];
        _saveCountLabel = [self labelBold:YES size:12 color:[UIColor whiteColor]];
        _saveCountLabel.textAlignment = NSTextAlignmentCenter;
        _commentsButton = [self iconButton:[[TKTheme shared] chatIconOn:YES] action:@selector(tapComments)];
        _commentsCountLabel = [self labelBold:YES size:12 color:[UIColor whiteColor]];
        _commentsCountLabel.textAlignment = NSTextAlignmentCenter;
        _shareButton = [self iconButton:[[TKTheme shared] skipIconForward:YES] action:@selector(tapShare)];
        _authorButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [_authorButton addTarget:self action:@selector(tapAuthor) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_authorButton];
        _avatarButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _avatarImage = [[TKImageView alloc] initWithFrame:CGRectMake(0, 0, 46, 46)];
        _avatarImage.userInteractionEnabled = NO;
        _avatarImage.contentMode = UIViewContentModeScaleAspectFill;
        _avatarImage.clipsToBounds = YES;
        _avatarImage.layer.cornerRadius = 23;
        _avatarImage.layer.borderColor = [UIColor whiteColor].CGColor;
        _avatarImage.layer.borderWidth = 1.5;
        _avatarImage.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1];
        [_avatarButton addSubview:_avatarImage];
        [_avatarButton addTarget:self action:@selector(tapAuthor) forControlEvents:UIControlEventTouchUpInside];
        _avatarButton.hidden = YES;
        [self addSubview:_avatarButton];
        // icon-only buttons: name them for VoiceOver (and the debug "press" command)
        _authorButton.accessibilityLabel = L(@"Profile");
        _avatarButton.accessibilityLabel = L(@"Profile");
        _saveButton.accessibilityLabel = L(@"Save");
        _commentsButton.accessibilityLabel = L(@"Comments");
        _shareButton.accessibilityLabel = L(@"Share");

        for (UILabel *l in @[ _authorLabel, _descLabel, _musicLabel, _saveCountLabel, _commentsCountLabel ]) l.layer.shadowOpacity = 0.6, l.layer.shadowRadius = 2, l.layer.shadowOffset = CGSizeMake(0, 1);

        // the strip along the bottom edge: drag sideways to seek
        _scrubZone = [[UIView alloc] initWithFrame:CGRectZero];
        _scrubZone.backgroundColor = [UIColor clearColor];
        [self addSubview:_scrubZone];
        _scrubLabel = [self labelBold:YES size:16 color:[UIColor whiteColor]];
        _scrubLabel.textAlignment = NSTextAlignmentCenter;
        _scrubLabel.layer.shadowOpacity = 0.8;
        _scrubLabel.layer.shadowRadius = 3;
        _scrubLabel.layer.shadowOffset = CGSizeMake(0, 1);
        _scrubLabel.hidden = YES;

        _toastLabel = [self labelBold:YES size:15 color:[UIColor whiteColor]];
        _toastLabel.textAlignment = NSTextAlignmentCenter;
        _toastLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
        _toastLabel.layer.cornerRadius = 8;
        _toastLabel.layer.masksToBounds = YES;
        _toastLabel.alpha = 0;

        // tap = pause/play, double tap = save, hold = menu, drag along the bottom = seek
        UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTapped:)];
        doubleTap.numberOfTapsRequired = 2;
        doubleTap.delegate = self;
        [self addGestureRecognizer:doubleTap];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(togglePlay)];
        [tap requireGestureRecognizerToFail:doubleTap];
        tap.delegate = self;
        [self addGestureRecognizer:tap];
        UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)];
        hold.minimumPressDuration = 0.45;
        hold.delegate = self;
        [self addGestureRecognizer:hold];
        _scrubPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(scrubbed:)];
        _scrubPan.delegate = self;
        [_scrubZone addGestureRecognizer:_scrubPan];
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
    CGSize nameSize = [self.authorLabel.text sizeWithFont:self.authorLabel.font];
    self.authorButton.frame = CGRectMake(8, CGRectGetMinY(self.authorLabel.frame) - 8, MIN(textW, ceilf(nameSize.width)) + 16, 36);
    self.avatarButton.frame = CGRectMake(railX + 1, y - 64, 46, 46);
    self.errorLabel.frame = CGRectMake(30, b.size.height / 2 - 40, b.size.width - 60, 80);
    self.scrubZone.frame = CGRectMake(0, b.size.height - TKScrubZoneHeight, b.size.width, TKScrubZoneHeight);
    self.scrubLabel.frame = CGRectMake(0, b.size.height - TKScrubZoneHeight - 40, b.size.width, 24);
    if (!self.noteLabel.hidden) {
        CGFloat maxW = MIN(b.size.width - 40, 520);
        CGSize ns = [self.noteLabel.text sizeWithFont:self.noteLabel.font constrainedToSize:CGSizeMake(maxW - 24, 200) lineBreakMode:NSLineBreakByWordWrapping];
        CGFloat w = ceilf(ns.width) + 24, h = ceilf(ns.height) + 14;
        self.noteLabel.frame = CGRectMake(floorf((b.size.width - w) / 2), 70, w, h);   // under the feed's title bar
    }
}

- (void)showNote:(NSString *)note
{
    self.noteLabel.text = note;
    self.noteLabel.hidden = (note.length == 0);
    [self setNeedsLayout];
}

- (void)showToast:(NSString *)message
{
    if (!message.length) return;
    self.toastLabel.text = message;
    CGSize s = [message sizeWithFont:self.toastLabel.font];
    CGFloat w = MIN(self.bounds.size.width - 40, ceilf(s.width) + 32), h = ceilf(s.height) + 16;
    self.toastLabel.frame = CGRectMake(floorf((self.bounds.size.width - w) / 2), floorf(self.bounds.size.height * 0.42 - h / 2), w, h);
    [self bringSubviewToFront:self.toastLabel];
    [self.toastLabel.layer removeAllAnimations];
    self.toastLabel.alpha = 1;
    [UIView animateWithDuration:0.35 delay:1.3 options:UIViewAnimationOptionBeginFromCurrentState animations:^{ self.toastLabel.alpha = 0; } completion:nil];
}

#pragma mark - Content

- (void)showVideo:(TKVideo *)video
{
    [self teardownPlayer];
    self.video = video;
    self.playbackRate = 1.0f;
    self.usingServerProxy = [TKSettings streamThroughServer];
    self.errorLabel.hidden = YES;
    self.authorLabel.text = video.author.length ? [@"@" stringByAppendingString:video.author] : (video.authorName ?: @"");
    self.descLabel.text = [TKUtils displayText:video.desc];
    self.musicLabel.text = video.music.length ? [NSString stringWithFormat:@"♪ %@", [TKUtils displayText:video.music]] : @"";
    self.saveCountLabel.text = video.likes ? [TKUtils formatCount:video.likes] : L(@"Save");
    self.commentsCountLabel.text = video.commentCount ? [TKUtils formatCount:video.commentCount] : @"";
    [self updateSavedState:[TKSettings isSaved:video.videoId]];
    self.avatarButton.hidden = !video.authorAvatarURL.length;
    [self.avatarImage setImageURL:video.authorAvatarURL placeholder:nil];
    self.authorButton.hidden = !video.author.length;
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

// Item and player through the media proxy. The picture (the layer) comes separately: a page prepared ahead has
// none until it is shown, so it only buffers and takes no decoder.
- (BOOL)buildPlayer
{
    [[TKMediaProxy shared] ensureRunning];
    self.proxyGeneration = [TKMediaProxy shared].generation;
    NSDictionary *headers = nil;
    NSString *upstream = [self buildUpstreamAndHeaders:&headers];
    NSString *local = upstream.length ? [[TKMediaProxy shared] proxyURLForURL:[NSURL URLWithString:upstream] upstreamHeaders:headers] : nil;
    if (!local) return NO;
    self.item = [AVPlayerItem playerItemWithURL:[NSURL URLWithString:local]];
    [self.item addObserver:self forKeyPath:@"status" options:0 context:TKItemStatusCtx];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemDidReachEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.item];
    self.player = [AVPlayer playerWithPlayerItem:self.item];
    __weak TKVideoCell *weakSelf = self;
    self.timeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 4) queue:NULL usingBlock:^(CMTime time) {
        [weakSelf tick:CMTimeGetSeconds(time)];
    }];
    return YES;
}

- (void)attachLayer
{
    if (self.playerLayer || !self.player) return;
    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    self.playerLayer.frame = self.bounds;
    self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    self.playerLayer.hidden = self.undecodableVideo;
    [self.layer insertSublayer:self.playerLayer above:self.coverView.layer];
    if (self.item.status != AVPlayerItemStatusReadyToPlay) [self.spinner startAnimating];
}

- (void)preparePlayback
{
    if (self.player || !self.video.playURL.length) return;
    [self buildPlayer];
}

- (void)startPlaybackMuted:(BOOL)muted
{
    self.wantMuted = muted;
    if (!self.video.playURL.length) { [self showError:L(@"This video could not be loaded.")]; return; }
    [[TKMediaProxy shared] ensureRunning];
    // This page already has its player (prepared ahead, or we came back to it): keep that one. Building another
    // here left the first one playing as well - the sound came twice.
    BOOL reusable = self.player && self.item.status != AVPlayerItemStatusFailed && self.proxyGeneration == [TKMediaProxy shared].generation;
    if (!reusable) {
        [self teardownPlayer];
        if (![self buildPlayer]) { [self showError:L(@"The player could not start.")]; return; }
    }
    self.errorLabel.hidden = YES;
    [self attachLayer];
    [self applyVolume];
    if (self.active && !self.playing) [self resume];
}

- (void)resume
{
    if (!self.player) return;
    self.player.rate = self.playbackRate;    // (-play would reset a 2x speed)
    self.playing = YES;
}

// AVPlayer has no volume/muted on iOS 6 (that is iOS 7+); mute by setting the item's audio mix to volume 0.
- (void)applyVolume
{
    AVPlayerItem *item = self.item;
    if (!item) return;
    NSArray *tracks = [item.asset tracksWithMediaType:AVMediaTypeAudio];
    if (!tracks.count) return;
    AVMutableAudioMix *mix = [AVMutableAudioMix audioMix];
    NSMutableArray *params = [NSMutableArray array];
    for (AVAssetTrack *track in tracks) {
        AVMutableAudioMixInputParameters *p = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:track];
        [p setVolume:(self.wantMuted ? 0.0f : 1.0f) atTime:kCMTimeZero];
        [params addObject:p];
    }
    mix.inputParameters = params;
    item.audioMix = mix;
}

- (NSTimeInterval)duration
{
    Float64 d = self.item ? CMTimeGetSeconds(self.item.duration) : 0;
    if (d > 0 && !isnan(d) && !isinf(d)) return d;
    return self.video.durationSeconds;
}

- (NSTimeInterval)currentTime
{
    Float64 t = self.player ? CMTimeGetSeconds(self.player.currentTime) : 0;
    return (t > 0 && !isnan(t)) ? t : 0;
}

- (NSTimeInterval)takeWatchedSeconds
{
    NSTimeInterval w = self.watchedSeconds;
    self.watchedSeconds = 0;
    return w;
}

- (void)tick:(NSTimeInterval)seconds
{
    if (isnan(seconds)) return;
    if (self.lastTickTime >= 0 && self.playing && !self.scrubbing) {
        double d = seconds - self.lastTickTime;
        if (d > 0 && d < 1.5) self.watchedSeconds += d;        // a loop jumps back, a seek jumps far: neither counts
    }
    self.lastTickTime = seconds;
    if (seconds > self.playedSeconds) self.playedSeconds = seconds;
    if (self.item.status == AVPlayerItemStatusReadyToPlay && self.playerLayer) {
        if (!self.undecodableVideo && self.playerLayer.readyForDisplay) self.coverView.hidden = YES;
        [self.spinner stopAnimating];
    }
    if (self.scrubbing) return;
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
        if (object != self.item) return;      // the last word of an item already torn down
        if (self.item.status == AVPlayerItemStatusReadyToPlay) {
            [self checkVideoCodec];
            [self applyVolume];
            if (self.playerLayer) {
                [self.spinner stopAnimating];
                if (!self.undecodableVideo && self.playerLayer.readyForDisplay) self.coverView.hidden = YES;
                if (self.active && !self.playing) [self resume];
            }
        } else if (self.item.status == AVPlayerItemStatusFailed) {
            // the direct CDN URL can refuse a device on a different network than the Pi; fall back through the Pi
            if (!self.usingServerProxy && [TKTikTok proxyURLForPlayURL:self.video.playURL].length) {
                TKLog(@"play failed direct, retrying via server proxy: %@", self.item.error.localizedDescription);
                BOOL shown = self.playerLayer != nil;
                self.usingServerProxy = YES;
                [self teardownPlayer];
                if (shown) [self startPlaybackMuted:self.wantMuted];
                else [self preparePlayback];
            } else {
                [self showError:L(@"This video could not be played.")];
            }
        }
    });
}

// iOS 6 has no HEVC decoder (that came with iOS 11): such a video plays its sound over a black picture.
// Spot it, keep the cover up and say why, instead of showing a black page. Every video's codec goes to the log.
- (void)checkVideoCodec
{
    if (self.undecodableVideo) return;
    NSArray *tracks = [self.item.asset tracksWithMediaType:AVMediaTypeVideo];
    AVAssetTrack *track = tracks.count ? tracks[0] : nil;
    if (!track.formatDescriptions.count) return;
    CMFormatDescriptionRef desc = (__bridge CMFormatDescriptionRef)track.formatDescriptions[0];
    FourCharCode codec = CMFormatDescriptionGetMediaSubType(desc);
    char cc[5] = { (char)(codec >> 24), (char)(codec >> 16), (char)(codec >> 8), (char)codec, 0 };
    TKLog(@"video %@: %s %.0fx%.0f", self.video.videoId, cc, track.naturalSize.width, track.naturalSize.height);
    if (codec == TKFourCC("hvc1") || codec == TKFourCC("hev1")) {
        self.undecodableVideo = YES;
        self.coverView.hidden = NO;
        self.playerLayer.hidden = YES;
        [self showNote:L(@"This video is in HEVC, which this device cannot show. You hear the sound only.")];
    }
}

- (void)itemDidReachEnd:(NSNotification *)note
{
    if (note.object != self.item) return;
    [self.delegate videoCellDidReachEnd:self];
    [self.item seekToTime:kCMTimeZero];
    self.lastTickTime = -1;
    if (self.active) [self resume];
}

- (void)setActive:(BOOL)active
{
    _active = active;
    if (active) {
        if (self.player && self.playerLayer) [self resume];
    } else {
        [self.player pause];
        self.playing = NO;
        if (self.item) [self.item seekToTime:kCMTimeZero];
        self.lastTickTime = -1;
    }
}

- (void)setMuted:(BOOL)muted
{
    self.wantMuted = muted;
    [self applyVolume];
}

- (BOOL)fastPlayback { return self.playbackRate > 1.01f; }

// (verified on the iPad 2: TikTok's MP4s report canPlayFastForward and really play at 2x)
- (BOOL)setFastPlayback:(BOOL)fast
{
    if (fast && !(self.item.status == AVPlayerItemStatusReadyToPlay && self.item.canPlayFastForward)) return NO;
    self.playbackRate = fast ? 2.0f : 1.0f;
    if (self.playing) self.player.rate = self.playbackRate;
    return YES;
}

- (float)playerRate { return self.player.rate; }

#pragma mark - Gestures

// The buttons keep their own taps
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch
{
    return ![touch.view isKindOfClass:[UIControl class]];
}

// The scrubber takes only sideways drags (the feed pages with vertical ones)
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g
{
    if (g == self.scrubPan) {
        CGPoint v = [self.scrubPan velocityInView:self];
        return self.player != nil && fabs(v.x) > fabs(v.y);
    }
    return YES;
}

- (void)noteTouched
{
    if ([self.delegate respondsToSelector:@selector(videoCellWasTouched:)]) [self.delegate videoCellWasTouched:self];
}

- (void)togglePlay
{
    [self noteTouched];
    if (!self.player) return;
    if (self.playing) {
        [self.player pause];
        self.playing = NO;
        [self flashPauseBadge:YES];
    } else {
        [self resume];
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

- (void)doubleTapped:(UITapGestureRecognizer *)g
{
    [self showSaveBurstAt:[g locationInView:self]];
    [self.delegate videoCellDidDoubleTap:self];
}

- (void)showSaveBurstAt:(CGPoint)p
{
    UIImageView *star = [[UIImageView alloc] initWithImage:[[TKTheme shared] starIconFilled:YES color:[[TKTheme shared] accentColor] size:96]];
    star.center = p;
    star.alpha = 0;
    star.transform = CGAffineTransformMakeScale(0.4, 0.4);
    star.userInteractionEnabled = NO;
    [self addSubview:star];
    [UIView animateWithDuration:0.16 animations:^{
        star.alpha = 1;
        star.transform = CGAffineTransformMakeScale(1.2, 1.2);
    } completion:^(BOOL f1) {
        [UIView animateWithDuration:0.1 animations:^{ star.transform = CGAffineTransformIdentity; } completion:^(BOOL f2) {
            [UIView animateWithDuration:0.35 delay:0.35 options:0 animations:^{
                star.alpha = 0;
                star.transform = CGAffineTransformMakeTranslation(0, -50);
            } completion:^(BOOL f3) { [star removeFromSuperview]; }];
        }];
    }];
}

- (void)longPressed:(UILongPressGestureRecognizer *)g
{
    if (g.state != UIGestureRecognizerStateBegan) return;
    [self.delegate videoCell:self didLongPressAt:[g locationInView:self]];
}

- (void)scrubbed:(UIPanGestureRecognizer *)g
{
    CGFloat f = [g locationInView:self].x / MAX((CGFloat)1, self.bounds.size.width);
    if (g.state == UIGestureRecognizerStateBegan) {
        [self beginScrub];
        [self scrubTo:f exact:NO];
    } else if (g.state == UIGestureRecognizerStateChanged) {
        [self scrubTo:f exact:NO];
    } else {
        [self scrubTo:f exact:YES];
        [self endScrub];
    }
}

- (void)beginScrub
{
    [self noteTouched];
    self.scrubbing = YES;
    self.resumeAfterScrub = self.playing;
    [self.player pause];
    self.scrubLabel.hidden = NO;
}

- (void)scrubTo:(CGFloat)fraction exact:(BOOL)exact
{
    Float64 dur = CMTimeGetSeconds(self.item.duration);
    if (!(dur > 0) || isnan(dur)) return;
    fraction = MAX(0, MIN(1, fraction));
    Float64 t = fraction * dur;
    CGRect b = self.bounds;
    self.progressBar.frame = CGRectMake(0, b.size.height - 5, b.size.width * fraction, 5);
    self.scrubLabel.text = [NSString stringWithFormat:@"%@ / %@", [TKUtils formatDuration:t], [TKUtils formatDuration:dur]];
    CMTime tolerance = exact ? kCMTimeZero : CMTimeMakeWithSeconds(0.4, 600);
    [self.player seekToTime:CMTimeMakeWithSeconds(t, 600) toleranceBefore:tolerance toleranceAfter:tolerance];
}

- (void)endScrub
{
    self.scrubbing = NO;
    self.scrubLabel.hidden = YES;
    self.lastTickTime = -1;
    if (self.resumeAfterScrub && self.active) [self resume];
}

- (void)simulateDoubleTap
{
    [self showSaveBurstAt:CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds))];
    [self.delegate videoCellDidDoubleTap:self];
}

- (void)simulateLongPress
{
    [self.delegate videoCell:self didLongPressAt:CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds))];
}

- (void)simulateScrubTo:(CGFloat)fraction
{
    if (!self.player) return;
    [self beginScrub];
    [self scrubTo:fraction exact:YES];
    [self endScrub];
}

#pragma mark - Buttons

- (void)tapAuthor
{
    [self noteTouched];
    if ([self.delegate respondsToSelector:@selector(videoCellDidTapAuthor:)]) [self.delegate videoCellDidTapAuthor:self];
}

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
    self.watchedSeconds = 0;
    self.lastTickTime = -1;
    self.scrubbing = NO;
    self.scrubLabel.hidden = YES;
    self.coverView.hidden = NO;
    [self.spinner stopAnimating];
    self.undecodableVideo = NO;
    [self showNote:nil];
}

- (void)teardown
{
    [self teardownPlayer];
    [self.coverView setImageURL:nil placeholder:nil];
    [self.avatarImage setImageURL:nil placeholder:nil];
    self.video = nil;
}

- (void)dealloc
{
    [self teardownPlayer];
}

@end
