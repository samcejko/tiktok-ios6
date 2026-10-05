#import "TKGridViewController.h"
#import "TKLinkRouter.h"
#import "TKHTTP.h"
#import "TKModels.h"
#import "TKImageLoader.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"

static NSString * const TKGridCellId = @"video";
static NSString * const TKGridHeaderId = @"header";
static NSString * const TKGridFooterId = @"footer";
static const CGFloat TKGridGap = 1.5;
static const NSTimeInterval TKGridRetryAfter = 5;   // a failed "more" is not asked again sooner

#pragma mark - Cells

@interface TKGridCell : UICollectionViewCell
@property (nonatomic, strong) TKImageView *cover;
@property (nonatomic, strong) UILabel *badge;
@end

@implementation TKGridCell

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.contentView.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
        _cover = [[TKImageView alloc] initWithFrame:self.contentView.bounds];
        _cover.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _cover.contentMode = UIViewContentModeScaleAspectFill;
        _cover.clipsToBounds = YES;
        _cover.maxPixels = 400;
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

// Holds the page's own header view (one view, moved into whichever host the grid hands out)
@interface TKGridHost : UICollectionReusableView
@property (nonatomic, strong) UIView *content;
@end

@implementation TKGridHost

- (void)setContent:(UIView *)content
{
    if (content.superview != self) {
        [_content removeFromSuperview];
        [self addSubview:content];
    }
    _content = content;
    [self setNeedsLayout];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    self.content.frame = self.bounds;
}

@end

// Under the last row: a spinner while a page loads, or a note (nothing there, an error)
@interface TKGridFooter : UICollectionReusableView
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *label;
@end

@implementation TKGridFooter

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:[[TKTheme shared] spinnerStyle]];
        _spinner.hidesWhenStopped = YES;
        [self addSubview:_spinner];
        _label = [[UILabel alloc] initWithFrame:CGRectZero];
        _label.font = [UIFont systemFontOfSize:15];
        _label.textColor = [[TKTheme shared] secondaryTextColor];
        _label.backgroundColor = [UIColor clearColor];
        _label.textAlignment = NSTextAlignmentCenter;
        _label.numberOfLines = 0;
        [self addSubview:_label];
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGSize s = self.bounds.size;
    self.spinner.center = CGPointMake(s.width / 2, s.height / 2);
    self.label.frame = CGRectMake(24, 0, s.width - 48, s.height);
}

@end

#pragma mark - Controller

@interface TKGridViewController ()
@property (nonatomic, strong) UICollectionView *grid;
@property (nonatomic, strong) NSMutableArray *videos;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL hasMore;
@property (nonatomic) BOOL loadedOnce;
@property (nonatomic, copy) NSString *message;          // under the grid: nothing there, or what went wrong
@property (nonatomic, strong) TKHTTPTask *task;
@property (nonatomic) NSUInteger generation;             // a reload voids the answers still on their way
@property (nonatomic) NSTimeInterval lastFailure;
@property (nonatomic, strong) NSMutableArray *waiters;   // the full-screen list waiting for the next page: @[ have, done ]
@end

@implementation TKGridViewController

- (instancetype)initWithNibName:(NSString *)nib bundle:(NSBundle *)bundle
{
    if ((self = [super initWithNibName:nib bundle:bundle])) {
        _videos = [NSMutableArray array];
        _waiters = [NSMutableArray array];
    }
    return self;
}

- (void)dealloc
{
    [self.task cancel];
    self.grid.delegate = nil;
    self.grid.dataSource = nil;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [[TKTheme shared] backgroundColor];
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = TKGridGap;
    layout.minimumLineSpacing = TKGridGap;
    self.grid = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    self.grid.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.grid.backgroundColor = [[TKTheme shared] backgroundColor];
    self.grid.alwaysBounceVertical = YES;
    self.grid.dataSource = self;
    self.grid.delegate = self;
    [self.grid registerClass:[TKGridCell class] forCellWithReuseIdentifier:TKGridCellId];
    [self.grid registerClass:[TKGridHost class] forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:TKGridHeaderId];
    [self.grid registerClass:[TKGridFooter class] forSupplementaryViewOfKind:UICollectionElementKindSectionFooter withReuseIdentifier:TKGridFooterId];
    [self.view addSubview:self.grid];
    [self reload];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    [self.grid.collectionViewLayout invalidateLayout];   // (the width: a rotation)
}

- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return TKIsPad() ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait; }

#pragma mark - For subclasses

- (TKHTTPTask *)fetchPageAfterFirst:(BOOL)more completion:(void (^)(NSArray *, BOOL, NSError *))completion
{
    completion(@[], NO, nil);
    return nil;
}

- (UIView *)headerView { return nil; }
- (CGFloat)headerHeightForWidth:(CGFloat)width { return 0; }
- (NSString *)emptyMessage { return L(@"Nothing to show."); }
- (NSString *)feedTitle { return self.title; }

- (void)headerChanged
{
    [self.grid.collectionViewLayout invalidateLayout];
    [self.grid reloadData];
}

#pragma mark - Loading

