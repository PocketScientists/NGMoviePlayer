#import "NGMoviePlayer.h"
#import "NGMoviePlayerView.h"
#import "NGMoviePlayerControlView.h"
#import "NGMoviePlayerControlView+NGPrivate.h"
#import "NGMoviePlayerLayout+NGPrivate.h"
#import "NGScrubber.h"
#import "NGMoviePlayerLayerView.h"
#import "NGMoviePlayerControlActionDelegate.h"


#define kNGInitialTimeToSkip                    10.     // this value gets added the first time (seconds)
#define kNGRepeatedTimeToSkipStartValue          5.     // this is the starting value the gets added repeatedly while user presses button (increases over time)
#define kNGDefaultSeekingToleranceTime           2.
#define kNGDefaultInitialPlaybackToleranceTime   1000.


static char playerItemStatusContext;
static char playerItemDurationContext;
static char playerCurrentItemContext;
static char playerRateContext;
static char playerAirPlayVideoActiveContext;


@interface NGMoviePlayer () <NGMoviePlayerControlActionDelegate, AVPictureInPictureControllerDelegate> {
    // flags for methods implemented in the delegate
    struct {
        unsigned int didStartPlayback:1;
        unsigned int didFailToLoad:1;
        unsigned int didFinishPlayback:1;
        unsigned int didPausePlayback:1;
        unsigned int didResumePlayback:1;
        unsigned int playbackStalled:1;
        unsigned int playbackFailed:1;

        unsigned int didBeginScrubbing:1;
        unsigned int didEndScrubbing:1;

        unsigned int didChangeStatus:1;
        unsigned int didChangePlaybackRate:1;
		unsigned int didChangeAirPlayActive:1;
        unsigned int didChangePictureInPictureActive:1;
        unsigned int didChangeControlStyle:1;
        unsigned int didUpdateCurrentTime:1;
        
        unsigned int willShowControls:1;
        unsigned int didShowControls:1;
        unsigned int willHideControls:1;
        unsigned int didHideControls:1;
        
	} _delegateFlags;

    BOOL _seekToInitialPlaybackTimeBeforePlay;
    float _rateToRestoreAfterScrubbing;
}

@property (nonatomic, strong, readwrite) AVPlayer *player;  // re-defined as read/write
@property (nonatomic, assign, readwrite, getter = isScrubbing) BOOL scrubbing; // re-defined as read/write
@property (nonatomic, strong) AVAsset *asset;
@property (nonatomic, strong) AVPlayerItem *playerItem;
@property (nonatomic, readonly) CMTime CMDuration;
@property (nonatomic, strong) id playerTimeObserver;

@property (nonatomic, assign) NSTimeInterval timeToSkip;
@property (nonatomic, ng_weak) NSTimer *skippingTimer;
@property (nonatomic, ng_weak) NSTimer *playableDurationTimer;

@end

@implementation NGMoviePlayer

@dynamic player;
@synthesize view = _view;

////////////////////////////////////////////////////////////////////////
#pragma mark - Class Methods
////////////////////////////////////////////////////////////////////////

+ (void)setAudioSessionCategory:(NGMoviePlayerAudioSessionCategory)audioSessionCategory {
    NSError *error = nil;
    [[AVAudioSession sharedInstance] setCategory:NGAVAudioSessionCategoryFromNGMoviePlayerAudioSessionCategory(audioSessionCategory)
                                           error:&error];

    if (error != nil) {
        NSLog(@"There was an error setting the AudioCategory to AVAudioSessionCategoryPlayback");
    }
}

+ (void)initialize {
    if (self == [NGMoviePlayer class]) {
        [self setAudioSessionCategory:NGMoviePlayerAudioSessionCategoryPlayback];
    }
}

////////////////////////////////////////////////////////////////////////
#pragma mark - Lifecycle
////////////////////////////////////////////////////////////////////////

- (id)initWithURL:(NSURL *)URL initialPlaybackTime:(NSTimeInterval)initialPlaybackTime duration:(NSTimeInterval)duration {
    
    if (self = [super init]) {
        _autostartWhenReady = NO;
        _seekToInitialPlaybackTimeBeforePlay = YES;
        _airPlayEnabled = [AVPlayer instancesRespondToSelector:@selector(allowsAirPlayVideo)];
        _rateToRestoreAfterScrubbing = 1.;
        _initialPlaybackTime = initialPlaybackTime;
        _seekingToleranceTime = kNGDefaultSeekingToleranceTime;
        _initialPlaybackToleranceTime = kNGDefaultInitialPlaybackToleranceTime;
        _userSetDuration = duration;
        _allowPlayingInBackground = NO;
        
        
        // calling setter here on purpose
        self.URL = URL;
    }
    return self;

}

- (id)initWithURL:(NSURL *)URL initialPlaybackTime:(NSTimeInterval)initialPlaybackTime {
    if ((self = [self initWithURL:URL initialPlaybackTime:initialPlaybackTime duration:0.])) {
    }
    return self;
}

