Pod::Spec.new do |s|
  s.name             = 'XaviaCalling'
  s.version          = '1.0.0'
  s.summary          = 'Native iOS WebRTC video/audio calling SDK'
  s.description      = <<-DESC
  Lightweight native WebRTC calling service with Socket.IO signaling
  DESC

  s.homepage         = 'https://github.com/xaviasolutions/xavia-calling-sdk-swift'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Your Name' => 'your@email.com' }
  s.source           = { :git => 'https://github.com/xaviasolutions/xavia-calling-sdk-swift', :tag => s.version.to_s }

  s.ios.deployment_target = '12.0'
  s.swift_version    = '5.7'

  s.source_files     = 'XaviaCalling/**/*.{swift}'
  s.requires_arc     = true

  s.dependency 'WebRTC-lib', '~> 141.0'               # ← from https://github.com/stasel/WebRTC
  s.dependency 'Socket.IO-Client-Swift', '~> 16.1'

  s.frameworks       = 'AVFoundation', 'Foundation', 'UIKit'

  s.static_framework = true

  s.pod_target_xcconfig = {
    'ENABLE_BITCODE'               => 'NO',
    'OTHER_LDFLAGS'                => '$(inherited) -ObjC',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) WEBRTC_IOS=1'
  }

  s.user_target_xcconfig = { 'ENABLE_BITCODE' => 'NO' }
end