- (void)reload
{
    [self.task cancel];
    self.generation++;
    [self.videos removeAllObjects];
    self.hasMore = NO;
    self.loadedOnce = NO;
    self.message = nil;
    [self fetch:NO];
}

- (void)loadMore
{
    if (self.loading || !self.hasMore || !self.loadedOnce) return;
    if ([NSDate timeIntervalSinceReferenceDate] - self.lastFailure < TKGridRetryAfter) return;
    [self fetch:YES];
}

- (void)fetch:(BOOL)more
{
    self.loading = YES;
    [self.grid reloadData];
    NSUInteger generation = self.generation;
    __weak TKGridViewController *weakSelf = self;
    self.task = [self fetchPageAfterFirst:more completion:^(NSArray *videos, BOOL hasMore, NSError *error) {
        TKGridViewController *me = weakSelf;
        if (!me || generation != me.generation) return;
        me.loading = NO;
        me.task = nil;
        if (error) {
            me.lastFailure = [NSDate timeIntervalSinceReferenceDate];
            if (!me.videos.count) me.message = error.localizedDescription ?: L(@"The server did not answer.");
        } else {
            me.loadedOnce = YES;
            NSMutableSet *known = [NSMutableSet set];
            for (TKVideo *v in me.videos) if (v.videoId) [known addObject:v.videoId];
            for (TKVideo *v in videos) if (v.videoId && ![known containsObject:v.videoId]) { [me.videos addObject:v]; [known addObject:v.videoId]; }
            me.hasMore = hasMore && videos.count > 0;
            me.message = me.videos.count ? nil : [me emptyMessage];
        }
        [me.grid reloadData];
        [me answerWaiters];
    }];
}

// The full-screen list asked for what comes after the `have` videos it was given
- (void)moreAfter:(NSUInteger)have done:(void (^)(NSArray *))done
{
    if (self.videos.count > have) { done([self.videos subarrayWithRange:NSMakeRange(have, self.videos.count - have)]); return; }
    if (!self.hasMore) { done(nil); return; }
    [self.waiters addObject:@[ @(have), [done copy] ]];
    if (!self.loading) [self fetch:YES];
}

- (void)answerWaiters
{
    NSArray *waiters = [self.waiters copy];
    [self.waiters removeAllObjects];
    for (NSArray *w in waiters) {
        NSUInteger have = [w[0] unsignedIntegerValue];
        void (^done)(NSArray *) = w[1];
        done(self.videos.count > have ? [self.videos subarrayWithRange:NSMakeRange(have, self.videos.count - have)] : nil);
    }
}

#pragma mark - Grid

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section { return (NSInteger)self.videos.count; }

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip
{
    TKGridCell *cell = [cv dequeueReusableCellWithReuseIdentifier:TKGridCellId forIndexPath:ip];
    TKVideo *v = self.videos[(NSUInteger)ip.item];
    [cell.cover setImageURL:v.coverURL placeholder:nil];
    cell.badge.text = v.isPhoto ? L(@"Photos") : (v.plays ? [@"▶ " stringByAppendingString:[TKUtils formatCount:v.plays]] : @"");
    [cell setNeedsLayout];
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)cv viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)ip
{
    if ([kind isEqualToString:UICollectionElementKindSectionHeader]) {
        TKGridHost *host = [cv dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:TKGridHeaderId forIndexPath:ip];
        UIView *header = [self headerView];
        if (header) host.content = header;
        return host;
    }
    TKGridFooter *footer = [cv dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:TKGridFooterId forIndexPath:ip];
    if (self.loading) [footer.spinner startAnimating]; else [footer.spinner stopAnimating];
    footer.label.text = self.loading ? @"" : (self.message ?: @"");
    return footer;
}

- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)layout referenceSizeForHeaderInSection:(NSInteger)section
{
    if (![self headerView]) return CGSizeZero;
    return CGSizeMake(cv.bounds.size.width, [self headerHeightForWidth:cv.bounds.size.width]);
}

- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)layout referenceSizeForFooterInSection:(NSInteger)section
{
    if (self.loading) return CGSizeMake(cv.bounds.size.width, self.videos.count ? 64 : 120);
    if (self.message.length) return CGSizeMake(cv.bounds.size.width, 120);
    return CGSizeMake(cv.bounds.size.width, 24);
}

- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)ip
{
    CGFloat w = cv.bounds.size.width;
    NSInteger columns = MAX(3, (NSInteger)floorf(w / 180));
    CGFloat side = floorf((w - TKGridGap * (columns - 1)) / columns);
    return CGSizeMake(side, floorf(side * 4 / 3));
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip
{
    __weak TKGridViewController *weakSelf = self;
    [TKLinkRouter openVideos:[self.videos copy] startIndex:ip.item title:[self feedTitle] loadMore:^(NSUInteger have, void (^done)(NSArray *)) {
        TKGridViewController *me = weakSelf;
        if (me) [me moreAfter:have done:done]; else done(nil);
    }];
}

// Near the end: the next page
- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    CGFloat visible = scrollView.bounds.size.height;
    if (scrollView.contentOffset.y + visible > scrollView.contentSize.height - visible * 1.5) [self loadMore];
}

@end