- (id)initWithURL:(NSURL *)URL {
    return [self initWithURL:URL initialPlaybackTime:0.];
}

- (id)init {
    return [self initWithURL:nil];
}

- (void)dealloc {
    
    NSLog(@"[NGMoviePlayer] did dealloc");

    [_skippingTimer invalidate];
    [_playableDurationTimer invalidate];
    _delegate = nil;
    _view.delegate = nil;
    _view.controlsView.delegate = nil;
    [_view removeFromSuperview];
    
    [self removeObserversFromPlayerItem:self.playerItem];
    self.player = nil;

}

////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject KVO
////////////////////////////////////////////////////////////////////////

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == &playerItemStatusContext) {
        AVPlayerStatus status = [[change objectForKey:NSKeyValueChangeNewKey] integerValue];

        switch (status) {
            case AVPlayerStatusUnknown: {
                [self stopObservingPlayerTimeChanges];
                [self.view updateWithCurrentTime:self.currentPlaybackTime duration:self.duration];
                // TODO: Disable buttons & scrubber
                break;
            }

            case AVPlayerStatusReadyToPlay: {
                // TODO: Enable buttons & scrubber
                if (!self.scrubbing) {
                    if (self.autostartWhenReady && self.view.superview != nil && ([UIApplication sharedApplication].applicationState == UIApplicationStateActive || [self isAirPlayVideoActive] || self.allowPlayingInBackground)) {
                        _autostartWhenReady = NO;
                        [self play];
                    }
                }

                break;
            }

            case AVPlayerStatusFailed: {
                [self stopObservingPlayerTimeChanges];
                [self.view updateWithCurrentTime:self.currentPlaybackTime duration:self.duration];
                // TODO: Disable buttons & scrubber
                break;
            }
        }

        [self.view updateWithPlaybackStatus:self.playing];

        if (_delegateFlags.didChangeStatus) {
            [self.delegate moviePlayer:self didChangeStatus:status];
        }
    }

    else if (context == &playerItemDurationContext) {
        [self.view updateWithCurrentTime:self.currentPlaybackTime duration:self.duration];
    }

    else if (context == &playerCurrentItemContext) {
        AVPlayerItem *newPlayerItem = [change objectForKey:NSKeyValueChangeNewKey];

        if (newPlayerItem == (id)[NSNull null]) {
            [self stopObservingPlayerTimeChanges];
            // TODO: Disable buttons & scrubber
        } else {
            [self.view updateWithPlaybackStatus:self.playing];
            [self startObservingPlayerTimeChanges];
        }
    }

    else if (context == &playerRateContext) {
        [self.view updateWithPlaybackStatus:self.playing];

        if (_delegateFlags.didChangePlaybackRate) {
            [self.delegate moviePlayer:self didChangePlaybackRate:self.player.rate];
        }
    }

    else if (context == &playerAirPlayVideoActiveContext) {
        if ([AVPlayer instancesRespondToSelector:@selector(isExternalPlaybackActive)]) {
            [self.view updateViewsForCurrentScreenState];

            if (_delegateFlags.didChangeAirPlayActive) {
                BOOL airPlayVideoActive = self.player.externalPlaybackActive;

                [self.delegate moviePlayer:self didChangeAirPlayActive:airPlayVideoActive];
            }
        }
    }

    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

////////////////////////////////////////////////////////////////////////
#pragma mark - NGMoviePlayer Video Playback
////////////////////////////////////////////////////////////////////////

- (void)play {
    if (self.player.status == AVPlayerStatusReadyToPlay) {
        if (_seekToInitialPlaybackTimeBeforePlay && _initialPlaybackTime >= 0.) {
            CMTime time = CMTimeMakeWithSeconds(_initialPlaybackTime, NSEC_PER_SEC);
            CMTime tolerance = self.initialPlaybackToleranceCMTime;
            __weak typeof(self) wself = self;
            dispatch_block_t afterSeekAction = ^{
                [wself.view hidePlaceholderViewAnimated:YES];

                [wself moviePlayerDidStartToPlay];
                [wself updateControlsViewForLivestreamStatus];

                if (_delegateFlags.didStartPlayback) {
                    [wself.delegate moviePlayer:wself didStartPlaybackOfURL:wself.URL];
                }
            };

            if ([self.player respondsToSelector:@selector(seekToTime:toleranceBefore:toleranceAfter:completionHandler:)]) {
                [self.view showPlaceholderViewAnimated:NO];
                [self.player seekToTime:time
                        toleranceBefore:tolerance
                         toleranceAfter:tolerance
                      completionHandler:^(BOOL finished) {
                    afterSeekAction();
                }];
            } else {
                [self.player seekToTime:time toleranceBefore:tolerance toleranceAfter:tolerance];
                afterSeekAction();
            }

            _seekToInitialPlaybackTimeBeforePlay = NO;
        } else {
            [self.view hidePlaceholderViewAnimated:YES];

            if (_delegateFlags.didResumePlayback) {
                [self.delegate moviePlayerDidResumePlayback:self];
            }

            [self moviePlayerDidResumePlayback];
        }

        [self.player play];
        [self.view setControlsVisible:YES animated:YES];
    } else {
        _autostartWhenReady = YES;
    }

    [self.playableDurationTimer invalidate];
    self.playableDurationTimer = [NSTimer scheduledTimerWithTimeInterval:1.
                                                                  target:self
                                                                selector:@selector(updatePlayableDurationTimerFired:)
                                                                userInfo:nil
                                                                 repeats:YES];
}

