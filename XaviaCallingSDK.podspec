Pod::Spec.new do |s|
  s.name             = 'XaviaCallingSDK'
  s.version          = '1.0.0'
  s.summary          = 'Pure iOS WebRTC calling SDK'
  s.description      = 'Service-only WebRTC SDK using Socket.IO and native WebRTC'
  s.homepage         = 'https://github.com/xaviasolutions/xavia-calling-sdk-swift'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'YourTeam' => 'ios@yourcompany.com' }
  s.source           = { :git => 'https://github.com/xaviasolutions/xavia-calling-sdk-swift.git', :tag => s.version.to_s }

  s.ios.deployment_target = '12.0'
  s.swift_version = '5.7'

  s.source_files = 'Sources/XaviaCallingSDK/**/*.{swift}'

  # ✅ AUTO INSTALL DEPENDENCIES
  s.dependency 'Socket.IO-Client-Swift', '~> 16.0'
  s.dependency 'WebRTC-SDK', '~> 125.0'
end
