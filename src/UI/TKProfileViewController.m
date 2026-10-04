#import "TKProfileViewController.h"
#import "TKFeedViewController.h"
#import "TKLinkRouter.h"
#import "TKTikTok.h"
#import "TKModels.h"
#import "TKImageLoader.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"

static NSString * const TKPostCellId = @"post";
static NSString * const TKHeaderId = @"header";
static const CGFloat TKAvatarSize = 84;

#pragma mark - Grid cell

@interface TKProfilePostCell : UICollectionViewCell
@property (nonatomic, strong) TKImageView *cover;
@property (nonatomic, strong) UILabel *badge;
@end

@implementation TKProfilePostCell

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.contentView.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
        _cover = [[TKImageView alloc] initWithFrame:self.contentView.bounds];
        _cover.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _cover.contentMode = UIViewContentModeScaleAspectFill;
        _cover.clipsToBounds = YES;
        [self.contentView addSubview:_cover];
        _badge = [[UILabel alloc] initWithFrame:CGRectZero];
        _badge.font = [UIFont boldSystemFontOfSize:11];
        _badge.textColor = [UIColor whiteColor];
        _badge.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
        _badge.textAlignment = NSTextAlignmentCenter;
        _badge.layer.cornerRadius = 4;
        _badge.layer.masksToBounds = YES;
        [self.contentView addSubview:_badge];
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGSize s = [self.badge.text sizeWithFont:self.badge.font];
    self.badge.hidden = self.badge.text.length == 0;
    self.badge.frame = CGRectMake(5, self.contentView.bounds.size.height - s.height - 9, ceilf(s.width) + 10, ceilf(s.height) + 4);
}

@end

#pragma mark - Header

@interface TKProfileHeader : UICollectionReusableView
@property (nonatomic, strong) TKImageView *avatar;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *handleLabel;
@property (nonatomic, strong) UILabel *statsLabel;
@property (nonatomic, strong) UILabel *bioLabel;
+ (CGFloat)heightForProfile:(TKProfile *)profile width:(CGFloat)width;
- (void)showProfile:(TKProfile *)profile handle:(NSString *)handle;
@end

@implementation TKProfileHeader

+ (UIFont *)bioFont { return [UIFont systemFontOfSize:14]; }

+ (CGFloat)heightForProfile:(TKProfile *)profile width:(CGFloat)width
{
    CGFloat h = 16 + TKAvatarSize + 10 + 22 + 18 + 6 + 18 + 12;
    if (profile.bio.length) {
        CGSize s = [[TKUtils displayText:profile.bio] sizeWithFont:[self bioFont] constrainedToSize:CGSizeMake(width - 40, 120) lineBreakMode:NSLineBreakByWordWrapping];
        h += ceilf(s.height) + 10;
    }
    return h;
}

- (UILabel *)label:(UIFont *)font
{
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.font = font;
    l.textAlignment = NSTextAlignmentCenter;
    l.backgroundColor = [UIColor clearColor];
    [self addSubview:l];
    return l;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        _avatar = [[TKImageView alloc] initWithFrame:CGRectMake(0, 0, TKAvatarSize, TKAvatarSize)];
        _avatar.contentMode = UIViewContentModeScaleAspectFill;
        _avatar.clipsToBounds = YES;
        _avatar.layer.cornerRadius = TKAvatarSize / 2;
        _avatar.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
        [self addSubview:_avatar];
        _nameLabel = [self label:[UIFont boldSystemFontOfSize:18]];
        _handleLabel = [self label:[UIFont systemFontOfSize:14]];
        _statsLabel = [self label:[UIFont boldSystemFontOfSize:13]];
        _bioLabel = [self label:[TKProfileHeader bioFont]];
        _bioLabel.numberOfLines = 0;
    }
    return self;
}

- (void)showProfile:(TKProfile *)p handle:(NSString *)handle
{
    TKTheme *theme = [TKTheme shared];
    self.nameLabel.textColor = [theme primaryTextColor];
    self.bioLabel.textColor = [theme primaryTextColor];
    self.handleLabel.textColor = [theme secondaryTextColor];
    self.statsLabel.textColor = [theme secondaryTextColor];
    [self.avatar setImageURL:p.avatarURL placeholder:nil];
    NSString *name = p.name.length ? [TKUtils displayText:p.name] : handle;
    self.nameLabel.text = p.verified ? [name stringByAppendingString:@" ✓"] : name;
    self.handleLabel.text = [@"@" stringByAppendingString:p.handle.length ? p.handle : handle];
    NSMutableArray *stats = [NSMutableArray array];
    if (p.followers) [stats addObject:[NSString stringWithFormat:L(@"%@ followers"), [TKUtils formatCount:(NSInteger)MIN(p.followers, (long long)NSIntegerMax)]]];
    if (p.likes) [stats addObject:[NSString stringWithFormat:L(@"%@ likes"), [TKUtils formatCount:(NSInteger)MIN(p.likes, (long long)NSIntegerMax)]]];
    if (p.videoCount) [stats addObject:[NSString stringWithFormat:L(@"%@ posts"), [TKUtils formatCount:p.videoCount]]];
    self.statsLabel.text = [stats componentsJoinedByString:@"  ·  "];
    self.bioLabel.text = p.bio.length ? [TKUtils displayText:p.bio] : @"";
    [self setNeedsLayout];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, y = 16;
    self.avatar.frame = CGRectMake(floorf((w - TKAvatarSize) / 2), y, TKAvatarSize, TKAvatarSize);
    y += TKAvatarSize + 10;
    self.nameLabel.frame = CGRectMake(20, y, w - 40, 22);
    y += 22;
    self.handleLabel.frame = CGRectMake(20, y, w - 40, 18);
    y += 18 + 6;
    self.statsLabel.frame = CGRectMake(10, y, w - 20, 18);
    y += 18 + 10;
    CGSize s = [self.bioLabel.text sizeWithFont:self.bioLabel.font constrainedToSize:CGSizeMake(w - 40, 120) lineBreakMode:NSLineBreakByWordWrapping];
    self.bioLabel.frame = CGRectMake(20, y, w - 40, ceilf(s.height));
}