- (void)pause {
    [self.player pause];

    [self.playableDurationTimer invalidate];
    self.playableDurationTimer = nil;
    [self.skippingTimer invalidate];
    self.skippingTimer = nil;

    if (_delegateFlags.didPausePlayback) {
        [self.delegate moviePlayerDidPausePlayback:self];
    }

    [self moviePlayerDidPausePlayback];
}

- (void)togglePlaybackState {
    if (self.playing) {
        [self pause];
    } else {
        [self play];
    }
}

- (void)stop {
    NSLog(@"[NGMoviePlayer] Stop!");
    
    [self pause];
    [self stopPictureInPicture];
    [self stopObservingPlayerTimeChanges];
    [self.asset cancelLoading];

}

////////////////////////////////////////////////////////////////////////
#pragma mark - NGMoviePlayer Subclass Hooks
////////////////////////////////////////////////////////////////////////

- (void)moviePlayerDidStartToPlay {
    // do nothing here
}

- (void)moviePlayerDidPausePlayback {
    // do nothing here
}

- (void)moviePlayerDidResumePlayback {
    // do nothing here
}

- (void)moviePlayerDidUpdateCurrentPlaybackTime:(NSTimeInterval)currentPlaybackTime {
    // do nothing here
}

- (void)moviePlayerWillShowControlsWithDuration:(NSTimeInterval)duration {
    // do nothing here
}

- (void)moviePlayerDidShowControls {
    // do nothing here
}

- (void)moviePlayerWillHideControlsWithDuration:(NSTimeInterval)duration {
    // do nothing here
}

- (void)moviePlayerDidHideControls {
    // do nothing here
}

////////////////////////////////////////////////////////////////////////
#pragma mark - NGMoviePlayer View
////////////////////////////////////////////////////////////////////////

- (void)addToSuperview:(UIView *)view withFrame:(CGRect)frame {
    self.view.frame = frame;
    [view addSubview:self.view];
}


////////////////////////////////////////////////////////////////////////
#pragma mark - NGMoivePlayer Control View
////////////////////////////////////////////////////////////////////////

- (NSTimeInterval)currentScrubberValue {
    return self.view.currentScrubberValue;
}

////////////////////////////////////////////////////////////////////////
#pragma mark - NGMoviePlayer Properties
////////////////////////////////////////////////////////////////////////

- (NGMoviePlayerView *)view {
    if (_view == nil) {
        _view = [[NGMoviePlayerView alloc] initWithFrame:CGRectZero];
        _view.continueExternalPlayingIfViewHidden = self.continueExternalPlayingIfViewHidden;
        _view.delegate = self;

        // layout that is used per default
        self.layout = [NGMoviePlayerDefaultLayout new];
    }

    return _view;
}

- (AVPlayer *)player {
    return self.view.playerLayer.player;
}

- (void)setPlayer:(AVPlayer *)player {
    if (player != self.view.playerLayer.player) {
        if (player == nil) {
            [self removeObserversFromPlayer:self.player];
            self.view.playerLayer.player = nil;
        }
        else {
            // Support AirPlay?
            if (self.airPlayEnabled) {
                [player setAllowsExternalPlayback:YES];
                [player setUsesExternalPlaybackWhileExternalScreenIsActive:YES];
            }
            
            self.view.playerLayer.player = player;
            
            if (AVPictureInPictureController.isPictureInPictureSupported) {
                self.pictureInPictureController = [[AVPictureInPictureController alloc] initWithPlayerLayer:self.view.playerLayer];
                self.pictureInPictureController.delegate = self;
                [self.view updatePictureInPictureButtonWithImage:[AVPictureInPictureController pictureInPictureButtonStartImageCompatibleWithTraitCollection:nil]];
            } else {
                NSLog(@"[NGMoviePlayer] can't create PiP-Controller: Not supported");
            }
            self.view.delegate = self;
        }
    }
}

- (void)setAirPlayEnabled:(BOOL)airPlayEnabled {
    if ([AVPlayer instancesRespondToSelector:@selector(allowsAirPlayVideo)]) {
        if (airPlayEnabled != _airPlayEnabled) {
            _airPlayEnabled = airPlayEnabled;
        }
    }
}

- (BOOL)isAirPlayVideoActive {
    return [AVPlayer instancesRespondToSelector:@selector(isExternalPlaybackActive)] && self.player.externalPlaybackActive;
}

