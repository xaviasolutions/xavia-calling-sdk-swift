# XaviaCallingSDK Installation Methods

## Quick Start

Choose one of the installation methods below based on your needs.

---

## 1. Git Repository Installation (Recommended)

If you want to use the SDK from GitHub directly (no CocoaPods Trunk publication needed):

### In your `Podfile`:
```ruby
target 'YourApp' do
  pod 'XaviaCallingSDK', :git => 'https://github.com/xaviasolutions/xavia-calling-sdk-swift.git'
end
```

### Install:
```bash
pod install
```

This method works immediately and is perfect for:
- ✅ Private repositories
- ✅ Team development
- ✅ CI/CD pipelines
- ✅ Early distribution

---

## 2. Local Path Installation (Development)

For testing locally during development:

### In your `Podfile`:
```ruby
target 'YourApp' do
  pod 'XaviaCallingSDK', :path => '../XaviaCallingSDK'
end
```

### Install:
```bash
pod install
```

This method is useful for:
- ✅ Local development
- ✅ Testing changes before pushing
- ✅ Debugging

---

## Troubleshooting

### Error: "Unable to find a pod with name XaviaCallingSDK"
**Solution**: Use the Git method or publish to CocoaPods Trunk first.

### Error: "Source not available"
**Solution**: Ensure the GitHub URL is correct and you have access to the repository.

### Error: "Invalid podspec"
**Solution**: Run validation first:
```bash
pod spec lint XaviaCallingSDK.podspec
```

---

## Recommended Setup for Your Team

```ruby
# Podfile
platform :ios, '12.0'

target 'YourApp' do
  # Use Git method for team development
  pod 'XaviaCallingSDK', :git => 'https://github.com/xaviasolutions/xavia-calling-sdk-swift.git', :branch => 'main'
  
  # Or pin to a specific version tag
  # pod 'XaviaCallingSDK', :git => 'https://github.com/xaviasolutions/xavia-calling-sdk-swift.git', :tag => '1.0.0'
end
```

Then:
```bash
pod install
pod update
```

---

## What Gets Installed

Regardless of the installation method, CocoaPods will automatically install:
- ✅ GoogleWebRTC
- ✅ Socket.IO-Client-Swift
- ✅ All required iOS frameworks

No additional steps needed!
