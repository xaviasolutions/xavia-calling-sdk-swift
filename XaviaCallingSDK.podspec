Pod::Spec.new do |spec|
  spec.name         = 'XaviaCallingSDK'
  spec.version      = '1.0.0'
  spec.summary      = 'Native iOS WebRTC calling SDK for Xavia'
  spec.description  = <<-DESC
    XaviaCallingSDK is a production-ready, service-only iOS native SDK for WebRTC-based calling.
    It provides complete peer-to-peer and group calling functionality with automatic dependency management.
    Features include socket.io signaling, WebRTC peer connections, local/remote stream management,
    and full call lifecycle control.
  DESC

  spec.homepage     = 'https://github.com/xaviasolutions/xavia-calling-sdk-swift'
  spec.license      = { :type => 'MIT', :file => 'LICENSE' }
  spec.author       = { 'Xavia' => 'shaheer@xaviasolutions.com' }
  
  spec.platform     = :ios, '12.0'
  spec.swift_version = '5.0'
  
  spec.source       = { :git => 'https://github.com/xaviasolutions/xavia-calling-sdk-swift.git', :tag => spec.version.to_s }
  spec.source_files = 'XaviaCallingSDK-Swift/**/*.swift'
  
  spec.frameworks   = 'Foundation', 'AVFoundation', 'CoreVideo', 'VideoToolbox', 'CoreMedia', 'CoreTelephony', 'GLKit'
  
  spec.dependency 'WebRTC', '~> 63.11'
  spec.dependency 'Socket.IO-Client-Swift', '~> 16.0'
  
  spec.requires_arc = true
end
