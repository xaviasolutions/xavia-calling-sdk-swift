import { io } from 'socket.io-client';
import { mediaDevices, RTCIceCandidate, RTCPeerConnection, RTCSessionDescription, RCTView } from 'react-native-webrtc'

/**
 * WebRTC Service - Complete implementation matching backend
 * Handles all WebRTC signaling, peer connections, and media streams
 */
class WebRTCService {
  constructor() {
    this.socket = null;
    this.peerConnections = new Map(); // participantId -> RTCPeerConnection
    this.localStream = null;
    this.remoteStreams = new Map(); // participantId -> MediaStream
    this.currentCallId = null;
    this.currentParticipantId = null;
    this.userId = null;
    this.userName = null;
    this.iceServers = null;

    // Event callbacks
    this.onConnectionChange = null;
    this.onLocalStream = null;
    this.onRemoteStream = null;
    this.onRemoteStreamRemoved = null;
    this.onOnlineUsers = null;
    this.onIncomingCall = null;
    this.onCallAccepted = null;
    this.onCallRejected = null;
    this.onParticipantJoined = null;
    this.onParticipantLeft = null;
    this.onError = null;
    this.baseUrl = null
  }

  /**
   * Initialize connection to backend
   */
  async connect(serverUrl, userId, userName) {
    this.baseUrl = serverUrl
    // Validate inputs
    if (!userName || !userName.trim()) {
      throw new Error('Username is required');
    }

    // If already connected with same user, don't reconnect
    if (this.socket && this.socket.connected && this.userId === userId) {
      console.log('⚠️ Already connected, skipping reconnection');
      return Promise.resolve();
    }

    // Disconnect existing connection if different user
    if (this.socket && this.userId !== userId) {
      console.log('🔄 Disconnecting previous connection');
      this.disconnect();
    }

    return new Promise((resolve, reject) => {
      try {
        this.userId = userId;
        this.userName = userName.trim();

        console.log(`🔌 Connecting to server: ${serverUrl}`);

        this.socket = io(serverUrl, {
          transports: ['websocket', 'polling'],
          reconnection: true,
          reconnectionAttempts: 5,
          reconnectionDelay: 1000,
          timeout: 20000
        });

        this.socket.on('connect', () => {
          console.log('✅ Socket connected:', this.socket.id);

          // Register user
          this.socket.emit('register-user', { userId, userName: this.userName });

          if (this.onConnectionChange) {
            this.onConnectionChange(true);
          }

          resolve();
        });

        this.socket.on('disconnect', () => {
          console.log('❌ Socket disconnected');
          if (this.onConnectionChange) {
            this.onConnectionChange(false);
          }
        });

        this.socket.on('connect_error', (error) => {
          console.error('Connection error:', error);
          if (this.onError) {
            this.onError('Connection failed: ' + error.message);
          }
          reject(error);
        });

        // Setup event listeners
        this.setupSocketListeners();

      } catch (error) {
        console.error('Connect error:', error);
        reject(error);
      }
    });
  }

  /**
   * Setup all socket event listeners
   */
  setupSocketListeners() {
    // Online users list
    this.socket.on('users-online', (users) => {
      console.log('📢 Online users:', users.length);
      if (this.onOnlineUsers) {
        this.onOnlineUsers(users);
      }
    });

    // Incoming call invitation
    this.socket.on('incoming-call', (data) => {
      console.log('📞 Incoming call from:', data.callerName);
      if (this.onIncomingCall) {
        this.onIncomingCall(data);
      }
    });

    // Call accepted
    this.socket.on('call-accepted', (data) => {
      console.log('✅ Call accepted by:', data.acceptedByName);
      if (this.onCallAccepted) {
        this.onCallAccepted(data);
      }
    });

    // Call rejected
    this.socket.on('call-rejected', (data) => {
      console.log('❌ Call rejected by:', data.rejectedByName);
      if (this.onCallRejected) {
        this.onCallRejected(data);
      }
    });

    // Call joined successfully
    this.socket.on('call-joined', async (data) => {
      console.log('✅ Joined call:', data.callId);
      console.log('Other participants:', data.participants);

      this.iceServers = data.iceServers;

      // Create peer connections for existing participants
      for (const participant of data.participants) {
        await this.createPeerConnection(participant.id, true);
      }
    });

    // New participant joined
    this.socket.on('participant-joined', async (data) => {
      console.log('👤 Participant joined:', data.userName);
      if (data.participantId !== this.currentParticipantId) {
        await this.createPeerConnection(data.participantId, false);
      }

      if (this.onParticipantJoined) {
        this.onParticipantJoined(data);
      }
    });

    // Participant left
    this.socket.on('participant-left', (data) => {
      console.log('👋 Participant left:', data.participantId);
      this.removePeerConnection(data.participantId);

      if (this.onParticipantLeft) {
        this.onParticipantLeft(data);
      }
    });

    // WebRTC signaling
    this.socket.on('signal', async (data) => {
      await this.handleSignal(data);
    });

    // Error handling
    this.socket.on('error', (data) => {
      console.error('❌ Server error:', data.message);
      if (this.onError) {
        this.onError(data.message);
      }
    });
  }