- (void)setURL:(NSURL *)URL {
    if (_URL != URL) {
        _URL = URL;

        if (_view != nil) {
            [self.player pause];
            self.player = nil;
        }

        if (URL != nil) {
            NSArray *keys = [NSArray arrayWithObjects:@"tracks", @"playable", nil];

            [self setAsset:[AVURLAsset URLAssetWithURL:URL options:nil]];
            __weak typeof(self) wself = self;
            [self.asset loadValuesAsynchronouslyForKeys:keys completionHandler:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    [wself doneLoadingAsset:self.asset withKeys:keys];
                });
            }];
            
            [self.view updateWithCurrentTime:0. duration:0.];
            [self.view showPlaceholderViewAnimated:(self.view.placeholderView.alpha != 1.f)];
        }
    }
}

- (void)setURL:(NSURL *)URL initialPlaybackTime:(NSTimeInterval)initialPlaybackTime {
    self.initialPlaybackTime = initialPlaybackTime;
    self.URL = URL;
}

- (void)setDelegate:(id<NGMoviePlayerDelegate>)delegate {
    if (delegate != _delegate) {
        _delegate = delegate;

        _delegateFlags.didStartPlayback = [delegate respondsToSelector:@selector(moviePlayer:didStartPlaybackOfURL:)];
        _delegateFlags.didFailToLoad = [delegate respondsToSelector:@selector(moviePlayer:didFailToLoadURL:)];
        _delegateFlags.didFinishPlayback = [delegate respondsToSelector:@selector(moviePlayer:didFinishPlaybackOfURL:)];
        _delegateFlags.didPausePlayback = [delegate respondsToSelector:@selector(moviePlayerDidPausePlayback:)];
        _delegateFlags.didResumePlayback = [delegate respondsToSelector:@selector(moviePlayerDidResumePlayback:)];
        _delegateFlags.playbackFailed = [delegate respondsToSelector:@selector(moviePlayerPlaybackFailed:)];
        _delegateFlags.playbackStalled = [delegate respondsToSelector:@selector(moviePlayerPlaybackStalled:)];

        _delegateFlags.didBeginScrubbing = [delegate respondsToSelector:@selector(moviePlayerDidBeginScrubbing:)];
        _delegateFlags.didEndScrubbing = [delegate respondsToSelector:@selector(moviePlayerDidEndScrubbing:)];

        _delegateFlags.didChangeStatus = [delegate respondsToSelector:@selector(moviePlayer:didChangeStatus:)];
        _delegateFlags.didChangePlaybackRate = [delegate respondsToSelector:@selector(moviePlayer:didChangePlaybackRate:)];
        _delegateFlags.didChangeAirPlayActive = [delegate respondsToSelector:@selector(moviePlayer:didChangeAirPlayActive:)];
        _delegateFlags.didChangePictureInPictureActive = [delegate respondsToSelector:@selector(moviePlayer:didChangePictureInPictureActive:)];
        _delegateFlags.didChangeControlStyle = [delegate respondsToSelector:@selector(moviePlayer:didChangeControlStyle:)];
        _delegateFlags.didUpdateCurrentTime = [delegate respondsToSelector:@selector(moviePlayer:didUpdateCurrentTime:)];
        
        _delegateFlags.willHideControls = [delegate respondsToSelector:@selector(moviePlayerWillHideControls:)];
        _delegateFlags.didHideControls = [delegate respondsToSelector:@selector(moviePlayerDidHideControls:)];
        _delegateFlags.willShowControls = [delegate respondsToSelector:@selector(moviePlayerWillShowControls:)];
        _delegateFlags.didHideControls = [delegate respondsToSelector:@selector(moviePlayerDidShowControls:)];
    }
}




- (BOOL)isPlaying {
    return self.player != nil && self.player.rate != 0.f;
}

- (BOOL)isPlayingLivestream {
    return self.URL != nil && (isnan(self.duration) || self.duration <= 0.);
}

- (void)setVideoGravity:(NGMoviePlayerVideoGravity)videoGravity {
    self.view.playerLayer.videoGravity = NGAVLayerVideoGravityFromNGMoviePlayerVideoGravity(videoGravity);
    // Hack: otherwise the video gravity doesn't change immediately
    self.view.playerLayer.bounds = self.view.playerLayer.bounds;
}

- (NGMoviePlayerVideoGravity)videoGravity {
    return NGMoviePlayerVideoGravityFromAVLayerVideoGravity(self.view.playerLayer.videoGravity);
}

- (void)setCurrentPlaybackTime:(NSTimeInterval)currentTime {
    currentTime = MAX(currentTime,0.);
    currentTime = MIN(currentTime,self.duration);

    CMTime time = CMTimeMakeWithSeconds(currentTime, NSEC_PER_SEC);
    CMTime tolerance = self.seekingToleranceCMTime;

    // completion handler only supported in iOS 5
    __weak typeof(self) wself = self;
    if ([self.player respondsToSelector:@selector(seekToTime:toleranceBefore:toleranceAfter:completionHandler:)]) {
        [self.player seekToTime:time
                toleranceBefore:tolerance
                 toleranceAfter:tolerance
              completionHandler:^(BOOL finished) {
                  if (finished) {
                      [wself.view updateWithCurrentTime:self.currentPlaybackTime duration:self.duration];
                  }
              }];
    } else {
        [self.player seekToTime:time toleranceBefore:tolerance toleranceAfter:tolerance];
        [self.view updateWithCurrentTime:currentTime duration:self.duration];
    }
}

