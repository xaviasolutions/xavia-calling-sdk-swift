# WebRTC Calling SDK - Usage Guide

This guide walks you through the complete workflow of making and receiving calls using the Xavia WebRTC Calling SDK.

## Overview

The calling process involves the following steps:
1. Connect to the server
2. Retrieve list of online users
3. Select a caller and create a call
4. Handle incoming call notifications
5. Accept or reject calls
6. Join the call
7. Access local and remote media streams

---

## Step 1: Connect to the Server

First, initialize the WebRTC service and connect to the signaling server with your credentials.

```swift
import XaviaCallingSDK

let service = WebRTCService.shared

// Set up delegate to receive events
service.delegate = self

// Connect to server
service.connect(
    serverUrl: "https://your-server.com",
    userId: "user123",
    userName: "John Doe"
) { result in
    switch result {
    case .success:
        print("✅ Connected to server successfully")
    case .failure(let error):
        print("❌ Connection failed: \(error.localizedDescription)")
    }
}
```

### Implement WebRTCServiceDelegate

Create a class that conforms to `WebRTCServiceDelegate` to handle events:

```swift
extension YourViewController: WebRTCServiceDelegate {
    
    // Called when connection status changes
    func onConnectionChange(_ connected: Bool) {
        if connected {
            print("📱 Connected to server")
        } else {
            print("📱 Disconnected from server")
        }
    }
    
    // Called when an error occurs
    func onError(_ message: String) {
        print("⚠️ Error: \(message)")
        // Handle error - show alert to user
    }
}
```

---

## Step 2: Get List of Online Users

When you connect successfully, the server sends a list of currently online users. Implement the delegate method to receive this list:

```swift
extension YourViewController: WebRTCServiceDelegate {
    
    // Called when online users list is updated
    func onOnlineUsers(_ users: [[String: Any]]) {
        print("👥 Online users: \(users)")
        
        // Example structure:
        // [
        //   ["id": "user456", "name": "Jane Smith"],
        //   ["id": "user789", "name": "Bob Johnson"]
        // ]
        
        // Update your UI with available users
        self.availableUsers = users
        self.refreshUserList()
    }
}
```

---

## Step 3: Select a Caller and Create a Call

When the user selects someone to call, create a call on the server.

```swift
func initiateCall(targetUserId: String) {
    // Step 3a: Create a new call on server
    WebRTCService.shared.createCall(
        callType: "video",
        isGroup: false,
        maxParticipants: 2
    ) { result in
        switch result {
        case .success(let response):
            guard let callId = response["callId"] as? String else {
                print("❌ No callId in response")
                return
            }
            
            print("✅ Call created: \(callId)")
            
            // Step 3b: Send call invitation to target user
            self.sendCallInvitation(callId: callId, targetUserId: targetUserId)
            
        case .failure(let error):
            print("❌ Failed to create call: \(error.localizedDescription)")
        }
    }
}

func sendCallInvitation(callId: String, targetUserId: String) {
    WebRTCService.shared.sendCallInvitation(
        targetUserId: targetUserId,
        callId: callId,
        callType: "video"
    ) { result in
        switch result {
        case .success(let response):
            print("✅ Call invitation sent to \(targetUserId)")
        case .failure(let error):
            print("❌ Failed to send invitation: \(error.localizedDescription)")
        }
    }
}
```

---

## Step 4: Receive Incoming Call Notification

The receiver will be notified when they receive a call invitation:

```swift
extension YourViewController: WebRTCServiceDelegate {
    
    // Called when incoming call is received
    func onIncomingCall(_ data: [String: Any]) {
        print("📞 Incoming call received")
        
        // Example data structure:
        // [
        //   "callId": "call_xyz123",
        //   "callerId": "user456",
        //   "callerName": "Jane Smith",
        //   "callType": "video"
        // ]
        
        guard let callId = data["callId"] as? String,
              let callerId = data["callerId"] as? String,
              let callerName = data["callerName"] as? String else {
            return
        }
        
        // Show incoming call UI to user
        self.showIncomingCallUI(
            callId: callId,
            callerId: callerId,
            callerName: callerName
        )
    }
}

func showIncomingCallUI(callId: String, callerId: String, callerName: String) {
    // Display incoming call screen with Accept/Reject buttons
    // Store the callId and callerId for later use
    self.incomingCallId = callId
    self.incomingCallerId = callerId
    
    // Show UI alert or transition to incoming call screen
    let alert = UIAlertController(
        title: "Incoming Call",
        message: "\(callerName) is calling...",
        preferredStyle: .alert
    )
    
    alert.addAction(UIAlertAction(title: "Accept", style: .default) { _ in
        self.acceptIncomingCall()
    })
    
    alert.addAction(UIAlertAction(title: "Reject", style: .cancel) { _ in
        self.rejectIncomingCall()
    })
    
    self.present(alert, animated: true)
}
```

