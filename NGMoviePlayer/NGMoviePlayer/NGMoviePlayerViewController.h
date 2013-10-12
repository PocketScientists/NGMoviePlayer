//
//  NGMoviePlayerViewController.h
//  NGMoviePlayer
//
//  Created by Matthias Tretter on 26.07.12.
//  Copyright (c) 2012 NOUS Wissensmanagement GmbH. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "NGMoviePlayerDelegate.h"


@class NGMoviePlayer;


@interface NGMoviePlayerViewController : UIViewController <NGMoviePlayerDelegate> {
    @protected
    NGMoviePlayer *_moviePlayer;
}

@property (nonatomic, strong, readonly) NGMoviePlayer *moviePlayer;

- (id)initWithContentURL:(NSURL *)contentURL;

/** Override to specify your custom subclass of NGMoviePlayer */
+ (Class)moviePlayerClass;

@end

@interface NGMoviePlayerViewController (SubclassingHooks)

- (void)dismiss;

@end
