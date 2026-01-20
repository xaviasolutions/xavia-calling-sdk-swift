import Foundation
import WebRTC

/// Delegate protocol for WebRTCService events
@objc public protocol WebRTCServiceDelegate: AnyObject {
    
    /// Called when connection status changes
    /// - Parameter isConnected: True if connected to signaling server
    @objc optional func webRTCService(_ service: WebRTCService, connectionStatusChanged isConnected: Bool)
    
    /// Called when local media stream is available
    /// - Parameter localStream: The local media stream
    @objc optional func webRTCService(_ service: WebRTCService, didReceiveLocalStream localStream: RTCMediaStream)
    
    /// Called when remote media stream is added
    /// - Parameters:
    ///   - participantId: ID of the remote participant
    ///   - remoteStream: The remote media stream
    @objc optional func webRTCService(_ service: WebRTCService, didAddRemoteStream remoteStream: RTCMediaStream, forParticipant participantId: String)
    
    /// Called when remote media stream is removed
    /// - Parameter participantId: ID of the remote participant
    @objc optional func webRTCService(_ service: WebRTCService, didRemoveRemoteStreamForParticipant participantId: String)
    
    /// Called when list of online users is received
    /// - Parameter users: Array of online users
    @objc optional func webRTCService(_ service: WebRTCService, didReceiveOnlineUsers users: [OnlineUser])
    
    /// Called when receiving an incoming call
    /// - Parameter callData: Information about the incoming call
    @objc optional func webRTCService(_ service: WebRTCService, didReceiveIncomingCall callData: IncomingCallData)
    
    /// Called when a call is accepted by remote party
    /// - Parameter data: Call acceptance data
    @objc optional func webRTCService(_ service: WebRTCService, callWasAccepted data: CallAcceptedData)
    
    /// Called when a call is rejected by remote party
    /// - Parameter data: Call rejection data
    @objc optional func webRTCService(_ service: WebRTCService, callWasRejected data: CallRejectedData)
    
    /// Called when a new participant joins the call
    /// - Parameter data: Participant data
    @objc optional func webRTCService(_ service: WebRTCService, participantDidJoin data: ParticipantData)
    
    /// Called when a participant leaves the call
    /// - Parameter data: Participant left data
    @objc optional func webRTCService(_ service: WebRTCService, participantDidLeave data: ParticipantLeftData)
    
    /// Called when an error occurs
    /// - Parameter error: Error description
    @objc optional func webRTCService(_ service: WebRTCService, didEncounterError error: String)
    
    /// Called when call is created successfully
    /// - Parameter response: Call creation response
    @objc optional func webRTCService(_ service: WebRTCService, didCreateCall response: CreateCallResponse)
    
    /// Called when call is joined successfully
    /// - Parameter response: Call join response
    @objc optional func webRTCService(_ service: WebRTCService, didJoinCall response: JoinCallResponse)
    
    /// Called when ICE connection state changes
    @objc optional func webRTCService(_ service: WebRTCService, iceConnectionStateDidChange state: RTCIceConnectionState, forParticipant participantId: String)
    
    /// Called when signaling state changes
    @objc optional func webRTCService(_ service: WebRTCService, signalingStateDidChange state: RTCSignalingState)
    
    /// Called when peer connection is established
    @objc optional func webRTCService(_ service: WebRTCService, didEstablishPeerConnectionWithParticipant participantId: String)
    
    /// Called when media track status changes
    @objc optional func webRTCService(_ service: WebRTCService, mediaTrack: RTCMediaStreamTrack, didChangeStatus isEnabled: Bool)
}

/// Convenience extension to handle multiple delegates
extension WebRTCService {
    
    /// Add a delegate to receive events
    /// - Parameter delegate: The delegate to add
    public func addDelegate(_ delegate: WebRTCServiceDelegate) {
        delegates.add(delegate)
    }
    
    /// Remove a delegate
    /// - Parameter delegate: The delegate to remove
    public func removeDelegate(_ delegate: WebRTCServiceDelegate) {
        delegates.remove(delegate)
    }
    
    /// Notify all delegates about connection status change
    internal func notifyConnectionStatusChanged(_ isConnected: Bool) {
        delegates.allObjects.forEach { delegate in
            (delegate as? WebRTCServiceDelegate)?.webRTCService?(self, connectionStatusChanged: isConnected)
        }
    }
    
    /// Notify all delegates about local stream
    internal func notifyLocalStreamReceived(_ stream: RTCMediaStream) {
        delegates.allObjects.forEach { delegate in
            (delegate as? WebRTCServiceDelegate)?.webRTCService?(self, didReceiveLocalStream: stream)
        }
    }
    
    /// Notify all delegates about remote stream added
    internal func notifyRemoteStreamAdded(_ stream: RTCMediaStream, forParticipant participantId: String) {
        delegates.allObjects.forEach { delegate in
            (delegate as? WebRTCServiceDelegate)?.webRTCService?(self, didAddRemoteStream: stream, forParticipant: participantId)
        }
    }
    
    /// Notify all delegates about remote stream removed
    internal func notifyRemoteStreamRemoved(forParticipant participantId: String) {
        delegates.allObjects.forEach { delegate in
            (delegate as? WebRTCServiceDelegate)?.webRTCService?(self, didRemoveRemoteStreamForParticipant: participantId)
        }
    }
    
