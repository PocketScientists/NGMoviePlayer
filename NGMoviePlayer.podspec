Pod::Spec.new do |s|
  s.platform     = :ios, '6.0'
  s.name         = 'NGMoviePlayer'
  s.version      = '1.0.0'
  s.license      = ''
  s.summary      = 'A movieplayer based on AVFoundation'
  s.homepage     = 'http://pocketscience.com/'
  s.authors      = { 'PocketScience GmbH' => 'r.grill@pocketscience.com' }
  s.source       = { :git => 'https://github.com/PocketScientists/NGMoviePlayer.git' }
  s.source_files = 'NGMoviePlayer/*/*.{h,m}'
  s.resource = 'NGMoviePlayer/Resources/NGMoviePlayer.bundle'
  s.requires_arc = true
  s.frameworks   = 'CoreMedia', 'AudioToolbox', 'AVFoundation', 'MediaPlayer', 'AVKit'

  s.prefix_header_contents = '
#ifdef __OBJC__
  #import <Foundation/Foundation.h>
  #import <UIKit/UIKit.h>
  #import <AVFoundation/AVFoundation.h>
  #import <QuartzCore/QuartzCore.h>
  #import <MediaPlayer/MediaPlayer.h>
  #import <AVKit/AVKit.h>
#endif

#define kNGFadeDuration                     0.33

#if __has_feature(objc_arc_weak)
    #define ng_weak  weak
    #define __ng_weak __weak
#else
    #define ng_weak  unsafe_unretained
    #define __ng_weak __unsafe_unretained
#endif
    '

  s.dependency 'NGVolumeControl'
  s.dependency 'PSPushPopPressView'
end