- (NSTimeInterval)currentPlaybackTime {
    return CMTimeGetSeconds(self.player.currentTime);
}

- (NSTimeInterval)duration {
    
    if (self.userSetDuration > 0. && self.shouldShowUserSetDuration == YES) {
        return self.userSetDuration;
    } else {
        return CMTimeGetSeconds(self.CMDuration);
    }
}

- (NSTimeInterval)playableDuration {
    NSArray *loadedTimeRanges = [self.player.currentItem loadedTimeRanges];

    if (loadedTimeRanges.count > 0) {
        CMTimeRange timeRange = [[loadedTimeRanges objectAtIndex:0] CMTimeRangeValue];
        Float64 startSeconds = CMTimeGetSeconds(timeRange.start);
        Float64 durationSeconds = CMTimeGetSeconds(timeRange.duration);

        return (NSTimeInterval)(startSeconds + durationSeconds);
    } else {
        return 0.;
    }
}

- (void)setLayout:(NGMoviePlayerLayout *)layout {
    layout.moviePlayer = self;
    self.view.controlsView.layout = layout;

    [layout invalidateLayout];
}

- (NGMoviePlayerLayout *)layout {
    return self.view.controlsView.layout;
}

- (void)setContinueExternalPlayingIfViewHidden:(BOOL)continueExternalPlayingIfViewHidden
{
    _continueExternalPlayingIfViewHidden = continueExternalPlayingIfViewHidden;
    if (_view) {
        _view.continueExternalPlayingIfViewHidden = continueExternalPlayingIfViewHidden;
    }
}

////////////////////////////////////////////////////////////////////////
#pragma mark - Notifications
////////////////////////////////////////////////////////////////////////

- (void)playerItemDidPlayToEndTime:(NSNotification *)notification {
    NSLog(@"[NGMoviePlayer] --playerItemDidPlayToEndTime");
    [self.player pause];

    _seekToInitialPlaybackTimeBeforePlay = YES;
    [self.view setControlsVisible:YES animated:YES];

    if (_delegateFlags.didFinishPlayback) {
        [self.delegate moviePlayer:self didFinishPlaybackOfURL:self.URL];
    }
}

- (void)playerItemFailedToPlayToEndTime:(NSNotification *)notification {
    if (_delegateFlags.playbackFailed) {
        [self.delegate moviePlayerPlaybackFailed:self];
    }
}

- (void)playerItemPlaybackStalled:(NSNotification *)notification {
    if (_delegateFlags.playbackStalled) {
        [self.delegate moviePlayerPlaybackStalled:self];
    }
}

////////////////////////////////////////////////////////////////////////
#pragma mark - Scrubbing/Skipping
////////////////////////////////////////////////////////////////////////

- (void)beginScrubbing {
    [self stopObservingPlayerTimeChanges];

    _rateToRestoreAfterScrubbing = self.player.rate;
    self.player.rate = 0.f;
    self.scrubbing = YES;

    if (_delegateFlags.didBeginScrubbing) {
        [self.delegate moviePlayerDidBeginScrubbing:self];
    }
}

- (void)endScrubbing {

    // TODO: We need to set this somewhere later (or find another workaround)
    // Current Bug: when the player is paused and the user scrubs player starts
    // playing again because we get a KVO notification that the status changed to ReadyForPlay
    self.scrubbing = NO;
    self.player.rate = _rateToRestoreAfterScrubbing;
    _rateToRestoreAfterScrubbing = 0.f;

    [self.skippingTimer invalidate];
    self.skippingTimer = nil;
    [self startObservingPlayerTimeChanges];

    if (_delegateFlags.didEndScrubbing) {
        [self.delegate moviePlayerDidEndScrubbing:self];
    }
}

- (void)beginSkippingBackwards {
    [self beginScrubbing];

    self.currentPlaybackTime -= kNGInitialTimeToSkip;
    self.timeToSkip = kNGRepeatedTimeToSkipStartValue;

    self.skippingTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                          target:self
                                                        selector:@selector(skipTimerFired:)
                                                        userInfo:[NSNumber numberWithInt:NGMoviePlayerControlActionBeginSkippingBackwards]
                                                         repeats:YES];
}

- (void)beginSkippingForwards {
    [self beginScrubbing];

    self.currentPlaybackTime += kNGInitialTimeToSkip;
    self.timeToSkip = kNGRepeatedTimeToSkipStartValue;

    self.skippingTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                          target:self
                                                        selector:@selector(skipTimerFired:)
                                                        userInfo:[NSNumber numberWithInt:NGMoviePlayerControlActionBeginSkippingForwards]
                                                         repeats:YES];
}
////////////////////////////////////////////////////////////////////////
#pragma mark - AVPictureInPicture methods
////////////////////////////////////////////////////////////////////////

