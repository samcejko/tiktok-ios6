#import "TKTopicsViewController.h"
#import "TKTaste.h"
#import "TKSettings.h"
#import "TKTheme.h"
#import "TKCommon.h"

@interface TKTopicsViewController ()
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) NSArray *chips;            // UIButton, tag = topic id
@property (nonatomic, strong) NSMutableSet *picked;      // NSNumber topic ids
@property (nonatomic, strong) UIButton *continueButton;
@property (nonatomic, strong) UIButton *skipButton;
@end

@implementation TKTopicsViewController

- (BOOL)pushed { return self.navigationController.viewControllers.count > 1; }

- (void)viewDidLoad
{
    [super viewDidLoad];
    TKTheme *theme = [TKTheme shared];
    self.title = L(@"Topics");
    self.view.backgroundColor = [theme backgroundColor];
    self.picked = [NSMutableSet set];

    self.scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scroll.alwaysBounceVertical = YES;
    [self.view addSubview:self.scroll];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.text = L(@"What do you enjoy?");
    self.titleLabel.font = [UIFont boldSystemFontOfSize:TKIsPad() ? 30 : 25];
    self.titleLabel.textColor = [theme primaryTextColor];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.backgroundColor = [UIColor clearColor];
    [self.scroll addSubview:self.titleLabel];

    self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.subtitleLabel.text = L(@"Pick a few topics so the feed hits the mark from the start. It goes on learning from how you watch.");
    self.subtitleLabel.font = [UIFont systemFontOfSize:15];
    self.subtitleLabel.textColor = [theme secondaryTextColor];
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.subtitleLabel.numberOfLines = 0;
    self.subtitleLabel.backgroundColor = [UIColor clearColor];
    [self.scroll addSubview:self.subtitleLabel];

    NSMutableArray *chips = [NSMutableArray array];
    for (NSNumber *t in [TKTaste topicIds]) {
        UIButton *chip = [UIButton buttonWithType:UIButtonTypeCustom];
        chip.tag = t.integerValue;
        chip.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        [chip setTitle:[TKTaste localizedTopicName:t.integerValue] forState:UIControlStateNormal];
        chip.layer.cornerRadius = 20;
        chip.layer.borderWidth = 1;
        [chip addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.scroll addSubview:chip];
        [chips addObject:chip];
    }
    self.chips = chips;

    self.continueButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.continueButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    self.continueButton.layer.cornerRadius = 8;
    [self.continueButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.continueButton setTitleColor:[UIColor colorWithWhite:1 alpha:0.5] forState:UIControlStateDisabled];
    [self.continueButton addTarget:self action:@selector(confirm) forControlEvents:UIControlEventTouchUpInside];
    [self.scroll addSubview:self.continueButton];

    self.skipButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.skipButton.titleLabel.font = [UIFont systemFontOfSize:15];
    [self.skipButton setTitle:L(@"Skip") forState:UIControlStateNormal];
    [self.skipButton setTitleColor:[theme secondaryTextColor] forState:UIControlStateNormal];
    [self.skipButton setTitleColor:[theme primaryTextColor] forState:UIControlStateHighlighted];
    [self.skipButton addTarget:self action:@selector(skip) forControlEvents:UIControlEventTouchUpInside];
    [self.scroll addSubview:self.skipButton];

    [self refreshChips];
}

- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return TKIsPad() ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait; }

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    CGFloat w = self.view.bounds.size.width, inner = MIN(w - 32, 620), left = floorf((w - inner) / 2);
    CGFloat y = [self pushed] ? 22 : 40;
    self.titleLabel.frame = CGRectMake(left, y, inner, 34);
    y += 44;
    CGSize s = [self.subtitleLabel.text sizeWithFont:self.subtitleLabel.font constrainedToSize:CGSizeMake(inner, 200) lineBreakMode:NSLineBreakByWordWrapping];
    self.subtitleLabel.frame = CGRectMake(left, y, inner, ceilf(s.height));
    y += ceilf(s.height) + 26;
    // the buttons flow in centred rows
    NSMutableArray *row = [NSMutableArray array];
    CGFloat rowW = 0, chipH = 40;
    for (UIButton *chip in self.chips) {
        CGFloat cw = ceilf([[chip titleForState:UIControlStateNormal] sizeWithFont:chip.titleLabel.font].width) + 36;
        chip.bounds = CGRectMake(0, 0, cw, chipH);
        CGFloat need = row.count ? rowW + 10 + cw : cw;
        if (row.count && need > inner) {
            [self placeRow:row width:rowW left:left inner:inner y:y];
            y += chipH + 10;
            [row removeAllObjects];
            need = cw;
        }
        [row addObject:chip];
        rowW = need;
    }
    if (row.count) { [self placeRow:row width:rowW left:left inner:inner y:y]; y += chipH; }
    y += 30;
    CGFloat bw = MIN(inner, 340);
    self.continueButton.frame = CGRectMake(floorf((w - bw) / 2), y, bw, 48);
    y += 48 + 8;
    self.skipButton.hidden = [self pushed];
    if (!self.skipButton.hidden) {
        self.skipButton.frame = CGRectMake(floorf((w - 200) / 2), y, 200, 40);
        y += 40;
    }
    self.scroll.contentSize = CGSizeMake(w, y + 24);
}

- (void)placeRow:(NSArray *)row width:(CGFloat)rowW left:(CGFloat)left inner:(CGFloat)inner y:(CGFloat)y
{
    CGFloat x = left + floorf((inner - rowW) / 2);
    for (UIButton *b in row) {
        b.frame = CGRectMake(x, y, b.bounds.size.width, b.bounds.size.height);
        x += b.bounds.size.width + 10;
    }
}

- (void)chipTapped:(UIButton *)chip
{
    NSNumber *t = @(chip.tag);
    if ([self.picked containsObject:t]) [self.picked removeObject:t]; else [self.picked addObject:t];
    [self refreshChips];
}

- (void)refreshChips
{
    TKTheme *theme = [TKTheme shared];
    for (UIButton *chip in self.chips) {
        BOOL on = [self.picked containsObject:@(chip.tag)];
        chip.backgroundColor = on ? [theme accentColor] : [theme cardColor];
        chip.layer.borderColor = (on ? [theme accentColor] : [theme separatorColor]).CGColor;
        [chip setTitleColor:on ? [UIColor whiteColor] : [theme primaryTextColor] forState:UIControlStateNormal];
    }
    NSUInteger n = self.picked.count;
    self.continueButton.enabled = n > 0;
    self.continueButton.backgroundColor = n ? [theme accentColor] : [theme separatorColor];
    [self.continueButton setTitle:n ? [NSString stringWithFormat:L(@"Continue (%lu)"), (unsigned long)n] : L(@"Continue")
                         forState:UIControlStateNormal];
}

- (void)confirm
{
    if (!self.picked.count) return;
    NSArray *ids = [[self.picked allObjects] sortedArrayUsingSelector:@selector(compare:)];
    [[TKTaste shared] seedTopics:ids];
    [TKSettings setTopicsChosen:YES];
    [TKSettings save];
    dispatch_block_t picked = self.onPicked;
    [self leave];
    if (picked) picked();
}

- (void)skip
{
    [TKSettings setTopicsChosen:YES];
    [TKSettings save];
    [self leave];
}

- (void)leave
{
    if ([self pushed]) [self.navigationController popViewControllerAnimated:YES];
    else [self dismissViewControllerAnimated:YES completion:nil];
}

@end
