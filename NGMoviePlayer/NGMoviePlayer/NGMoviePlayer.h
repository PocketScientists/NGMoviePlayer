//
//  NGMoviePlayer.h
//  NGMoviePlayer
//
//  Created by Tretter Matthias on 06.03.12.
//  Copyright (c) 2012 NOUS Wissensmanagement GmbH. All rights reserved.
//

#import "NGMoviePlayerDelegate.h"
#import "NGMoviePlayerView.h"
#import "NGMoviePlayerControlView.h"
#import "NGMoviePlayerScreenState.h"
#import "NGMoviePlayerVideoGravity.h"
#import "NGMoviePlayerAudioSessionCategory.h"
#import "NGMoviePlayerViewController.h"
#import "NGMoviePlayerPlaceholderView.h"
#import "NGScrubber.h"
#import "NGWeak.h"
#import "NGMoviePlayerLayout.h"
#import "NGMoviePlayerDefaultLayout.h"
#import "NGMoviePlayerSystemLayout.h"

#import <AVKit/AVKit.h>


@interface NGMoviePlayer : NSObject

/** The wrapped AVPlayer object */
@property (nonatomic, strong, readonly) AVPlayer *player;
/** The player view */
@property (nonatomic, strong, readonly) NGMoviePlayerView *view;

/** The URL of the video to play, start player by setting the URL */
@property (nonatomic, copy) NSURL *URL;
/** flag to indicate if the player is currently playing */
@property (nonatomic, readonly, getter = isPlaying) BOOL playing;
/** Indicates whether the current played URL is a livestream */
@property (nonatomic, readonly, getter = isPlayingLivestream) BOOL playingLivestream;
/** flag that indicates whether the player is currently scrubbing */
@property (nonatomic, assign, readonly, getter = isScrubbing) BOOL scrubbing;
/** The delegate of the player */
@property (nonatomic, ng_weak) id<NGMoviePlayerDelegate> delegate;
/** The gravity of the video */
@property (nonatomic, assign) NGMoviePlayerVideoGravity videoGravity;

/** AirPlay is only supported on >= iOS 5, defaults to YES on iOS >= 5, NO otherwise */
@property (nonatomic, assign, getter = isAirPlayEnabled) BOOL airPlayEnabled;
/** Is AirPlay currently active? */
@property (nonatomic, readonly, getter = isAirPlayVideoActive) BOOL airPlayVideoActive;
/** flag to indicate whether the video autoplays when it's ready loading, defaults to NO */
@property (nonatomic, assign) BOOL autostartWhenReady;
/** indicates, that the player shall continue playing in airPlay mode even if the player view becomes hidden on the device. default NO */
@property (nonatomic, assign) BOOL continueExternalPlayingIfViewHidden;

/** current playback time of the player */
@property (nonatomic, assign) NSTimeInterval currentPlaybackTime;
/** is set if the current playback time should be show with an offset. the shown current playback time will be the offset plus the real current playbacktime */
@property (nonatomic, assign) NSTimeInterval currentPlaybackTimeOffset;
/** total duration of played video */
@property (nonatomic, readonly) NSTimeInterval duration;
/** custom duration that shoud be shown on the scubber/progress time view. */
@property (nonatomic, assign) NSTimeInterval userSetDuration;
/** indicates if the userSetDuration should be used (YES) or the duration of AVPlayerItem (NO) */
@property (nonatomic, assign) BOOL shouldShowUserSetDuration;
/** currently downloaded duration which is already playable */
@property (nonatomic, readonly) NSTimeInterval playableDuration;
/** initialPlaybackTime for playing the video */
@property (nonatomic, assign) NSTimeInterval initialPlaybackTime;
/** returns the value of the scrubber in the movie player's control view */
@property (nonatomic, readonly) NSTimeInterval currentScrubberValue;


/** tolerance offset in seconds that is used when playing from an initial playback time, use greater values for faster seeking. Defaults to kCMTimePositiveInfinity seconds */
@property (nonatomic, assign) NSTimeInterval initialPlaybackToleranceTime;
/** tolerance offset in seconds that is used when seeking to a specific time, use greater values for faster seeking. Defaults to 2 seconds */
@property (nonatomic, assign) NSTimeInterval seekingToleranceTime;
/** to allow starting videos  in background */
@property (nonatomic, assign) BOOL allowPlayingInBackground;


@property (nonatomic, strong) NGMoviePlayerLayout *layout;
/** controller for PicutreInPicture function */
@property (nonatomic, strong) AVPictureInPictureController *pictureInPictureController;
- (void)stopPictureInPicture;
- (void)startPictureInPicture;

/**
 By changing the audio session category you can influence how your audio output interacts with
 other system audio output. Default category is AudioSessionCategoryPlackback, which ignores the
 system volume mute switch.
 */
+ (void)setAudioSessionCategory:(NGMoviePlayerAudioSessionCategory)audioSessionCategory;

- (id)initWithURL:(NSURL *)URL;
- (id)initWithURL:(NSURL *)URL initialPlaybackTime:(NSTimeInterval)initialPlaybackTime;
- (id)initWithURL:(NSURL *)URL initialPlaybackTime:(NSTimeInterval)initialPlaybackTime duration:(NSTimeInterval)duration;

- (void)setURL:(NSURL *)URL initialPlaybackTime:(NSTimeInterval)initialPlaybackTime;

- (void)play;
- (void)pause;
- (void)togglePlaybackState;
/** CAUTION: pretty untested method */
- (void)stop;


/**
 Convenience method to set frame of view and add to superview
 */
- (void)addToSuperview:(UIView *)view withFrame:(CGRect)frame;

/******************************************
 @name Subclass Hooks
 
 Subclasses can override this method to perform an action here, the default implementation does nothing
 ******************************************/

- (void)moviePlayerDidStartToPlay;
- (void)moviePlayerDidPausePlayback;
- (void)moviePlayerDidResumePlayback;
- (void)moviePlayerDidUpdateCurrentPlaybackTime:(NSTimeInterval)currentPlaybackTime;

- (void)moviePlayerWillShowControlsWithDuration:(NSTimeInterval)duration;
- (void)moviePlayerDidShowControls;
- (void)moviePlayerWillHideControlsWithDuration:(NSTimeInterval)duration;
- (void)moviePlayerDidHideControls;

@end