---

## Step 5: Accept or Reject the Call

Handle user's decision to accept or reject the call:

```swift
func acceptIncomingCall() {
    guard let callId = incomingCallId,
          let callerId = incomingCallerId else {
        print("❌ Missing call information")
        return
    }
    
    // Notify server of acceptance
    WebRTCService.shared.acceptCall(callId: callId, callerId: callerId)
    print("✅ Call accepted")
    
    // Proceed to Step 6: Join the call
    self.joinCall(callId: callId)
}

func rejectIncomingCall() {
    guard let callId = incomingCallId,
          let callerId = incomingCallerId else {
        print("❌ Missing call information")
        return
    }
    
    WebRTCService.shared.rejectCall(callId: callId, callerId: callerId)
    print("❌ Call rejected")
}
```

Listen for call acceptance on the caller side:

```swift
extension YourViewController: WebRTCServiceDelegate {
    
    // Called when the receiver accepts the call
    func onCallAccepted(_ data: [String: Any]) {
        print("✅ Call was accepted by receiver")
        
        guard let callId = data["callId"] as? String else { return }
        
        // Proceed to Step 6: Join the call
        self.joinCall(callId: callId)
    }
    
    // Called when the receiver rejects the call
    func onCallRejected(_ data: [String: Any]) {
        print("❌ Call was rejected")
        
        // Clean up UI, dismiss call screen
        self.dismissCallUI()
    }
}
```

---

## Step 6: Join the Call

Both caller and receiver join the call to establish the peer connection:

```swift
func joinCall(callId: String) {
    print("🚀 Joining call: \(callId)")
    
    // Step 6a: Request camera and microphone permissions
    WebRTCService.shared.getLocalMedia(constraints: [:]) { [weak self] result in
        switch result {
        case .success(let localStream):
            print("✅ Local media obtained")
            
            // Step 6b: Join the call on server
            WebRTCService.shared.joinCall(callId: callId) { result in
                switch result {
                case .success:
                    print("✅ Successfully joined call")
                    // Proceed to Step 7
                    
                case .failure(let error):
                    print("❌ Failed to join call: \(error.localizedDescription)")
                }
            }
            
        case .failure(let error):
            print("❌ Failed to get local media: \(error.localizedDescription)")
        }
    }
}
```

---

## Step 7: Access Local and Remote Media Streams

Now that you've joined the call, you can access the local video and remote participants' videos:

```swift
extension YourViewController: WebRTCServiceDelegate {
    
    // Called when your local media is ready
    func onLocalStream(_ stream: RTCMediaStream) {
        print("🎥 Local stream available")
        
        // Render local video to your preview view
        if let videoTrack = stream.videoTracks.first {
            self.localVideoView.renderFrame(videoTrack)
        }
    }
    
    // Called when a remote participant joins
    func onParticipantJoined(_ data: [String: Any]) {
        print("👤 Participant joined")
        
        guard let participantId = data["participantId"] as? String else { return }
        
        // Prepare remote video view for this participant
        self.prepareRemoteVideoView(for: participantId)
    }
    
    // Called when remote media stream is received
    func onRemoteStream(participantId: String, stream: RTCMediaStream) {
        print("📹 Remote stream received from \(participantId)")
        
        // Render remote video to participant's view
        if let videoTrack = stream.videoTracks.first {
            self.remoteVideoView.renderFrame(videoTrack)
        }
    }
    
    // Called when a participant leaves
    func onParticipantLeft(_ data: [String: Any]) {
        print("👤 Participant left")
        
        guard let participantId = data["participantId"] as? String else { return }
        
        // Remove remote video view
        self.removeRemoteVideoView(for: participantId)
    }
    
    // Called when remote stream is removed
    func onRemoteStreamRemoved(participantId: String) {
        print("📹 Remote stream removed from \(participantId)")
    }
}
```

---

## Step 8: Call Controls

While in a call, you can control audio and video:

