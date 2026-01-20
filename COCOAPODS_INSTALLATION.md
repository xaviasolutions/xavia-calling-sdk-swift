# XaviaCallingSDK - CocoaPods Installation Guide

## Requirements

- iOS 13.0+
- Xcode 14.0+
- CocoaPods 1.10.0+
- Swift 5.9+

## Installation

### Step 1: Install CocoaPods (if not already installed)

```bash
sudo gem install cocoapods
```

### Step 2: Create Podfile

Navigate to your Xcode project directory and create a `Podfile`:

```bash
cd /path/to/your/project
pod init
```

### Step 3: Add XaviaCallingSDK to Podfile

Open your `Podfile` and add:

```ruby
platform :ios, '13.0'
use_frameworks!

target 'YourAppTarget' do
  pod 'XaviaCallingSDK', :git => 'https://github.com/xaviasolutions/xavia-calling-sdk-swift.git', :branch => 'v3'
end
```

### Step 4: Install Dependencies

```bash
pod install
```

### Step 5: Open Workspace

```bash
open YourApp.xcworkspace
```

**Important**: Always use the `.xcworkspace` file, not `.xcodeproj` after CocoaPods installation.

## Updating the SDK

To update to the latest version:

```bash
pod update XaviaCallingSDK
```

## Usage

After installation, import and use the SDK:

```swift
import XaviaCallingSDK

class ViewController: UIViewController {
    let sdk = XaviaCallingSDK.shared
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Initialize SDK
        Task {
            try await sdk.initialize(
                serverUrl: "wss://your-server.com",
                userId: "user@example.com",
                userName: "John Doe"
            )
        }
    }
}
```

## Troubleshooting

### Issue: "Unable to find a specification for XaviaCallingSDK"

**Solution**: Make sure you're pointing to the correct git repository:

```ruby
pod 'XaviaCallingSDK', :git => 'https://github.com/xaviasolutions/xavia-calling-sdk-swift.git', :branch => 'v3'
```

### Issue: "The platform of the target is not compatible"

**Solution**: Ensure your deployment target is iOS 13.0 or higher:

```ruby
platform :ios, '13.0'
```

### Issue: Build errors with GoogleWebRTC

**Solution**: Clean and rebuild:

```bash
pod deintegrate
pod install
```

Then in Xcode:
1. Product → Clean Build Folder (Cmd+Shift+K)
2. Product → Build (Cmd+B)

### Issue: "Module 'XaviaCallingSDK' not found"

**Solution**: 
1. Make sure you opened the `.xcworkspace` file, not `.xcodeproj`
2. Clean and rebuild the project
3. Check that the pod was successfully installed:

```bash
pod list | grep XaviaCallingSDK
```

### Issue: Swift version compatibility

The SDK requires Swift 5.9+. Add to your `Podfile`:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['SWIFT_VERSION'] = '5.9'
    end
  end
end
```

## Complete Podfile Example

Here's a complete example `Podfile`:

```ruby
platform :ios, '13.0'
use_frameworks!
inhibit_all_warnings!

target 'MyCallingApp' do
  # XaviaCallingSDK
  pod 'XaviaCallingSDK', :git => 'https://github.com/xaviasolutions/xavia-calling-sdk-swift.git', :branch => 'v3'
  
  # Other pods
  # pod 'Alamofire', '~> 5.8'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['SWIFT_VERSION'] = '5.9'
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
    end
  end
end
```

## Verifying Installation

After installation, verify the SDK is available:

1. Build your project (Cmd+B)
2. Try importing:

```swift
import XaviaCallingSDK

print(XaviaCallingSDK.shared)  // Should not error
```

## Dependencies

The SDK automatically installs these dependencies via CocoaPods:

- **GoogleWebRTC** (~> 1.1.31999) - WebRTC framework
- **Socket.IO-Client-Swift** (~> 16.0) - WebSocket client

No manual configuration needed!

## Next Steps

1. ✅ SDK installed via CocoaPods
2. 📖 Read [GETTING_STARTED.md](GETTING_STARTED.md) for quick tutorial
3. 💡 Check [EXAMPLES.md](EXAMPLES.md) for code samples
4. 📚 Reference [API_REFERENCE.md](API_REFERENCE.md) for complete API docs

## Alternative: Swift Package Manager

If you prefer SPM over CocoaPods, see [README.md](README.md) for Swift Package Manager installation instructions.

## Support

For issues:
- Check [README.md](README.md) troubleshooting section
- Review [IMPLEMENTATION.md](IMPLEMENTATION.md) for architecture details
- Enable console logging to see detailed SDK events

---

**Status**: ✅ CocoaPods Support Added
**Version**: 1.0.0
**Last Updated**: January 20, 2024