- (void)startPictureInPicture {
    
    [self.pictureInPictureController startPictureInPicture];
    
    if ([AVPictureInPictureController isPictureInPictureSupported] == NO) {
        NSLog(@"[NGMoviePlayer] PictureInPicture not supported");
    } else if (self.pictureInPictureController.pictureInPicturePossible == NO) {
        NSLog(@"[NSMoviePlayer] PictureInPicture not possible");
    }
}

- (void)stopPictureInPicture {
    if (self.pictureInPictureController.isPictureInPictureActive) {
        [self.pictureInPictureController stopPictureInPicture];
    }
}


////////////////////////////////////////////////////////////////////////
#pragma mark - AVPictureInPictureDelegate
////////////////////////////////////////////////////////////////////////

- (void)pictureInPictureControllerDidStartPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    NSLog(@"[NGMoviePlayer] PiP did start successfully");
    [self.view updatePictureInPictureButtonWithImage:[AVPictureInPictureController pictureInPictureButtonStopImageCompatibleWithTraitCollection:nil]];
}


- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    NSLog(@"[NGMoviePlayer] PiP did stop");
    [self.view updatePictureInPictureButtonWithImage:[AVPictureInPictureController pictureInPictureButtonStartImageCompatibleWithTraitCollection:nil]];
}

- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController failedToStartPictureInPictureWithError:(NSError *)error {
    NSLog(@"[NGMoviePlayer] PiP did fail with error: %@", error);
}


////////////////////////////////////////////////////////////////////////
#pragma mark - NGMoviePlayerControlViewDelegate
////////////////////////////////////////////////////////////////////////

- (void)moviePlayerControl:(id)control didPerformAction:(NGMoviePlayerControlAction)action {
    [self.view stopFadeOutControlsViewTimer];

    switch (action) {
        case NGMoviePlayerControlActionStartToPlay: {
            [self play];
            [self.view restartFadeOutControlsViewTimer];
            break;
        }

        case NGMoviePlayerControlActionTogglePlayPause: {
            [self togglePlaybackState];
            [self.view restartFadeOutControlsViewTimer];
            break;
        }

        case NGMoviePlayerControlActionToggleZoomState: {
            if (self.view.controlStyle == NGMoviePlayerControlStyleInline) {
                self.view.controlStyle = NGMoviePlayerControlStyleFullscreen;
            } else {
                self.view.controlStyle = NGMoviePlayerControlStyleInline;
            }

            [self.view restartFadeOutControlsViewTimer];

            if (_delegateFlags.didChangeControlStyle) {
                [self.delegate moviePlayer:self didChangeControlStyle:self.view.controlStyle];
            }
            break;
        }

        case NGMoviePlayerControlActionBeginSkippingBackwards: {
            [self beginSkippingBackwards];
            break;
        }

        case NGMoviePlayerControlActionBeginSkippingForwards: {
            [self beginSkippingForwards];
            break;
        }

        case NGMoviePlayerControlActionBeginScrubbing: {
            [self beginScrubbing];
            break;
        }

        case NGMoviePlayerControlActionScrubbingValueChanged: {
            if ([control isKindOfClass:[NGScrubber class]]) {
                NGScrubber *slider = (NGScrubber *)control;

                float value = slider.value;
                [self setCurrentPlaybackTime:value];
                _seekToInitialPlaybackTimeBeforePlay = NO;
            }

            break;
        }

        case NGMoviePlayerControlActionEndScrubbing:
        case NGMoviePlayerControlActionEndSkipping: {
            [self endScrubbing];
            [self.view restartFadeOutControlsViewTimer];
            _seekToInitialPlaybackTimeBeforePlay = NO;
            break;
        }

        case NGMoviePlayerControlActionVolumeChanged: {
            [self.view restartFadeOutControlsViewTimer];
            break;
        }

        case NGMoviePlayerControlActionWillShowControls: {
            if (!_delegateFlags.willShowControls || [self.delegate moviePlayerWillShowControls:self]) {
                [self moviePlayerWillShowControlsWithDuration:kNGFadeDuration];
            }
            break;
        }
            
        case NGMoviePlayerControlActionWillHideControls: {
            if (!_delegateFlags.willHideControls || [self.delegate moviePlayerWillHideControls:self]) {
                [self moviePlayerWillHideControlsWithDuration:kNGFadeDuration];
            }
            break;
        }

        case NGMoviePlayerControlActionDidShowControls: {
            [self moviePlayerDidShowControls];
            [self.view restartFadeOutControlsViewTimer];
            break;
        }

        case NGMoviePlayerControlActionDidHideControls: {
            [self moviePlayerDidHideControls];
            [self.view restartFadeOutControlsViewTimer];
            break;
        }

        case NGMoviePlayerControlActionAirPlayMenuActivated: {
            [self.view restartFadeOutControlsViewTimer];
            break;
        }
            
        case NGMoviePlayerControlActionPictureInPictureActivated: {
            BOOL active = NO;
            if (self.pictureInPictureController.isPictureInPictureActive) {
                //active = NO;
                [self stopPictureInPicture];
            } else {
                active = YES;
                [self startPictureInPicture];
            }
            
            if (_delegateFlags.didChangePictureInPictureActive) {
                [self.delegate moviePlayer:self didChangePictureInPictureActive:active];
            }
            break;
        }

        
        default:
            // do nothing
            break;

    }
}

