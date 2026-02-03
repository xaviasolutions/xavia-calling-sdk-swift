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
  s.source           = { :git => 'https://github.com/xaviasolutions/xavia-calling-sdk-swift.git', :tag => s.version.to_s }
  
  s.ios.deployment_target = '15.0'
  s.swift_version = '5.9'
  
  s.source_files = 'Sources/**/*.swift'
  
  s.dependency 'GoogleWebRTC', '~> 1.1.31999'
  s.dependency 'Socket.IO-Client-Swift', '~> 16.0'
  
  s.frameworks = 'AVFoundation', 'AudioToolbox', 'CoreMedia', 'CoreVideo'
  s.libraries = 'c++'
  
  s.pod_target_xcconfig = {
    'VALID_ARCHS' => 'arm64 arm64e x86_64',
    'ENABLE_BITCODE' => 'NO'
  }
end