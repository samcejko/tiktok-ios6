#import "TKFeed.h"
#import "TKTikTok.h"
#import "TKSettings.h"
#import "TKCommon.h"

@interface TKFeed ()
@property (nonatomic, strong) NSMutableDictionary *pools;   // handle -> NSMutableArray of TKVideo not yet placed
@property (nonatomic, strong) NSMutableSet *placedIds;
@property (nonatomic) BOOL loading;
@end

@implementation TKFeed {
    NSMutableArray *_videos;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _videos = [NSMutableArray array];
        _pools = [NSMutableDictionary dictionary];
        _placedIds = [NSMutableSet set];
    }
    return self;
}

- (NSArray *)videos { return _videos; }

#pragma mark - Loading creator pools

// Fetches each creator's recent videos into its pool. completion(any) once all have answered.
- (void)fillPools:(void (^)(BOOL any))completion
{
    NSArray *creators = [TKSettings creators];
    if (!creators.count) { completion(NO); return; }
    __block NSInteger pending = (NSInteger)creators.count;
    __block BOOL any = NO;
    for (NSString *handle in creators) {
        [TKTikTok videosForCreator:handle count:30 completion:^(NSArray *videos, NSError *error) {
            if (videos.count) {
                NSMutableArray *pool = [NSMutableArray array];
                for (TKVideo *v in videos) {
                    if (![self.placedIds containsObject:v.videoId]) [pool addObject:v];
                }
                if (pool.count) { self.pools[handle] = pool; any = YES; }
            } else if (error) {
                TKLog(@"feed: @%@ failed: %@", handle, error.localizedDescription);
            }
            if (--pending == 0) completion(any);
        }];
    }
}

// How much a creator is favoured right now: base 1, plus their learned score, plus a little noise.
- (double)weightForCreator:(NSString *)handle
{
    double score = [TKSettings scoreForCreator:handle];
    double base = 1.0 + (score > 0 ? score : score * 0.3);   // dislikes pull down gently, likes lift fully
    if (base < 0.1) base = 0.1;
    double noise = (double)(arc4random_uniform(1000)) / 1000.0 * 1.2;
    return base + noise;
}

// Places one video: picks a creator by weight (preferring not the last one placed), pops its freshest pooled video.
- (TKVideo *)placeOneAvoiding:(NSString *)lastHandle
{
    NSMutableArray *handles = [NSMutableArray array];
    for (NSString *h in self.pools) if ([self.pools[h] count]) [handles addObject:h];
    if (!handles.count) return nil;
    NSMutableArray *candidates = [handles mutableCopy];
    if (candidates.count > 1 && lastHandle) [candidates removeObject:lastHandle];
    double total = 0;
    NSMutableArray *weights = [NSMutableArray array];
    for (NSString *h in candidates) { double w = [self weightForCreator:h]; [weights addObject:@(w)]; total += w; }
    double pick = ((double)arc4random_uniform(1000000) / 1000000.0) * total;
    NSString *chosen = candidates.lastObject;
    double acc = 0;
    for (NSUInteger i = 0; i < candidates.count; i++) {
        acc += [weights[i] doubleValue];
        if (pick <= acc) { chosen = candidates[i]; break; }
    }
    NSMutableArray *pool = self.pools[chosen];
    // prefer an unseen video; fall back to the freshest if everything was seen before
    NSUInteger idx = NSNotFound;
    for (NSUInteger i = 0; i < pool.count; i++) if (![TKSettings hasSeenVideo:((TKVideo *)pool[i]).videoId]) { idx = i; break; }
    if (idx == NSNotFound) idx = 0;
    TKVideo *v = pool[idx];
    [pool removeObjectAtIndex:idx];
    [self.placedIds addObject:v.videoId];
    return v;
}

- (NSInteger)appendUpTo:(NSInteger)wanted
{
    NSInteger added = 0;
    NSString *last = [(TKVideo *)_videos.lastObject author];
    while (added < wanted) {
        TKVideo *v = [self placeOneAvoiding:last];
        if (!v) break;
        [_videos addObject:v];
        last = v.author;
        added++;
    }
    return added;
}

- (void)reloadWithCompletion:(void (^)(NSError *))completion
{
    [_videos removeAllObjects];
    [self.pools removeAllObjects];
    [self.placedIds removeAllObjects];
    if (![TKTikTok configured]) { if (completion) completion(TKMakeError(TKErrorAPI, L(@"Set the server address in Settings first."))); return; }
    if (![TKSettings creators].count) { if (completion) completion(TKMakeError(TKErrorRestricted, L(@"Add a creator to start your feed."))); return; }
    self.loading = YES;
    [self fillPools:^(BOOL any) {
        self.loading = NO;
        if (!any) { if (completion) completion(TKMakeError(TKErrorNetwork, L(@"Could not load any videos. Check the server and the creators."))); return; }
        [self appendUpTo:20];
        if (completion) completion(nil);
    }];
}

- (void)ensureAhead:(NSInteger)index by:(NSInteger)count completion:(void (^)(BOOL))completion
{
    NSInteger need = (index + count) - (NSInteger)self.videos.count;
    if (need <= 0) { if (completion) completion(NO); return; }
    NSInteger added = [self appendUpTo:need];
    if (added >= need || self.loading) { if (completion) completion(added > 0); return; }
    // pools ran dry: refetch (the creators may have new videos, and seen ones can come round again)
    self.loading = YES;
    [self fillPools:^(BOOL any) {
        self.loading = NO;
        NSInteger more = [self appendUpTo:need - added];
        if (completion) completion(added + more > 0);
    }];
}

- (void)noteVideo:(TKVideo *)video completed:(BOOL)completed saved:(BOOL)saved skipped:(BOOL)skipped
{
    if (!video) return;
    [TKSettings noteCreator:video.author completed:completed saved:saved skipped:skipped];
    if (completed || saved) [TKSettings markVideoSeen:video.videoId];
}

@end
