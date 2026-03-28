import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../shared/models/active_call_session.dart';

final webRtcCallControllerProvider =
    ChangeNotifierProvider<WebRtcCallController>((ref) {
  final controller = WebRtcCallController(ref.watch(firestoreProvider));
  ref.onDispose(controller.dispose);
  return controller;
});

class WebRtcCallController extends ChangeNotifier {
  WebRtcCallController(this._firestore);

  final FirebaseFirestore _firestore;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _candidateSubscription;

  bool _renderersReady = false;
  bool _busy = false;
  bool _muted = false;
  bool _speakerOn = true;
  bool _videoEnabled = false;
  bool _usingFrontCamera = true;
  String _boundCallId = '';
  String _boundUserId = '';
  String _boundDirection = '';
  String _error = '';
  bool _answerSubmitted = false;
  bool _offerSubmitted = false;
  bool _negotiating = false;
  final Set<String> _appliedCandidateIds = <String>{};

  bool get busy => _busy;
  bool get muted => _muted;
  bool get videoEnabled => _videoEnabled;
  bool get speakerOn => _speakerOn;
  bool get usingFrontCamera => _usingFrontCamera;
  bool get hasRemoteVideo => remoteRenderer.srcObject != null;
  bool get hasLocalVideo => localRenderer.srcObject != null;
  String get error => _error;

  Future<void> bindToSession({
    required ActiveCallSession session,
    required String currentUserId,
  }) async {
    if (session.callId.isEmpty || currentUserId.isEmpty) return;
    await _ensureRenderers();

    final sameCall =
        _boundCallId == session.callId && _boundUserId == currentUserId;
    if (!sameCall) {
      await _teardownConnection(resetRenderers: false);
      _boundCallId = session.callId;
      _boundUserId = currentUserId;
      _boundDirection = session.direction;
      _videoEnabled = session.type == 'video';
      await _prepareLocalStream();
      await _createPeerConnection();
      _listenToCallDocument(session);
      _listenToRemoteCandidates();
    } else {
      _videoEnabled = session.type == 'video';
      _setVideoTrackEnabled(_videoEnabled);
      notifyListeners();
    }

    await _maybeExchangeSdp(session);
  }

  Future<void> acceptIncomingCall({
    required ActiveCallSession session,
    required String currentUserId,
  }) async {
    await bindToSession(session: session, currentUserId: currentUserId);
    await _maybeExchangeSdp(session, forceAnswer: true);
  }

  Future<void> toggleMute() async {
    final stream = _localStream;
    if (stream == null) return;
    _muted = !_muted;
    for (final track in stream.getAudioTracks()) {
      track.enabled = !_muted;
    }
    notifyListeners();
  }

  Future<void> toggleVideo() async {
    _videoEnabled = !_videoEnabled;
    _setVideoTrackEnabled(_videoEnabled);
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    await Helper.setSpeakerphoneOn(_speakerOn);
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final stream = _localStream;
    if (stream == null) return;
    final videoTracks = stream.getVideoTracks();
    if (videoTracks.isEmpty) return;
    await Helper.switchCamera(videoTracks.first);
    _usingFrontCamera = !_usingFrontCamera;
    notifyListeners();
  }

