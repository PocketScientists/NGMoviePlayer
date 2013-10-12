//
//  NGMoviePlayerControlViewDelegate.h
//  NGMoviePlayer
//
//  Created by Tretter Matthias on 13.03.12.
//  Copyright (c) 2012 NOUS Wissensmanagement GmbH. All rights reserved.
//

typedef enum {
    NGMoviePlayerControlActionStartToPlay,
    NGMoviePlayerControlActionTogglePlayPause,
    NGMoviePlayerControlActionToggleZoomState,
    NGMoviePlayerControlActionBeginSkippingBackwards,
    NGMoviePlayerControlActionBeginSkippingForwards,
    NGMoviePlayerControlActionBeginScrubbing,
    NGMoviePlayerControlActionScrubbingValueChanged,
    NGMoviePlayerControlActionEndScrubbing,
    NGMoviePlayerControlActionEndSkipping,
    NGMoviePlayerControlActionVolumeChanged,
    NGMoviePlayerControlActionWillShowControls,
    NGMoviePlayerControlActionDidShowControls,
    NGMoviePlayerControlActionWillHideControls,
    NGMoviePlayerControlActionDidHideControls,
    NGMoviePlayerControlActionAirPlayMenuActivated
} NGMoviePlayerControlAction;


@protocol NGMoviePlayerControlActionDelegate <NSObject>

- (void)moviePlayerControl:(id)control didPerformAction:(NGMoviePlayerControlAction)action;

// will get called for NGMoviePlayerControlActionWillShowControls and NGMoviePlayerControlActionWillHideControls
- (BOOL)moviePlayerControl:(id)control willPerformAction:(NGMoviePlayerControlAction)action;

@end