```swift
// Toggle microphone
func toggleMicrophone(_ enabled: Bool) {
    WebRTCService.shared.toggleAudio(enabled: enabled)
    print("🎤 Microphone: \(enabled ? "ON" : "OFF")")
}

// Toggle camera
func toggleCamera(_ enabled: Bool) {
    WebRTCService.shared.toggleVideo(enabled: enabled)
    print("📹 Camera: \(enabled ? "ON" : "OFF")")
}

// Leave the call
func endCall() {
    WebRTCService.shared.leaveCall()
    print("👋 Left the call")
    
    // Dismiss call UI, return to main screen
    self.dismissCallUI()
}

// Disconnect from server
func disconnect() {
    WebRTCService.shared.disconnect()
    print("🔌 Disconnected from server")
}
```

---

## Complete Example Workflow

```swift
class CallViewController: UIViewController, WebRTCServiceDelegate {
    
    let service = WebRTCService.shared
    var currentCallId: String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        service.delegate = self
        
        // Step 1: Connect to server
        connectToServer()
    }
    
    // STEP 1: Connect
    func connectToServer() {
        service.connect(
            serverUrl: "https://your-server.com",
            userId: "user123",
            userName: "John Doe"
        ) { result in
            if case .success = result {
                print("✅ Connected")
            }
        }
    }
    
    // STEP 2: Receive online users
    func onOnlineUsers(_ users: [[String: Any]]) {
        print("Available users: \(users)")
    }
    
    // STEP 3: User selects caller
    @IBAction func callButtonTapped(_ sender: UIButton) {
        let targetUserId = "user456"
        initiateCall(targetUserId: targetUserId)
    }
    
    func initiateCall(targetUserId: String) {
        service.createCall(callType: "video") { result in
            guard case .success(let response) = result,
                  let callId = response["callId"] as? String else { return }
            
            self.currentCallId = callId
            
            service.sendCallInvitation(
                targetUserId: targetUserId,
                callId: callId,
                callType: "video"
            ) { _ in }
        }
    }
    
    // STEP 4: Receive incoming call
    func onIncomingCall(_ data: [String: Any]) {
        guard let callId = data["callId"] as? String else { return }
        self.currentCallId = callId
        showIncomingCallAlert()
    }
    
    func showIncomingCallAlert() {
        let alert = UIAlertController(
            title: "Incoming Call",
            message: "Someone is calling",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Accept", style: .default) { _ in
            self.acceptCall()
        })
        alert.addAction(UIAlertAction(title: "Reject", style: .cancel) { _ in
            self.rejectCall()
        })
        present(alert, animated: true)
    }
    
    // STEP 5: Accept call
    func acceptCall() {
        guard let callId = currentCallId else { return }
        service.acceptCall(callId: callId, callerId: "caller_id")
        joinCall()
    }
    
    // STEP 6 & 7: Join call and get streams
    func joinCall() {
        guard let callId = currentCallId else { return }
        
        service.getLocalMedia { result in
            if case .success = result {
                self.service.joinCall(callId: callId) { _ in }
            }
        }
    }
    
    func onLocalStream(_ stream: RTCMediaStream) {
        print("Local stream ready")
        // Display local video
    }
    
    func onRemoteStream(participantId: String, stream: RTCMediaStream) {
        print("Remote stream from \(participantId)")
        // Display remote video
    }
    
    // STEP 8: End call
    @IBAction func endCallButtonTapped(_ sender: UIButton) {
        service.leaveCall()
    }
}
```

---

## Error Handling

Always implement proper error handling:

```swift
func onError(_ message: String) {
    print("❌ Error: \(message)")
    
    // Show user-friendly error message
    let alert = UIAlertController(
        title: "Error",
        message: message,
        preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
}
```

---

## Summary

| Step | Action | Method |
|------|--------|--------|
| 1 | Connect to server | `connect(serverUrl:userId:userName:completion:)` |
| 2 | Get online users | `onOnlineUsers(_:)` delegate |
| 3 | Create call & send invitation | `createCall(...)` + `sendCallInvitation(...)` |
| 4 | Receive incoming call notification | `onIncomingCall(_:)` delegate |
| 5 | Accept/Reject call | `acceptCall(...)` / `rejectCall(...)` |
| 6 | Join the call | `joinCall(callId:completion:)` |
| 7 | Access media streams | `getLocalMedia(...)` + `onRemoteStream(_:_:)` delegate |
| 8 | Control call | `toggleAudio(...)`, `toggleVideo(...)`, `leaveCall()` |
