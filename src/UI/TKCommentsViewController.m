#import "TKCommentsViewController.h"
#import "TKTikTok.h"
#import "TKModels.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"

@interface TKCommentsViewController ()
@property (nonatomic, strong) TKVideo *video;
@property (nonatomic, strong) NSArray *comments;
@property (nonatomic) BOOL loading;
@property (nonatomic, copy) NSString *status;
@end

// A comment shows at most this many lines (some are walls of emoji that would fill the whole sheet)
static const NSInteger TKCommentMaxLines = 8;

// Rows are measured with a label set up exactly like the cell's, so the height matches what gets drawn
// (emoji lines are taller than the body font's).
static UILabel *TKCommentSizingLabel(void)
{
    static UILabel *label;
    if (!label) {
        label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.numberOfLines = TKCommentMaxLines;
        label.lineBreakMode = NSLineBreakByTruncatingTail;
    }
    return label;
}

@implementation TKCommentsViewController

- (instancetype)initWithVideo:(TKVideo *)video
{
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _video = video;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = L(@"Comments");
    [[TKTheme shared] applyToTableView:self.tableView];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
    self.loading = YES;
    self.status = L(@"Loading comments…");
    [TKTikTok commentsForVideo:self.video.videoId count:50 completion:^(NSArray *comments, NSError *error) {
        self.loading = NO;
        self.comments = comments;
        if (error) self.status = error.localizedDescription;
        else if (!comments.count) self.status = L(@"No comments to show.");
        [self.tableView reloadData];
    }];
}

- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }

- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.comments.count ? (NSInteger)self.comments.count : 1; }

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    [[TKTheme shared] styleCell:cell];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (!self.comments.count) {
        cell.textLabel.text = @"";
        cell.detailTextLabel.text = self.status;
        cell.detailTextLabel.textColor = [[TKTheme shared] secondaryTextColor];
        return cell;
    }
    TKComment *c = self.comments[(NSUInteger)ip.row];
    cell.textLabel.text = [NSString stringWithFormat:@"@%@%@", c.author, c.likes ? [NSString stringWithFormat:@"  ♥ %@", [TKUtils formatCount:c.likes]] : @""];
    cell.textLabel.font = [[TKTheme shared] tinyBoldFont];
    cell.textLabel.textColor = [[TKTheme shared] secondaryTextColor];
    cell.detailTextLabel.text = [TKUtils displayText:c.text];
    cell.detailTextLabel.numberOfLines = TKCommentMaxLines;
    cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    cell.detailTextLabel.font = [[TKTheme shared] bodyFont];
    cell.detailTextLabel.textColor = [[TKTheme shared] primaryTextColor];
    return cell;
}

- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)ip
{
    if (!self.comments.count) return 80;
    TKComment *c = self.comments[(NSUInteger)ip.row];
    UILabel *sizer = TKCommentSizingLabel();
    sizer.font = [[TKTheme shared] bodyFont];
    sizer.text = [TKUtils displayText:c.text];
    CGSize s = [sizer sizeThatFits:CGSizeMake(t.bounds.size.width - 24, CGFLOAT_MAX)];
    return MAX(52, ceilf(s.height) + 34);
}

@end
