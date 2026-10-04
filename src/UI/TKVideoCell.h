#import <UIKit/UIKit.h>
#import "TKModels.h"

@class TKVideoCell;

@protocol TKVideoCellDelegate <NSObject>
- (void)videoCellDidTapSave:(TKVideoCell *)cell;
- (void)videoCellDidTapComments:(TKVideoCell *)cell;
- (void)videoCellDidTapShare:(TKVideoCell *)cell;
- (void)videoCellDidReachEnd:(TKVideoCell *)cell;        // one loop finished (for auto-advance / completion)
- (void)videoCellDidDoubleTap:(TKVideoCell *)cell;       // double tap = save (the cell shows the star burst itself)
- (void)videoCell:(TKVideoCell *)cell didLongPressAt:(CGPoint)point;   // hold = the video's menu
@end

// One full-screen video page: AVPlayer behind, cover art until the first frame, the author/description overlay,
// the right-hand buttons and a scrubber along the bottom edge. Gestures: tap = pause/play, double tap = save,
// hold = menu, drag sideways along the bottom = seek. The feed controller owns resolve; the cell just plays.
@interface TKVideoCell : UIView
@property (nonatomic, weak) id<TKVideoCellDelegate> delegate;
@property (nonatomic, readonly) TKVideo *video;
@property (nonatomic, readonly) BOOL playing;
@property (nonatomic, readonly) NSTimeInterval playedSeconds;   // furthest position reached
@property (nonatomic, readonly) NSTimeInterval duration;        // the item's length, else the video's listed one
@property (nonatomic, readonly) NSTimeInterval currentTime;     // the player's position
@property (nonatomic, readonly) BOOL fastPlayback;

- (void)showVideo:(TKVideo *)video;         // labels + cover; no network yet
- (void)preparePlayback;                    // off screen: buffers the start (no picture yet) so the swipe starts at once
- (void)startPlaybackMuted:(BOOL)muted;     // needs video.playURL; plays (reusing the prepared player), looping
- (void)setActive:(BOOL)active;             // the visible page plays; others pause
- (void)setMuted:(BOOL)muted;
- (BOOL)setFastPlayback:(BOOL)fast;         // 2x speed; NO when this video cannot play faster
- (NSTimeInterval)takeWatchedSeconds;       // real viewing time since the last call (loops add up, seeks do not)
- (void)updateSavedState:(BOOL)saved;
- (void)showError:(NSString *)message;
- (void)showToast:(NSString *)message;      // a short note in the middle that fades
- (void)teardown;

// For the debug URL commands: the gestures' actions without a finger
- (void)simulateDoubleTap;
- (void)simulateLongPress;
- (void)simulateScrubTo:(CGFloat)fraction;
@end