  /**
   * Create a new call
   */
  async createCall(callType = 'video', isGroup = false, maxParticipants = 1000) {
    try {
      const serverUrl = this.baseUrl;
      const response = await fetch(`${serverUrl}/api/calls`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ callType, isGroup, maxParticipants })
      });

      const data = await response.json();

      if (!data.success) {
        throw new Error(data.error || 'Failed to create call');
      }

      console.log('✅ Call created:', data.callId);
      this.iceServers = data.config.iceServers;

      return data;
    } catch (error) {
      console.error('Create call error:', error);
      throw error;
    }
  }

  /**
   * Join an existing call
   */
  async joinCall(callId) {
    try {
      const serverUrl = this.baseUrl;
      console.log({ serverUrl }, "from the sdk file")
      const createCallUrl = `${serverUrl}/api/calls/${callId}/join`
      console.log({ createCallUrl })
      const response = await fetch(createCallUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          userName: this.userName,
          userId: this.userId
        })
      });

      const data = await response.json();

      if (!data.success) {
        throw new Error(data.error || 'Failed to join call');
      }

      console.log('✅ Joined call via API:', data.callId);

      this.currentCallId = data.callId;
      this.currentParticipantId = data.participantId;
      this.iceServers = data.config.iceServers;

      // Get local media
      await this.getLocalMedia();

      // Join via socket
      this.socket.emit('join-call', {
        callId: data.callId,
        participantId: data.participantId,
        userName: this.userName
      });

      return data;
    } catch (error) {
      console.error('Join call error:', error);
      throw error;
    }
  }

  /**
   * Get local media stream
   */
  async getLocalMedia(constraints = {}) {
    try {
      const defaultConstraints = {
        video: {
          width: { min: 640, ideal: 1280, max: 1920 },
          height: { min: 480, ideal: 720, max: 1080 },
          frameRate: { ideal: 30, max: 60 }
        },
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true
        }
      };

      const finalConstraints = { ...defaultConstraints, ...constraints };

      console.log('🎥 Getting local media...');

      this.localStream = await mediaDevices.getUserMedia(finalConstraints);

      console.log('✅ Local media obtained');

      if (this.onLocalStream) {
        this.onLocalStream(this.localStream);
      }

      return this.localStream;
    } catch (error) {
      console.error('Get local media error:', error);
      throw error;
    }
  }

  /**
   * Create peer connection
   */
  async createPeerConnection(participantId, isInitiator) {
    try {
      console.log(`🔗 Creating peer connection with ${participantId}, initiator: ${isInitiator}`);

      const config = {
        iceServers: this.iceServers || [
          { urls: 'stun:stun.l.google.com:19302' }
        ]
      };

      const pc = new RTCPeerConnection(config);
      this.peerConnections.set(participantId, pc);

      // Add local stream tracks
      if (this.localStream) {
        this.localStream.getTracks().forEach(track => {
          pc.addTrack(track, this.localStream);
          console.log('➕ Added local track:', track.kind);
        });
      }

      // Handle ICE candidates
      pc.onicecandidate = (event) => {
        if (event.candidate) {
          console.log('📡 Sending ICE candidate to', participantId);
          this.socket.emit('signal', {
            callId: this.currentCallId,
            targetId: participantId,
            signal: {
              candidate: event.candidate.candidate,
              sdpMid: event.candidate.sdpMid,
              sdpMLineIndex: event.candidate.sdpMLineIndex
            },
            type: 'ice-candidate'
          });
        }
      };

      // Handle remote stream
      pc.ontrack = (event) => {
        console.log('📥 Received remote track from', participantId);
        const [remoteStream] = event.streams;
        this.remoteStreams.set(participantId, remoteStream);

        if (this.onRemoteStream) {
          this.onRemoteStream(participantId, remoteStream);
        }
      };

      // Handle connection state
      pc.onconnectionstatechange = () => {
        console.log(`Connection state with ${participantId}:`, pc.connectionState);
      };

      pc.oniceconnectionstatechange = () => {
        console.log(`ICE connection state with ${participantId}:`, pc.iceConnectionState);
      };

      // If initiator, create and send offer
      if (isInitiator) {
        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);

        console.log('📤 Sending offer to', participantId);
        this.socket.emit('signal', {
          callId: this.currentCallId,
          targetId: participantId,
          signal: { sdp: offer.sdp, type: offer.type },
          type: 'offer'
        });
      }

      return pc;
    } catch (error) {
      console.error('Create peer connection error:', error);
      throw error;
    }
  }

  /**
   * Handle incoming signals
   */
  async handleSignal(data) {
    const { fromId, signal, type } = data;

    console.log(`📡 Received signal from ${fromId}:`, type);

    let pc = this.peerConnections.get(fromId);

    // Create peer connection if doesn't exist
    if (!pc) {
      pc = await this.createPeerConnection(fromId, false);
    }

    try {
      if (type === 'offer') {
        await pc.setRemoteDescription(new RTCSessionDescription({
          type: signal.type,
          sdp: signal.sdp
        }));

        const answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);

        console.log('📤 Sending answer to', fromId);
        this.socket.emit('signal', {
          callId: this.currentCallId,
          targetId: fromId,
          signal: { sdp: answer.sdp, type: answer.type },
          type: 'answer'
        });
      } else if (type === 'answer') {
        await pc.setRemoteDescription(new RTCSessionDescription({
          type: signal.type,
          sdp: signal.sdp
        }));
      } else if (type === 'ice-candidate') {
        if (signal.candidate) {
          await pc.addIceCandidate(new RTCIceCandidate({
            candidate: signal.candidate,
            sdpMid: signal.sdpMid,
            sdpMLineIndex: signal.sdpMLineIndex
          }));
        }
      }
    } catch (error) {
      console.error('Handle signal error:', error);
    }
  }

  /**
   * Remove peer connection
   */
  removePeerConnection(participantId) {
    const pc = this.peerConnections.get(participantId);
    if (pc) {
      pc.close();
      this.peerConnections.delete(participantId);
    }

    const stream = this.remoteStreams.get(participantId);
    if (stream) {
      this.remoteStreams.delete(participantId);
      if (this.onRemoteStreamRemoved) {
        this.onRemoteStreamRemoved(participantId);
      }
    }
  }

  /**
   * Send call invitation
   */
  sendCallInvitation(targetUserId, callId, callType) {
    return new Promise((resolve, reject) => {
      this.socket.emit('send-call-invitation', {
        targetUserId,
        callId,
        callType,
        callerId: this.userId,
        callerName: this.userName
      }, (response) => {
        if (response.success) {
          resolve(response);
        } else {
          reject(new Error(response.error));
        }
      });
    });
  }

  /**
   * Accept incoming call
   */
  acceptCall(callId, callerId) {
    this.socket.emit('accept-call', { callId, callerId });
  }

  /**
   * Reject incoming call
   */
  rejectCall(callId, callerId) {
    this.socket.emit('reject-call', { callId, callerId });
  }

  /**
   * Leave current call
   */
  leaveCall() {
    if (this.currentCallId) {
      console.log('👋 Leaving call:', this.currentCallId);

      this.socket.emit('leave-call', {
        callId: this.currentCallId,
        reason: 'left'
      });

      // Close all peer connections
      this.peerConnections.forEach((pc) => pc.close());
      this.peerConnections.clear();
      this.remoteStreams.clear();

      // Stop local stream
      if (this.localStream) {
        this.localStream.getTracks().forEach(track => track.stop());
        this.localStream = null;
      }

      this.currentCallId = null;
      this.currentParticipantId = null;
    }
  }

  /**
   * Toggle audio
   */
  toggleAudio(enabled) {
    if (this.localStream) {
      this.localStream.getAudioTracks().forEach(track => {
        track.enabled = enabled;
      });
      console.log('🎤 Audio:', enabled ? 'enabled' : 'disabled');
    }
  }

  /**
   * Toggle video
   */
  toggleVideo(enabled) {
    if (this.localStream) {
      this.localStream.getVideoTracks().forEach(track => {
        track.enabled = enabled;
      });
      console.log('📹 Video:', enabled ? 'enabled' : 'disabled');
    }
  }

  /**
   * Disconnect from server
   */
  disconnect() {
    this.leaveCall();
    if (this.socket) {
      this.socket.disconnect();
      this.socket = null;
    }
  }
}

export default new WebRTCService();