- (BOOL)moviePlayerControl:(id)control willPerformAction:(NGMoviePlayerControlAction)action {
    switch (action) {
        case NGMoviePlayerControlActionWillShowControls: {
            if (!_delegateFlags.willShowControls || [self.delegate moviePlayerWillShowControls:self]) {
                [self moviePlayerWillShowControlsWithDuration:kNGFadeDuration];
            } else {
                return NO;
            }
            break;
        }
            
        case NGMoviePlayerControlActionWillHideControls: {
            if (!_delegateFlags.willHideControls || [self.delegate moviePlayerWillHideControls:self]) {
                [self moviePlayerWillHideControlsWithDuration:kNGFadeDuration];
            } else {
                return NO;
            }
            break;
        }
            
        default:
            break;
    }
    return YES;
}

////////////////////////////////////////////////////////////////////////
#pragma mark - Private
////////////////////////////////////////////////////////////////////////

- (CMTime)CMDuration {
    CMTime duration = kCMTimeInvalid;

    // Peferred in HTTP Live Streaming
    if ([self.playerItem respondsToSelector:@selector(duration)] && // 4.3
        self.player.currentItem.status == AVPlayerItemStatusReadyToPlay) {

        if (CMTIME_IS_VALID(self.playerItem.duration)) {
            duration = self.playerItem.duration;
        }
    }

    // when playing over AirPlay the previous duration always returns 1, so we check again
    if ((!CMTIME_IS_VALID(duration) || duration.timescale == 0 || duration.value/duration.timescale < 2) && CMTIME_IS_VALID(self.player.currentItem.asset.duration)) {
        duration = self.player.currentItem.asset.duration;
    }
    

    return duration;
}

- (void)doneLoadingAsset:(AVAsset *)asset withKeys:(NSArray *)keys {
    NSLog(@"[NGMoviePlayer] doneLoadingAssets");
    
    if (!asset.playable) {
        if (_delegateFlags.didFailToLoad) {
            [self.delegate moviePlayer:self didFailToLoadURL:self.URL];
        }

        return;
    }

    // Check if all keys are OK
    for (NSString *key in keys) {
        NSError *error = nil;
        AVKeyValueStatus status = [asset statusOfValueForKey:key error:&error];

        if (status == AVKeyValueStatusFailed || status == AVKeyValueStatusCancelled) {
            if (_delegateFlags.didFailToLoad) {
                [self.delegate moviePlayer:self didFailToLoadURL:self.URL];
            }

            return;
        }
    }

    // Remove observer from old playerItem and create new one
    if (self.playerItem) {
        [self removeObserversFromPlayerItem:self.playerItem];
    }

    self.playerItem = nil;
    self.playerItem = [AVPlayerItem playerItemWithAsset:asset];

    [self addObserversToPlayerItem:self.playerItem];

    _seekToInitialPlaybackTimeBeforePlay = YES;

    // Create the player
    if (!self.player) {
        NSLog(@"[NGMoviePlayer] Create new AVPlayer");
        AVPlayer *player = [AVPlayer playerWithPlayerItem:self.playerItem];
        self.player = player;
        [self addObserversToPlayer:self.player];
    }

    // New playerItem?
    if (self.player.currentItem != self.playerItem) {
        NSLog(@"[NGMoviePlayer] Replace old AVPlayerItem with new one");
        [self.player replaceCurrentItemWithPlayerItem:self.playerItem];
        [self.view updateWithPlaybackStatus:self.playing];
    }
}




- (void)updateControlsViewForLivestreamStatus {
    // layout might change when playing livestream
    [self.layout invalidateLayout];
}

- (void)skipTimerFired:(NSTimer *)timer {
    NGMoviePlayerControlAction action = [timer.userInfo intValue];
    
    if (action == NGMoviePlayerControlActionBeginSkippingBackwards) {
        self.currentPlaybackTime -= self.timeToSkip++;
    } else if (action == NGMoviePlayerControlActionBeginSkippingForwards) {
        self.currentPlaybackTime += self.timeToSkip++;
    }
}

- (void)updatePlayableDurationTimerFired:(NSTimer *)timer {
    self.view.controlsView.playableDuration = self.playableDuration;
}

- (CMTime)seekingToleranceCMTime {
    if (self.seekingToleranceTime >= 1000.) {
        return kCMTimePositiveInfinity;
    } else if (self.seekingToleranceTime <= 0.001) {
        return kCMTimeZero;
    } else {
        return CMTimeMakeWithSeconds(self.seekingToleranceTime, NSEC_PER_SEC);
    }
}

