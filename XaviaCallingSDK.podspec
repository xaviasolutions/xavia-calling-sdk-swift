Pod::Spec.new do |s|
  s.name             = 'XaviaCallingSDK'
  s.version          = '1.0.0'
  s.summary          = 'Production-ready native iOS Swift SDK for WebRTC calling'
  s.description      = <<-DESC
  XaviaCallingSDK is a comprehensive WebRTC calling SDK for iOS. It provides complete
  functionality for 1-on-1 and group video/audio calling with features including:
  - Connection management with auto-reconnection
  - Call creation, joining, and invitation system
  - Multi-participant support for group calls
  - Media stream management (audio/video)
  - WebRTC signaling with Socket.IO and REST API
  - Thread-safe implementation
  - Comprehensive error handling
  - Event-driven architecture with 12+ callbacks
                       DESC

  s.homepage         = 'https://github.com/xaviasolutions/xavia-calling-sdk-swift'
  s.license          = { :type => 'Proprietary', :text => 'Copyright 2026 Xavia Inc. All rights reserved.' }
  s.author           = { 'Xavia Inc' => 'support@xavia.io' }
  s.source           = { :git => 'https://github.com/xaviasolutions/xavia-calling-sdk-swift.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.swift_version = '5.9'

  s.source_files = 'Sources/**/*.swift'
  
  # Dependencies
  s.dependency 'WebRTC-lib'
  s.dependency 'Socket.IO-Client-Swift', '~> 16.0'
  
  # Framework settings
  s.frameworks = 'Foundation', 'AVFoundation', 'AudioToolbox', 'VideoToolbox'
  s.requires_arc = true
  
  # Exclude SwiftPM files
  s.exclude_files = 'Package.swift'
  
  # Pod settings
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_VERSION' => '5.9'
  }
end
