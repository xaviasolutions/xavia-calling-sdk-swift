Pod::Spec.new do |s|
  # Basic Information
  s.name             = 'XaviaCallingSDK'
  s.version          = '1.0.0'
  s.summary          = 'A comprehensive WebRTC calling SDK for iOS applications'
  s.description      = <<-DESC
XaviaCallingSDK provides a complete WebRTC-based calling solution for iOS applications.
It includes signaling, peer-to-peer connections, media streaming, and call management.
Perfect for building video/audio calling features into your mobile apps.
                       DESC

  # Repository Information
  s.homepage         = 'https://github.com/xaviasolutions/xavia-calling-sdk-swift'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Xavia Solutions' => 'contact@xavia.solutions' }
  s.source           = { 
    :git => 'https://github.com/xaviasolutions/xavia-calling-sdk-swift.git', 
    :tag => s.version.to_s 
  }

  # Platform Requirements
  s.ios.deployment_target = '13.0'
  s.swift_versions = ['5.0', '5.1', '5.2', '5.3', '5.4', '5.5']

  # Source Files Configuration
  s.source_files = 'Sources/**/*.swift'
  
  # Resource Files (if any)
  s.resource_bundles = {
    'XaviaCallingSDK' => ['Sources/Resources/*.xcprivacy']
  }

  # Dependencies
  s.dependency 'GoogleWebRTC', '~> 1.1'
  s.dependency 'Socket.IO-Client-Swift', '~> 16.1'
  
  # Frameworks and Libraries
  s.frameworks = 'Foundation', 'AVFoundation', 'AudioToolbox', 'CoreGraphics', 'CoreMedia', 'UIKit', 'VideoToolbox'
  s.libraries = 'c++'
  
  # Build Settings
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '-ObjC',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES',
    'ENABLE_BITCODE' => 'NO'
  }
  
  # Module Map for Objective-C Compatibility
  s.module_map = 'Sources/XaviaCallingSDK.modulemap'
  
  # Privacy Manifest (iOS 14+ requirement)
  s.info_plist = {
    'NSPrivacyAccessedAPITypes' => [
      {
        'NSPrivacyAccessedAPIType' => 'NSPrivacyAccessedAPICategoryFileTimestamp',
        'NSPrivacyAccessedAPITypeReasons' => ['C617.1']
      },
      {
        'NSPrivacyAccessedAPIType' => 'NSPrivacyAccessedAPICategorySystemBootTime',
        'NSPrivacyAccessedAPITypeReasons' => ['35F9.1']
      }
    ]
  }
  
  # Preserve paths for header files if needed
  s.preserve_paths = 'Sources/**/*'
end