  Future<void> showScreenShareUnavailable() async {
    _error = 'Compartir pantalla real todavia no esta disponible en Android.';
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_teardownConnection(resetRenderers: true));
    if (_renderersReady) {
      unawaited(localRenderer.dispose());
      unawaited(remoteRenderer.dispose());
      _renderersReady = false;
    }
    super.dispose();
  }

  Future<void> _ensureRenderers() async {
    if (_renderersReady) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersReady = true;
  }

  Future<void> _prepareLocalStream() async {
    _busy = true;
    _error = '';
    notifyListeners();
    try {
      _localStream?.dispose();
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': <String, dynamic>{
          'facingMode': 'user',
          'mandatory': <String, dynamic>{},
          'optional': <Map<String, dynamic>>[],
        },
      });
      _localStream = stream;
      localRenderer.srcObject = stream;
      await Helper.setSpeakerphoneOn(true);
      _setVideoTrackEnabled(_videoEnabled);
      _muted = false;
      _speakerOn = true;
      _usingFrontCamera = true;
    } catch (error) {
      _error =
          'No pudimos acceder al microfono/camara. ${error.toString().replaceFirst('Exception: ', '')}';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _createPeerConnection() async {
    final config = <String, dynamic>{
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };
    _peerConnection = await createPeerConnection(config);
    final connection = _peerConnection;
    final stream = _localStream;
    if (connection == null || stream == null) return;

    for (final track in stream.getTracks()) {
      await connection.addTrack(track, stream);
    }

    connection.onIceCandidate = (candidate) async {
      if (candidate.candidate == null || _boundCallId.isEmpty) return;
      final ownCollection = _boundDirection == 'outgoing'
          ? 'callerCandidates'
          : 'calleeCandidates';
      await _firestore
          .collection('calls')
          .doc(_boundCallId)
          .collection(ownCollection)
          .add({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
        'createdAt': FieldValue.serverTimestamp(),
      });
    };

    connection.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        remoteRenderer.srcObject = _remoteStream;
      }
      notifyListeners();
    };

    connection.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _error = 'La conexion de la llamada se interrumpio.';
      }
      notifyListeners();
    };
  }

  void _listenToCallDocument(ActiveCallSession session) {
    _callSubscription?.cancel();
    _callSubscription = _firestore
        .collection('calls')
        .doc(session.callId)
        .snapshots()
        .listen((snapshot) async {
      final data = snapshot.data();
      if (data == null) return;
      if ((data['status'] as String? ?? '') == 'ended') {
        await _teardownConnection(resetRenderers: false);
        notifyListeners();
        return;
      }
      final mergedSession = ActiveCallSession(
        id: session.id,
        callId: session.callId,
        contactId: session.contactId,
        contactName: session.contactName,
        contactUsername: session.contactUsername,
        contactPhoto: session.contactPhoto,
        type: data['type'] as String? ?? session.type,
        status: data['status'] as String? ?? session.status,
        direction: session.direction,
        screenSharing: data['screenSharing'] as bool? ?? session.screenSharing,
        startedAt: session.startedAt,
      );
      _videoEnabled = mergedSession.type == 'video';
      _setVideoTrackEnabled(_videoEnabled);
      await _maybeExchangeSdp(mergedSession);
      notifyListeners();
    });
  }

  void _listenToRemoteCandidates() {
    _candidateSubscription?.cancel();
    if (_boundCallId.isEmpty) return;
    final remoteCollection =
        _boundDirection == 'outgoing' ? 'calleeCandidates' : 'callerCandidates';
    _candidateSubscription = _firestore
        .collection('calls')
        .doc(_boundCallId)
        .collection(remoteCollection)
        .snapshots()
        .listen((snapshot) async {
      final connection = _peerConnection;
      if (connection == null) return;
      for (final doc in snapshot.docs) {
        if (_appliedCandidateIds.contains(doc.id)) continue;
        final data = doc.data();
        final candidate = data['candidate'] as String? ?? '';
        if (candidate.isEmpty) continue;
        await connection.addCandidate(
          RTCIceCandidate(
            candidate,
            data['sdpMid'] as String?,
            data['sdpMLineIndex'] as int?,
          ),
        );
        _appliedCandidateIds.add(doc.id);
      }
    });
  }

  Future<void> _maybeExchangeSdp(
    ActiveCallSession session, {
    bool forceAnswer = false,
  }) async {
    final connection = _peerConnection;
    if (connection == null || _boundCallId.isEmpty || _negotiating) return;
    _negotiating = true;
    try {
      final callDoc =
          await _firestore.collection('calls').doc(_boundCallId).get();
      final data = callDoc.data() ?? const <String, dynamic>{};

      if (session.direction == 'outgoing') {
        final existingOffer = data['offer'] as Map<String, dynamic>?;
        RTCSessionDescription? localDescription;
        try {
          localDescription = await connection.getLocalDescription();
        } catch (_) {
          localDescription = null;
        }
        if (!_offerSubmitted &&
            existingOffer == null &&
            localDescription == null) {
          try {
            final offer = await connection.createOffer();
            await connection.setLocalDescription(offer);
            await _firestore.collection('calls').doc(_boundCallId).set({
              'offer': {
                'type': offer.type,
                'sdp': offer.sdp,
              },
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            _offerSubmitted = true;
          } catch (error) {
            _error =
                'No pudimos iniciar la negociacion de la llamada. ${error.toString()}';
            notifyListeners();
            return;
          }
        }
        final answer = data['answer'] as Map<String, dynamic>?;
        RTCSessionDescription? remoteDescription;
        try {
          remoteDescription = await connection.getRemoteDescription();
        } catch (_) {
          remoteDescription = null;
        }
        if (answer != null &&
            remoteDescription == null &&
            (answer['sdp'] as String? ?? '').isNotEmpty) {
          await connection.setRemoteDescription(
            RTCSessionDescription(
              answer['sdp'] as String? ?? '',
              answer['type'] as String? ?? 'answer',
            ),
          );
        }
        return;
      }

      final offer = data['offer'] as Map<String, dynamic>?;
      if (offer == null || (offer['sdp'] as String? ?? '').isEmpty) {
        return;
      }
      RTCSessionDescription? remoteDescription;
      try {
        remoteDescription = await connection.getRemoteDescription();
      } catch (_) {
        remoteDescription = null;
      }
      if (remoteDescription == null) {
        await connection.setRemoteDescription(
          RTCSessionDescription(
            offer['sdp'] as String? ?? '',
            offer['type'] as String? ?? 'offer',
          ),
        );
      }
      if ((_boundDirection == 'incoming' && session.status == 'active') ||
          forceAnswer) {
        final existingAnswer = data['answer'] as Map<String, dynamic>?;
        RTCSessionDescription? localDescription;
        try {
          localDescription = await connection.getLocalDescription();
        } catch (_) {
          localDescription = null;
        }
        if (!_answerSubmitted &&
            existingAnswer == null &&
            localDescription == null) {
          try {
            final answer = await connection.createAnswer();
            await connection.setLocalDescription(answer);
            await _firestore.collection('calls').doc(_boundCallId).set({
              'answer': {
                'type': answer.type,
                'sdp': answer.sdp,
              },
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            _answerSubmitted = true;
          } catch (error) {
            _error = 'No pudimos responder la llamada. ${error.toString()}';
            notifyListeners();
          }
        }
      }
    } finally {
      _negotiating = false;
    }
  }

  void _setVideoTrackEnabled(bool enabled) {
    final stream = _localStream;
    if (stream == null) return;
    for (final track in stream.getVideoTracks()) {
      track.enabled = enabled;
    }
  }

  Future<void> _teardownConnection({required bool resetRenderers}) async {
    await _callSubscription?.cancel();
    await _candidateSubscription?.cancel();
    _callSubscription = null;
    _candidateSubscription = null;
    _appliedCandidateIds.clear();
    _offerSubmitted = false;
    _answerSubmitted = false;
    _negotiating = false;
    await _peerConnection?.close();
    _peerConnection = null;
    for (final track
        in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
      await track.stop();
    }
    await _localStream?.dispose();
    _localStream = null;
    await _remoteStream?.dispose();
    _remoteStream = null;
    if (resetRenderers) {
      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
    } else {
      remoteRenderer.srcObject = null;
    }
    _boundCallId = '';
    _boundUserId = '';
    _boundDirection = '';
    _muted = false;
    _speakerOn = true;
    _videoEnabled = false;
    _usingFrontCamera = true;
  }
}