    /// Notify all delegates about online users
    internal func notifyOnlineUsersReceived(_ users: [OnlineUser]) {
        delegates.allObjects.forEach { delegate in
            (delegate as? WebRTCServiceDelegate)?.webRTCService?(self, didReceiveOnlineUsers: users)
        }
    }
    
    /// Notify all delegates about incoming call
    internal func notifyIncomingCallReceived(_ callData: IncomingCallData) {
        delegates.allObjects.forEach { delegate in
            (delegate as? WebRTCServiceDelegate)?.webRTCService?(self, didReceiveIncomingCall: callData)
        }
    }
    
    /// Notify all delegates about call accepted
    internal func notifyCallAccepted(_ data: CallAcceptedData) {
        delegates.allObjects.forEach { delegate in
            (delegate as? WebRTCServiceDelegate)?.webRTCService?(self, callWasAccepted: data)
        }
    }
    
    /// Notify all delegates about call rejected
    internal func notifyCallRejected(_ data: CallRejectedData) {
        delegates.allObjects.forEach { delegate in
            (delegate as? WebRTCServiceDelegate)?.webRTCService?(self, callWasRejected: data)
        }
    }
    
    /// Notify all delegates about participant joined
    internal func notifyParticipantJoined(_ data: ParticipantData) {
        delegates.allObjects.forEach { delegate in
            (delegate as? WebRTCServiceDelegate)?.webRTCService?(self, participantDidJoin: data)
        }
    }
    
    /// Notify all delegates about participant left
    internal func notifyParticipantLeft(_ data: ParticipantLeftData) {
        delegates.allObjects.forEach { delegate in
            (delegate as? WebRTCServiceDelegate)?.webRTCService?(self, participantDidLeave: data)
        }
    }
    
    /// Notify all delegates about error
    internal func notifyErrorOccurred(_ error: String) {
        delegates.allObjects.forEach { delegate in
            (delegate as? WebRTCServiceDelegate)?.webRTCService?(self, didEncounterError: error)
        }
    }
    
    /// Notify all delegates about call created
    internal func notifyCallCreated(_ response: CreateCallResponse) {
        delegates.allObjects.forEach { delegate in
            (delegate as? WebRTCServiceDelegate)?.webRTCService?(self, didCreateCall: response)
        }
    }
    
    /// Notify all delegates about call joined
    internal func notifyCallJoined(_ response: JoinCallResponse) {
        delegates.allObjects.forEach { delegate in
            (delegate as? WebRTCServiceDelegate)?.webRTCService?(self, didJoinCall: response)
        }
    }
    
    /// Notify all delegates about ICE connection state change
    internal func notifyIceConnectionStateChanged(_ state: RTCIceConnectionState, forParticipant participantId: String) {
        delegates.allObjects.forEach { delegate in
            (delegate as? WebRTCServiceDelegate)?.webRTCService?(self, iceConnectionStateDidChange: state, forParticipant: participantId)
        }
    }
    
    /// Notify all delegates about signaling state change
    internal func notifySignalingStateChanged(_ state: RTCSignalingState) {
        delegates.allObjects.forEach { delegate in
            (delegate as? WebRTCServiceDelegate)?.webRTCService?(self, signalingStateDidChange: state)
        }
    }
    
    /// Notify all delegates about peer connection established
    internal func notifyPeerConnectionEstablished(forParticipant participantId: String) {
        delegates.allObjects.forEach { delegate in
            (delegate as? WebRTCServiceDelegate)?.webRTCService?(self, didEstablishPeerConnectionWithParticipant: participantId)
        }
    }
}

// MARK: - Delegate Management
extension WebRTCService {
    
    // Add this property to WebRTCService class
    internal let delegates = NSHashTable<AnyObject>.weakObjects()
    
    // Update the callback setters to use delegates
    internal func setupDelegateCallbacks() {
        self.onConnectionChange = { [weak self] isConnected in
            self?.notifyConnectionStatusChanged(isConnected)
        }
        
        self.onLocalStream = { [weak self] stream in
            self?.notifyLocalStreamReceived(stream)
        }
        
        self.onRemoteStream = { [weak self] participantId, stream in
            self?.notifyRemoteStreamAdded(stream, forParticipant: participantId)
        }
        
        self.onRemoteStreamRemoved = { [weak self] participantId in
            self?.notifyRemoteStreamRemoved(forParticipant: participantId)
        }
        
        self.onOnlineUsers = { [weak self] users in
            self?.notifyOnlineUsersReceived(users)
        }
        
        self.onIncomingCall = { [weak self] callData in
            self?.notifyIncomingCallReceived(callData)
        }
        
        self.onCallAccepted = { [weak self] data in
            self?.notifyCallAccepted(data)
        }
        
        self.onCallRejected = { [weak self] data in
            self?.notifyCallRejected(data)
        }
        
        self.onParticipantJoined = { [weak self] data in
            self?.notifyParticipantJoined(data)
        }
        
        self.onParticipantLeft = { [weak self] data in
            self?.notifyParticipantLeft(data)
        }
        
        self.onError = { [weak self] error in
            self?.notifyErrorOccurred(error)
        }
    }
}