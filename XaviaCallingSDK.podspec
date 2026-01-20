Pod::Spec.new do |s|
  s.name             = 'XaviaCallingSDK'
  s.version          = '2.0.0'
  s.summary          = 'Xavia Calling SDK for iOS - WebRTC based video/audio calling'
  s.description      = <<-DESC
  A comprehensive WebRTC-based calling SDK for iOS that provides video/audio calling capabilities with signaling, media handling, and call management.
                       DESC
  
  s.homepage         = 'https://github.com/xaviasolutions/xavia-calling-sdk-swift.git'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Xavia Solutions' => 'contact@xavia.com' }
  s.source           = { :git => 'https://github.com/xaviasolutions/xavia-calling-sdk-swift.git', :branch => 'v2' }
  
  s.swift_version = '5.7'
  s.ios.deployment_target = '13.0'
  
  s.source_files = 'Sources/XaviaCallingSDK/**/*.{swift,h,m}'

  s.dependency 'WebRTC-lib', '124.0.0'
  
  s.pod_target_xcconfig = {
    'ENABLE_BITCODE' => 'NO',
    'OTHER_LDFLAGS' => '-ObjC',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES',
    'VALID_ARCHS' => 'arm64 x86_64',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64'
  }
  
  s.user_target_xcconfig = {
    'ENABLE_BITCODE' => 'NO'
  }
  
  s.resource_bundles = {
    'XaviaCallingSDK' => ['Sources/XaviaCallingSDK/PrivacyInfo.xcprivacy']
  }
  
  s.requires_arc = true
end