- (CMTime)initialPlaybackToleranceCMTime {
    if (self.initialPlaybackToleranceTime >= 1000.) {
        return kCMTimePositiveInfinity;
    } else if (self.initialPlaybackToleranceTime <= 0.001) {
        return kCMTimeZero;
    } else {
        return CMTimeMakeWithSeconds(self.initialPlaybackToleranceTime, NSEC_PER_SEC);
    }
}


////////////////////////////////////////////////////////////////////////
#pragma mark - Add/Remove Observers
////////////////////////////////////////////////////////////////////////

- (void)removeObserversFromPlayerItem:(AVPlayerItem *)playerItem {
    NSLog(@"[NGMoviePlayer] Remove observers from playerItem");
    if (playerItem) {
        [playerItem removeObserver:self forKeyPath:@"status"];
        [playerItem removeObserver:self forKeyPath:@"duration"];
        
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:AVPlayerItemDidPlayToEndTimeNotification
                                                      object:playerItem];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:AVPlayerItemFailedToPlayToEndTimeNotification
                                                      object:playerItem];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:AVPlayerItemPlaybackStalledNotification
                                                      object:playerItem];
    }

}

- (void)addObserversToPlayerItem:(AVPlayerItem *)playerItem {
    NSLog(@"[NGMoviePlayer] Add observers to playerItem");
    if (playerItem) {
    // Observe status, ok -> play
        [playerItem addObserver:self
                      forKeyPath:@"status"
                         options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                         context:&playerItemStatusContext];
    
    // Durationchange
        [playerItem addObserver:self
                      forKeyPath:@"duration"
                         options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                         context:&playerItemDurationContext];
    
        [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerItemDidPlayToEndTime:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:playerItem];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerItemFailedToPlayToEndTime:)
                                                 name:AVPlayerItemFailedToPlayToEndTimeNotification
                                               object:playerItem];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerItemPlaybackStalled:)
                                                 name:AVPlayerItemPlaybackStalledNotification
                                               object:playerItem];
    }
}


- (void)removeObserversFromPlayer:(AVPlayer *)player {
    
    if (player) {
        [player removeObserver:self forKeyPath:@"rate"];
        [player removeObserver:self forKeyPath:@"currentItem"];
        if ([AVPlayer instancesRespondToSelector:@selector(allowsAirPlayVideo)]) {
            [player removeObserver:self forKeyPath:@"airPlayVideoActive"];
        }
    }
}

- (void)addObserversToPlayer:(AVPlayer *)player {
    
    if (player) {
        // Observe currentItem, catch the -replaceCurrentItemWithPlayerItem:
        [player addObserver:self
                  forKeyPath:@"currentItem"
                     options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                     context:&playerCurrentItemContext];
    
        // Observe rate, play/pause-button?
        [player addObserver:self
                  forKeyPath:@"rate"
                     options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                     context:&playerRateContext];
    
        if ([AVPlayer instancesRespondToSelector:@selector(allowsAirPlayVideo)]) {
            [player addObserver:self
                      forKeyPath:@"airPlayVideoActive"
                         options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                         context:&playerAirPlayVideoActiveContext];
        }
    }

}

- (void)startObservingPlayerTimeChanges {
    if (self.playerTimeObserver == nil) {
        __ng_weak NGMoviePlayer *weakSelf = self;
        
        self.playerTimeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(.5, NSEC_PER_SEC)
                                                                            queue:dispatch_get_main_queue()
                                                                       usingBlock:^(CMTime time) {
                                                                           __strong NGMoviePlayer *strongSelf = weakSelf;
                                                                           
                                                                           if (strongSelf != nil && [strongSelf isKindOfClass:[NGMoviePlayer class]]) {
                                                                               if (CMTIME_IS_VALID(strongSelf.player.currentTime) && CMTIME_IS_VALID(strongSelf.CMDuration)) {
                                                                                   
                                                                                   CGFloat absoluteCurrentPlaybackTime = strongSelf.currentPlaybackTime + strongSelf.currentPlaybackTimeOffset;
                                                                                   
                                                                                   [strongSelf.view updateWithCurrentTime:absoluteCurrentPlaybackTime
                                                                                                                 duration:strongSelf.duration];
                                                                                   
                                                                                   [strongSelf moviePlayerDidUpdateCurrentPlaybackTime:strongSelf.currentPlaybackTime];
                                                                                   
                                                                                   if (strongSelf->_delegateFlags.didUpdateCurrentTime) {
                                                                                       [strongSelf.delegate moviePlayer:strongSelf didUpdateCurrentTime:strongSelf.currentPlaybackTime];
                                                                                   }
                                                                               }
                                                                           }
                                                                       }];
    }
}

- (void)stopObservingPlayerTimeChanges {
    if (self.playerTimeObserver != nil) {
        [self.player removeTimeObserver:self.playerTimeObserver];
        self.playerTimeObserver = nil;
    }
}


@end