@end

#pragma mark - Controller

@interface TKProfileViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, copy) NSString *handle;
@property (nonatomic, strong) TKProfile *profile;
@property (nonatomic, strong) UICollectionView *grid;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *messageLabel;
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
    [super viewDidLoad];
    self.title = [@"@" stringByAppendingString:self.handle];
    self.view.backgroundColor = [[TKTheme shared] backgroundColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = 2;
    layout.minimumLineSpacing = 2;
    self.grid = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    self.grid.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.grid.backgroundColor = [[TKTheme shared] backgroundColor];
    self.grid.alwaysBounceVertical = YES;
    self.grid.dataSource = self;
    self.grid.delegate = self;
    [self.grid registerClass:[TKProfilePostCell class] forCellWithReuseIdentifier:TKPostCellId];
    [self.grid registerClass:[TKProfileHeader class] forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:TKHeaderId];
    [self.view addSubview:self.grid];

    self.messageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.messageLabel.textColor = [[TKTheme shared] secondaryTextColor];
    self.messageLabel.backgroundColor = [UIColor clearColor];
    self.messageLabel.textAlignment = NSTextAlignmentCenter;
    self.messageLabel.numberOfLines = 0;
    self.messageLabel.hidden = YES;
    [self.view addSubview:self.messageLabel];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:[[TKTheme shared] spinnerStyle]];
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];
    [self load];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    CGSize s = self.view.bounds.size;
    self.spinner.center = CGPointMake(s.width / 2, s.height / 3);
    self.messageLabel.frame = CGRectMake(30, s.height / 3 - 40, s.width - 60, 80);
    [self.grid.collectionViewLayout invalidateLayout];
}

- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)load
{
    [self.spinner startAnimating];
    self.messageLabel.hidden = YES;
    [TKTikTok profileForUser:self.handle completion:^(TKProfile *profile, NSError *error) {
        [self.spinner stopAnimating];
        if (!profile) {
            self.messageLabel.text = error.localizedDescription ?: L(@"This profile could not be loaded.");
            self.messageLabel.hidden = NO;
            return;
        }
        self.profile = profile;
        if (profile.name.length) self.title = [TKUtils displayText:profile.name];
        if (!profile.videos.count) {
            self.messageLabel.text = L(@"No public posts to show.");
            self.messageLabel.hidden = NO;
        }
        [self.grid reloadData];
    }];
}

#pragma mark - Grid

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section { return (NSInteger)self.profile.videos.count; }

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip
{
    TKProfilePostCell *cell = [cv dequeueReusableCellWithReuseIdentifier:TKPostCellId forIndexPath:ip];
    TKVideo *v = self.profile.videos[(NSUInteger)ip.item];
    [cell.cover setImageURL:v.coverURL placeholder:nil];
    cell.badge.text = v.isPhoto ? L(@"Photos") : (v.plays ? [@"▶ " stringByAppendingString:[TKUtils formatCount:v.plays]] : @"");
    [cell setNeedsLayout];
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)cv viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)ip
{
    TKProfileHeader *header = [cv dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:TKHeaderId forIndexPath:ip];
    [header showProfile:self.profile handle:self.handle];
    return header;
}

- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)layout referenceSizeForHeaderInSection:(NSInteger)section
{
    if (!self.profile) return CGSizeZero;
    return CGSizeMake(cv.bounds.size.width, [TKProfileHeader heightForProfile:self.profile width:cv.bounds.size.width]);
}

- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)ip
{
    CGFloat w = floorf((cv.bounds.size.width - 4) / 3);
    return CGSizeMake(w, floorf(w * 4 / 3));
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip
{
    TKFeedViewController *feed = [[TKFeedViewController alloc] initWithVideos:self.profile.videos startIndex:ip.item title:[@"@" stringByAppendingString:self.handle]];
    feed.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:feed animated:YES completion:nil];
}

@end
