#import "TKHashtagViewController.h"
#import "TKTikTok.h"
#import "TKModels.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"

static const CGFloat TKTagTileSize = 84;

@interface TKHashtagHeaderView : UIView
@property (nonatomic, strong) UIView *tile;
@property (nonatomic, strong) UILabel *hashLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *countsLabel;
@property (nonatomic, strong) UILabel *descLabel;
@property (nonatomic, strong) UIView *rule;
- (void)showHashtag:(TKHashtag *)tag;
- (CGFloat)layoutForWidth:(CGFloat)width apply:(BOOL)apply;
@end

@implementation TKHashtagHeaderView

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        TKTheme *theme = [TKTheme shared];
        self.backgroundColor = [theme backgroundColor];
        _tile = [[UIView alloc] initWithFrame:CGRectMake(0, 0, TKTagTileSize, TKTagTileSize)];
        _tile.backgroundColor = [theme cardColor];
        _tile.layer.cornerRadius = 14;
        _tile.layer.borderWidth = 1;
        _tile.layer.borderColor = [theme separatorColor].CGColor;
        [self addSubview:_tile];
        _hashLabel = [[UILabel alloc] initWithFrame:_tile.bounds];
        _hashLabel.text = @"#";
        _hashLabel.font = [UIFont boldSystemFontOfSize:50];
        _hashLabel.textColor = [theme accentColor];
        _hashLabel.textAlignment = NSTextAlignmentCenter;
        _hashLabel.backgroundColor = [UIColor clearColor];
        [_tile addSubview:_hashLabel];
        _nameLabel = [self label:[UIFont boldSystemFontOfSize:20] color:[theme primaryTextColor]];
        _countsLabel = [self label:[UIFont systemFontOfSize:14] color:[theme secondaryTextColor]];
        _descLabel = [self label:[UIFont systemFontOfSize:14] color:[theme primaryTextColor]];
        _descLabel.numberOfLines = 4;
        _rule = [[UIView alloc] initWithFrame:CGRectZero];
        _rule.backgroundColor = [theme separatorColor];
        [self addSubview:_rule];
    }
    return self;
}

- (UILabel *)label:(UIFont *)font color:(UIColor *)color
{
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.font = font;
    l.textColor = color;
    l.backgroundColor = [UIColor clearColor];
    [self addSubview:l];
    return l;
}

- (void)showHashtag:(TKHashtag *)tag
{
    self.nameLabel.text = [@"#" stringByAppendingString:tag.name ?: @""];
    NSMutableArray *parts = [NSMutableArray array];
    if (tag.videoCount) [parts addObject:[NSString stringWithFormat:L(@"%@ videos"), [TKUtils formatBigCount:tag.videoCount]]];
    if (tag.viewCount) [parts addObject:[NSString stringWithFormat:L(@"%@ views"), [TKUtils formatBigCount:tag.viewCount]]];
    self.countsLabel.text = [parts componentsJoinedByString:@"  ·  "];
    self.descLabel.text = tag.desc.length ? [TKUtils displayText:tag.desc] : @"";
    [self setNeedsLayout];
}

- (CGFloat)layoutForWidth:(CGFloat)w apply:(BOOL)apply
{
    CGFloat x = 16 + TKTagTileSize + 14, textW = w - x - 16, y = 18;
    if (apply) {
        self.tile.frame = CGRectMake(16, y, TKTagTileSize, TKTagTileSize);
        self.nameLabel.frame = CGRectMake(x, y + 14, textW, 26);
        self.countsLabel.frame = CGRectMake(x, y + 44, textW, 20);
    }
    y += TKTagTileSize + 14;
    if (self.descLabel.text.length) {
        CGSize s = [self.descLabel.text sizeWithFont:self.descLabel.font constrainedToSize:CGSizeMake(w - 32, 4 * 18) lineBreakMode:NSLineBreakByWordWrapping];
        if (apply) self.descLabel.frame = CGRectMake(16, y, w - 32, ceilf(s.height));
        y += ceilf(s.height) + 12;
    }
    if (apply) self.rule.frame = CGRectMake(0, y - 1, w, 1);
    return y;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    [self layoutForWidth:self.bounds.size.width apply:YES];
}

@end

@interface TKHashtagViewController ()
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) TKHashtag *hashtag;
@property (nonatomic, strong) TKHashtagHeaderView *header;
@property (nonatomic) long long cursor;
@end

@implementation TKHashtagViewController

- (instancetype)initWithName:(NSString *)name
{
    if ((self = [super initWithNibName:nil bundle:nil])) _name = [name copy] ?: @"";
    return self;
}

- (void)viewDidLoad
{
    self.title = [@"#" stringByAppendingString:self.name];
    [super viewDidLoad];
}

- (TKHTTPTask *)fetchPageAfterFirst:(BOOL)more completion:(void (^)(NSArray *, BOOL, NSError *))completion
{
    return [TKTikTok hashtag:self.name cursor:more ? self.cursor : 0 completion:^(TKVideoPage *page, NSError *error) {
        if (!page) { completion(nil, NO, error); return; }
        if (!more) {
            self.hashtag = page.hashtag;
            if (page.hashtag) [self.header showHashtag:page.hashtag];
        }
        self.cursor = page.cursor;
        completion(page.videos, page.hasMore, nil);
    }];
}

- (UIView *)headerView
{
    if (!self.hashtag) return nil;
    if (!self.header) {
        self.header = [[TKHashtagHeaderView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 140)];
        [self.header showHashtag:self.hashtag];
    }
    return self.header;
}

- (CGFloat)headerHeightForWidth:(CGFloat)width { return [(TKHashtagHeaderView *)[self headerView] layoutForWidth:width apply:NO]; }
- (NSString *)emptyMessage { return self.hashtag ? L(@"No videos to show.") : L(@"This hashtag was not found."); }
- (NSString *)feedTitle { return [@"#" stringByAppendingString:self.name]; }

@end
