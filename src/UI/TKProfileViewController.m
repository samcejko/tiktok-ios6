#import "TKProfileViewController.h"
#import "TKLinkRouter.h"
#import "TKExternalOpen.h"
#import "TKTikTok.h"
#import "TKModels.h"
#import "TKImageLoader.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"

static const CGFloat TKAvatarSize = 96;

#pragma mark - Header

@interface TKProfileHeaderView : UIView
@property (nonatomic, strong) TKProfile *profile;
@property (nonatomic, strong) TKImageView *avatar;
@property (nonatomic, strong) UILabel *handleLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) NSArray *valueLabels;       // following, followers, likes
@property (nonatomic, strong) NSArray *captionLabels;
@property (nonatomic, strong) NSArray *dividers;
@property (nonatomic, strong) UIButton *liveButton;
@property (nonatomic, strong) UILabel *bioLabel;
@property (nonatomic, strong) UIButton *linkButton;
@property (nonatomic, strong) UIView *rule;
- (CGFloat)layoutForWidth:(CGFloat)width apply:(BOOL)apply;
@end

@implementation TKProfileHeaderView

- (UILabel *)label:(UIFont *)font color:(UIColor *)color
{
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.font = font;
    l.textColor = color;
    l.textAlignment = NSTextAlignmentCenter;
    l.backgroundColor = [UIColor clearColor];
    [self addSubview:l];
    return l;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        TKTheme *theme = [TKTheme shared];
        self.backgroundColor = [theme backgroundColor];
        _avatar = [[TKImageView alloc] initWithFrame:CGRectMake(0, 0, TKAvatarSize, TKAvatarSize)];
        _avatar.contentMode = UIViewContentModeScaleAspectFill;
        _avatar.clipsToBounds = YES;
        _avatar.layer.cornerRadius = TKAvatarSize / 2;
        _avatar.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
        _avatar.maxPixels = 300;
        [self addSubview:_avatar];
        _handleLabel = [self label:[UIFont boldSystemFontOfSize:18] color:[theme primaryTextColor]];
        _nameLabel = [self label:[UIFont systemFontOfSize:14] color:[theme secondaryTextColor]];
        NSMutableArray *values = [NSMutableArray array], *captions = [NSMutableArray array], *dividers = [NSMutableArray array];
        for (NSString *caption in @[ L(@"Following"), L(@"Followers"), L(@"Likes") ]) {
            [values addObject:[self label:[UIFont boldSystemFontOfSize:18] color:[theme primaryTextColor]]];
            UILabel *c = [self label:[UIFont systemFontOfSize:12] color:[theme secondaryTextColor]];
            c.text = caption;
            [captions addObject:c];
        }
        for (int i = 0; i < 2; i++) {
            UIView *d = [[UIView alloc] initWithFrame:CGRectZero];
            d.backgroundColor = [theme separatorColor];
            [self addSubview:d];
            [dividers addObject:d];
        }
        _valueLabels = values;
        _captionLabels = captions;
        _dividers = dividers;
        _liveButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _liveButton.backgroundColor = [theme liveColor];
        _liveButton.layer.cornerRadius = 6;
        _liveButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        [_liveButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [_liveButton setTitleColor:[UIColor colorWithWhite:1 alpha:0.6] forState:UIControlStateHighlighted];
        [_liveButton setTitle:[@"●  " stringByAppendingString:L(@"Watch live")] forState:UIControlStateNormal];
        [self addSubview:_liveButton];
        _bioLabel = [self label:[UIFont systemFontOfSize:14] color:[theme primaryTextColor]];
        _bioLabel.numberOfLines = 6;
        _linkButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _linkButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        _linkButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [_linkButton setTitleColor:[theme linkColor] forState:UIControlStateNormal];
        [_linkButton setTitleColor:[theme secondaryTextColor] forState:UIControlStateHighlighted];
        [self addSubview:_linkButton];
        _rule = [[UIView alloc] initWithFrame:CGRectZero];
        _rule.backgroundColor = [theme separatorColor];
        [self addSubview:_rule];
    }
    return self;
}

- (void)setProfile:(TKProfile *)p
{
    _profile = p;
    [self.avatar setImageURL:p.avatarURL placeholder:nil];
    self.avatar.layer.borderColor = [[TKTheme shared] liveColor].CGColor;
    self.avatar.layer.borderWidth = p.liveRoom.length ? 3 : 0;
    NSString *handle = [@"@" stringByAppendingString:p.handle ?: @""];
    self.handleLabel.text = p.verified ? [handle stringByAppendingString:@" ✓"] : handle;
    self.nameLabel.text = p.name.length ? [TKUtils displayText:p.name] : @"";
    NSArray *counts = @[ @(p.following), @(p.followers), @(p.likes) ];
    for (NSUInteger i = 0; i < 3; i++) [self.valueLabels[i] setText:[TKUtils formatBigCount:[counts[i] longLongValue]]];
    self.liveButton.hidden = !p.liveRoom.length;
    self.bioLabel.text = p.bio.length ? [TKUtils displayText:p.bio] : @"";
    NSString *link = [p.link stringByReplacingOccurrencesOfString:@"https://" withString:@""];
    link = [link stringByReplacingOccurrencesOfString:@"http://" withString:@""];
    [self.linkButton setTitle:link.length ? [@"🔗 " stringByAppendingString:link] : nil forState:UIControlStateNormal];
    self.linkButton.hidden = !link.length;
    [self setNeedsLayout];
}

