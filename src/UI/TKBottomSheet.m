#import "TKBottomSheet.h"
#import <QuartzCore/QuartzCore.h>
#import "TKTheme.h"
#import "TKCommon.h"

static const CGFloat TKSheetHeaderHeight = 46;

static UIImage *TKSheetCloseImage(UIColor *color)
{
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(20, 20), NO, 0);
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(4, 4)]; [p addLineToPoint:CGPointMake(16, 16)];
    [p moveToPoint:CGPointMake(16, 4)]; [p addLineToPoint:CGPointMake(4, 16)];
    p.lineWidth = 2.5;
    p.lineCapStyle = kCGLineCapRound;
    [color setStroke];
    [p stroke];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

@interface TKBottomSheet () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIView *dimView;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UIView *header;
@property (nonatomic, strong) UIView *grabber;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIView *rule;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) CAShapeLayer *corners;
@property (nonatomic) BOOL shown;          // up (not coming or going)
@property (nonatomic) BOOL dragging;
@property (nonatomic) BOOL closing;
@end

@implementation TKBottomSheet

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        TKTheme *theme = [TKTheme shared];
        _heightFraction = 0.68;
        self.backgroundColor = [UIColor clearColor];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        _dimView = [[UIView alloc] initWithFrame:self.bounds];
        _dimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _dimView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.2];
        _dimView.alpha = 0;
        [_dimView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(close)]];
        [self addSubview:_dimView];

        _panel = [[UIView alloc] initWithFrame:CGRectZero];
        _panel.backgroundColor = [theme cardColor];
        _corners = [CAShapeLayer layer];
        _panel.layer.mask = _corners;
        [self addSubview:_panel];

        _header = [[UIView alloc] initWithFrame:CGRectZero];
        _header.backgroundColor = [UIColor clearColor];
        [_panel addSubview:_header];
        _grabber = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 36, 4)];
        _grabber.backgroundColor = [theme separatorColor];
        _grabber.layer.cornerRadius = 2;
        [_header addSubview:_grabber];
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.font = [UIFont boldSystemFontOfSize:14];
        _titleLabel.textColor = [theme primaryTextColor];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.backgroundColor = [UIColor clearColor];
        [_header addSubview:_titleLabel];
        _closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [_closeButton setImage:TKSheetCloseImage([theme secondaryTextColor]) forState:UIControlStateNormal];
        _closeButton.accessibilityLabel = L(@"Close");
        [_closeButton addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
        [_header addSubview:_closeButton];
        _rule = [[UIView alloc] initWithFrame:CGRectZero];
        _rule.backgroundColor = [theme separatorColor];
        [_panel addSubview:_rule];

        _contentView = [[UIView alloc] initWithFrame:CGRectZero];
        _contentView.backgroundColor = [theme cardColor];
        _contentView.clipsToBounds = YES;
        [_panel addSubview:_contentView];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)];
        pan.delegate = self;
        [_header addGestureRecognizer:pan];
    }
    return self;
}

- (void)setTitle:(NSString *)title
{
    _title = [title copy];
    self.titleLabel.text = title;
}

- (CGFloat)panelHeight { return floorf(self.bounds.size.height * self.heightFraction); }
- (CGFloat)restY { return self.bounds.size.height - [self panelHeight]; }

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGSize s = self.bounds.size;
    CGFloat h = [self panelHeight];
    if (!self.dragging) self.panel.frame = CGRectMake(0, self.shown ? [self restY] : s.height, s.width, h);
    else self.panel.frame = CGRectMake(0, self.panel.frame.origin.y, s.width, h);
    self.header.frame = CGRectMake(0, 0, s.width, TKSheetHeaderHeight);
    self.grabber.center = CGPointMake(s.width / 2, 8);
    self.titleLabel.frame = CGRectMake(50, 14, s.width - 100, 22);
    self.closeButton.frame = CGRectMake(s.width - 46, 2, 44, 42);
    self.rule.frame = CGRectMake(0, TKSheetHeaderHeight - 1, s.width, 1);
    self.contentView.frame = CGRectMake(0, TKSheetHeaderHeight, s.width, h - TKSheetHeaderHeight);
    self.corners.path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, s.width, h) byRoundingCorners:UIRectCornerTopLeft | UIRectCornerTopRight
                                                    cornerRadii:CGSizeMake(10, 10)].CGPath;
}

- (void)showInView:(UIView *)host
{
    self.frame = host.bounds;
    [host addSubview:self];
    self.shown = NO;
    [self layoutIfNeeded];
    self.shown = YES;
    [UIView animateWithDuration:0.28 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.dimView.alpha = 1;
        [self layoutSubviews];
    } completion:nil];
}

- (void)close
{
    if (self.closing) return;
    self.closing = YES;
    self.shown = NO;
    self.dragging = NO;
    [UIView animateWithDuration:0.24 delay:0 options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState animations:^{
        self.dimView.alpha = 0;
        [self layoutSubviews];
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
        if (self.onClose) self.onClose();
        self.onClose = nil;
    }];
}

- (void)panned:(UIPanGestureRecognizer *)g
{
    if (self.closing) return;
    CGFloat h = [self panelHeight], rest = [self restY];
    CGFloat dy = MAX(0, [g translationInView:self].y);
    if (g.state == UIGestureRecognizerStateBegan || g.state == UIGestureRecognizerStateChanged) {
        self.dragging = YES;
        CGRect f = self.panel.frame;
        f.origin.y = rest + dy;
        self.panel.frame = f;
        self.dimView.alpha = 1 - MIN(1, dy / h);
        return;
    }
    self.dragging = NO;
    if (dy > h * 0.3 || [g velocityInView:self].y > 700) { [self close]; return; }
    [UIView animateWithDuration:0.2 animations:^{
        self.dimView.alpha = 1;
        [self layoutSubviews];
    }];
}

@end
