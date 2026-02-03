Pod::Spec.new do |s|
  s.name             = 'XaviaCallingSDK'
  s.version          = '1.0.0'
  s.summary          = 'A complete WebRTC calling SDK for iOS'
  s.description      = <<-DESC
  A complete WebRTC implementation for iOS with audio/video calling capabilities.
  Features include:
  - Audio/Video calls
  - Group calling support
  - Socket.IO signaling
  - Media controls
  - ICE candidate handling
  - Auto-reconnection
  DESC
  
  s.homepage         = 'https://github.com/xaviasolutions/xavia-calling-sdk-swift'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Xavia Solutions' => 'support@xaviasolutions.com' }
  s.source           = { :git => 'https://github.com/xaviasolutions/xavia-calling-sdk-swift.git', :branch => 'v5' }
  
  # Lower deployment target to match your project
  s.ios.deployment_target = '13.0'
  s.swift_version = '5.5'
  
  s.source_files = 'Sources/**/*.swift'
  s.public_header_files = 'Sources/*.h'
  
  # Dependencies
  s.dependency 'GoogleWebRTC', '~> 1.1'
  s.dependency 'Socket.IO-Client-Swift', '~> 16.0'
  
  s.frameworks = 'AVFoundation', 'AudioToolbox', 'CoreMedia', 'CoreVideo', 'Foundation'
  s.libraries = 'c++'
  
  s.pod_target_xcconfig = {
    'VALID_ARCHS' => 'arm64 arm64e x86_64',
    'ENABLE_BITCODE' => 'NO',
    'DEFINES_MODULE' => 'YES'
  }
  
  s.user_target_xcconfig = {
    'VALID_ARCHS' => 'arm64 arm64e x86_64'
  }
end