#import <UIKit/UIKit.h>
#import "TKModels.h"

@class TKVideoCell;

@protocol TKVideoCellDelegate <NSObject>
- (void)videoCellDidTapSave:(TKVideoCell *)cell;
- (void)videoCellDidTapComments:(TKVideoCell *)cell;
- (void)videoCellDidTapShare:(TKVideoCell *)cell;
- (void)videoCellDidReachEnd:(TKVideoCell *)cell;        // one loop finished (for auto-advance / completion)
@end

// One full-screen video page: AVPlayer behind, cover art until the first frame, the author/description overlay
// and the right-hand buttons. The feed controller owns resolve; the cell just plays a resolved TKVideo and loops.
@interface TKVideoCell : UIView
@property (nonatomic, weak) id<TKVideoCellDelegate> delegate;
@property (nonatomic, readonly) TKVideo *video;
@property (nonatomic, readonly) BOOL playing;
@property (nonatomic, readonly) NSTimeInterval playedSeconds;   // how long it has actually played (for "completed")

- (void)showVideo:(TKVideo *)video;         // labels + cover; no network yet
- (void)startPlaybackMuted:(BOOL)muted;     // needs video.playURL; builds the proxy URL and plays, looping
- (void)setActive:(BOOL)active;             // the visible page plays; others pause
- (void)setMuted:(BOOL)muted;
- (void)updateSavedState:(BOOL)saved;
- (void)showError:(NSString *)message;
- (void)teardown;
@end
