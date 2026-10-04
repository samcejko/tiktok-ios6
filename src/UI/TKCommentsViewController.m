#import "TKCommentsViewController.h"
#import "TKTikTok.h"
#import "TKHTTP.h"
#import "TKModels.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"

// A comment shows at most this many lines (some are walls of emoji that would fill the whole sheet)
static const NSInteger TKCommentMaxLines = 8;
static const CGFloat TKReplyIndent = 30;

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

@interface TKCommentsViewController ()
@property (nonatomic, strong) TKVideo *video;
@property (nonatomic) BOOL panel;
@property (nonatomic, strong) NSArray *comments;               // top level
@property (nonatomic, strong) NSMutableDictionary *replies;    // comment id -> NSArray of replies
@property (nonatomic, strong) NSMutableSet *loadingReplies;    // comment ids
@property (nonatomic, strong) NSArray *rows;                   // TKComment, or @{ "more": TKComment }
@property (nonatomic) BOOL loading;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, strong) TKHTTPTask *task;
@end

@implementation TKCommentsViewController

- (instancetype)initWithVideo:(TKVideo *)video
{
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _video = video;
        _replies = [NSMutableDictionary dictionary];
        _loadingReplies = [NSMutableSet set];
    }
    return self;
}

- (instancetype)initAsPanel
{
    if ((self = [self initWithVideo:nil])) _panel = YES;
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = L(@"Comments");
    [[TKTheme shared] applyToTableView:self.tableView];
    if (!self.panel)
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
    [self load];
}

- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }

- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }

- (void)showVideo:(TKVideo *)video
{
    if (video == self.video || [video.videoId isEqualToString:self.video.videoId]) return;
    self.video = video;
    [self.replies removeAllObjects];
    [self.loadingReplies removeAllObjects];
    if (self.isViewLoaded) [self load];
}

- (void)load
{
    [self.task cancel];
    self.comments = nil;
    self.loading = YES;
    self.status = self.video ? L(@"Loading comments…") : @"";
    [self rebuildRows];
    if (!self.video.videoId.length) return;
    TKVideo *forVideo = self.video;
    self.task = [TKTikTok commentsForVideo:self.video.videoId count:50 completion:^(NSArray *comments, NSError *error) {
        if (forVideo != self.video) return;      // (switched to another video meanwhile)
        self.loading = NO;
        self.comments = comments;
        if (error) self.status = error.localizedDescription;
        else if (!comments.count) self.status = L(@"No comments to show.");
        [self rebuildRows];
    }];
    [self.tableView setContentOffset:CGPointZero animated:NO];
}

- (void)rebuildRows
{
    NSMutableArray *rows = [NSMutableArray array];
    for (TKComment *c in self.comments) {
        [rows addObject:c];
        if (c.replyCount <= 0 || !c.commentId.length) continue;
        NSArray *replies = self.replies[c.commentId];
        if (replies.count) [rows addObjectsFromArray:replies];
        else if (!replies) [rows addObject:@{ @"more": c }];
    }
    self.rows = rows;
    [self.tableView reloadData];
}

- (void)loadRepliesOf:(TKComment *)comment
{
    if (!comment.commentId.length || [self.loadingReplies containsObject:comment.commentId]) return;
    [self.loadingReplies addObject:comment.commentId];
    [self.tableView reloadData];
    TKVideo *forVideo = self.video;
    [TKTikTok repliesForVideo:self.video.videoId comment:comment.commentId count:20 completion:^(NSArray *replies, NSError *error) {
        if (forVideo != self.video) return;
        [self.loadingReplies removeObject:comment.commentId];
        if (replies) self.replies[comment.commentId] = replies;   // (an empty list: the row goes away)
        [self rebuildRows];
    }];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.rows.count ? (NSInteger)self.rows.count : 1; }

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    [[TKTheme shared] styleCell:cell];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (!self.rows.count) {
        cell.textLabel.text = @"";
        cell.detailTextLabel.text = self.status;
        cell.detailTextLabel.textColor = [[TKTheme shared] secondaryTextColor];
        return cell;
    }
    id row = self.rows[(NSUInteger)ip.row];
    if ([row isKindOfClass:[NSDictionary class]]) {
        TKComment *parent = row[@"more"];
        BOOL busy = [self.loadingReplies containsObject:parent.commentId];
        cell.textLabel.text = busy ? L(@"Loading replies…") : [NSString stringWithFormat:L(@"View replies (%@)"), [TKUtils formatCount:parent.replyCount]];
        cell.textLabel.font = [[TKTheme shared] tinyBoldFont];
        cell.textLabel.textColor = [[TKTheme shared] linkColor];
        cell.indentationWidth = TKReplyIndent;
        cell.indentationLevel = 1;
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
        return cell;
    }
    TKComment *c = row;
    NSMutableString *head = [NSMutableString stringWithFormat:@"@%@", c.author];
    if (c.likes) [head appendFormat:@"  ♥ %@", [TKUtils formatCount:c.likes]];
    if (c.pinned) [head appendFormat:@"  ·  %@", L(@"Pinned")];
    cell.textLabel.text = head;
    cell.textLabel.font = [[TKTheme shared] tinyBoldFont];
    cell.textLabel.textColor = [[TKTheme shared] secondaryTextColor];
    cell.detailTextLabel.text = [TKUtils displayText:c.text];
    cell.detailTextLabel.numberOfLines = TKCommentMaxLines;
    cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    cell.detailTextLabel.font = c.isReply ? [[TKTheme shared] smallFont] : [[TKTheme shared] bodyFont];
    cell.detailTextLabel.textColor = [[TKTheme shared] primaryTextColor];
    if (c.isReply) { cell.indentationWidth = TKReplyIndent; cell.indentationLevel = 1; }
    return cell;
}

- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)ip
{
    if (!self.rows.count) return 80;
    id row = self.rows[(NSUInteger)ip.row];
    if ([row isKindOfClass:[NSDictionary class]]) return 36;
    TKComment *c = row;
    UILabel *sizer = TKCommentSizingLabel();
    sizer.font = c.isReply ? [[TKTheme shared] smallFont] : [[TKTheme shared] bodyFont];
    sizer.text = [TKUtils displayText:c.text];
    CGFloat width = t.bounds.size.width - 24 - (c.isReply ? TKReplyIndent : 0);
    CGSize s = [sizer sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    return MAX(c.isReply ? 44 : 52, ceilf(s.height) + 34);
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [t deselectRowAtIndexPath:ip animated:YES];
    if (!self.rows.count) return;
    id row = self.rows[(NSUInteger)ip.row];
    if ([row isKindOfClass:[NSDictionary class]]) [self loadRepliesOf:row[@"more"]];
}

@end