// The same arithmetic measures and places, so the grid's header is exactly as tall as what is drawn
- (CGFloat)layoutForWidth:(CGFloat)w apply:(BOOL)apply
{
    CGFloat y = 18;
    if (apply) self.avatar.frame = CGRectMake(floorf((w - TKAvatarSize) / 2), y, TKAvatarSize, TKAvatarSize);
    y += TKAvatarSize + 12;
    if (apply) self.handleLabel.frame = CGRectMake(16, y, w - 32, 22);
    y += 24;
    if (self.nameLabel.text.length) {
        if (apply) self.nameLabel.frame = CGRectMake(16, y, w - 32, 18);
        y += 20;
    }
    y += 12;
    CGFloat colW = MIN(110, floorf((w - 32) / 3)), left = floorf((w - colW * 3) / 2);
    for (NSUInteger i = 0; i < 3 && apply; i++) {
        [self.valueLabels[i] setFrame:CGRectMake(left + colW * i, y, colW, 22)];
        [self.captionLabels[i] setFrame:CGRectMake(left + colW * i, y + 22, colW, 16)];
        if (i < 2) [self.dividers[i] setFrame:CGRectMake(left + colW * (i + 1), y + 10, 1, 18)];
    }
    y += 38 + 14;
    if (!self.liveButton.hidden) {
        if (apply) self.liveButton.frame = CGRectMake(floorf((w - 200) / 2), y, 200, 36);
        y += 36 + 12;
    }
    if (self.bioLabel.text.length) {
        CGSize s = [self.bioLabel.text sizeWithFont:self.bioLabel.font constrainedToSize:CGSizeMake(MIN(w - 40, 520), 6 * 18)
                                      lineBreakMode:NSLineBreakByWordWrapping];
        if (apply) self.bioLabel.frame = CGRectMake(floorf((w - MIN(w - 40, 520)) / 2), y, MIN(w - 40, 520), ceilf(s.height));
        y += ceilf(s.height) + 8;
    }
    if (!self.linkButton.hidden) {
        if (apply) self.linkButton.frame = CGRectMake(20, y, w - 40, 24);
        y += 24 + 6;
    }
    y += 8;
    if (apply) self.rule.frame = CGRectMake(0, y - 1, w, 1);
    return y;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    [self layoutForWidth:self.bounds.size.width apply:YES];
}

@end

#pragma mark - Controller

@interface TKProfileViewController ()
@property (nonatomic, copy) NSString *handle;
@property (nonatomic, strong) TKProfile *profile;
@property (nonatomic, strong) TKProfileHeaderView *header;
@property (nonatomic) long long cursor;
@end

@implementation TKProfileViewController

- (instancetype)initWithHandle:(NSString *)handle
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _handle = [handle hasPrefix:@"@"] ? [handle substringFromIndex:1] : (handle ?: @"");
    }
    return self;
}

- (void)viewDidLoad
{
    self.title = [@"@" stringByAppendingString:self.handle];
    [super viewDidLoad];
}

- (TKHTTPTask *)fetchPageAfterFirst:(BOOL)more completion:(void (^)(NSArray *, BOOL, NSError *))completion
{
    if (more) {
        return [TKTikTok postsOf:self.profile cursor:self.cursor completion:^(TKVideoPage *page, NSError *error) {
            if (page) self.cursor = page.cursor;
            completion(page.videos, page.hasMore && page.cursor > 0, error);
        }];
    }
    return [TKTikTok profileForUser:self.handle completion:^(TKProfile *profile, NSError *error) {
        if (!profile) { completion(nil, NO, error ?: TKMakeError(TKErrorBadResponse, L(@"This profile could not be loaded."))); return; }
        self.profile = profile;
        self.cursor = profile.postsCursor;
        if (profile.name.length) self.title = [TKUtils displayText:profile.name];
        self.header.profile = profile;
        completion(profile.videos, profile.hasMorePosts && profile.secUid.length > 0, nil);
    }];
}

- (UIView *)headerView
{
    if (!self.profile) return nil;
    if (!self.header) {
        self.header = [[TKProfileHeaderView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 300)];
        [self.header.liveButton addTarget:self action:@selector(openLive) forControlEvents:UIControlEventTouchUpInside];
        [self.header.linkButton addTarget:self action:@selector(openBioLink) forControlEvents:UIControlEventTouchUpInside];
        self.header.profile = self.profile;
    }
    return self.header;
}

- (CGFloat)headerHeightForWidth:(CGFloat)width { return [(TKProfileHeaderView *)[self headerView] layoutForWidth:width apply:NO]; }

- (NSString *)emptyMessage { return self.profile.isPrivate ? L(@"This account is private.") : L(@"No public posts to show."); }
- (NSString *)feedTitle { return [@"@" stringByAppendingString:self.profile.handle.length ? self.profile.handle : self.handle]; }

- (void)openLive
{
    if (self.profile.liveRoom.length) [TKLinkRouter openLiveRoom:self.profile.liveRoom];
}

- (void)openBioLink
{
    NSString *link = self.profile.link;
    if (!link.length) return;
    if (![[link lowercaseString] hasPrefix:@"http"]) link = [@"https://" stringByAppendingString:link];
    if (![TKLinkRouter openLink:link]) [TKExternalOpen openInBrowser:[NSURL URLWithString:link]];
}

@end
