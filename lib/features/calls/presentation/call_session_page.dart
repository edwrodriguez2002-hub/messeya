import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/user_avatar.dart';
import '../data/calls_repository.dart';
import '../data/web_rtc_call_controller.dart';

class CallSessionPage extends ConsumerStatefulWidget {
  const CallSessionPage({
    super.key,
    required this.userId,
  });

  final String userId;

  @override
  ConsumerState<CallSessionPage> createState() => _CallSessionPageState();
}

class _CallSessionPageState extends ConsumerState<CallSessionPage> {
  String _lastBoundCallId = '';
  String _lastBindSignature = '';

  String _buildStatusText({
    required bool isRinging,
    required bool isVideo,
    required String direction,
    required String status,
    required DateTime? startedAt,
    required String error,
  }) {
    if (error.isNotEmpty) return error;
    if (status == 'rejected') {
      return direction == 'incoming' ? 'Llamada rechazada' : 'No contestaron';
    }
    if (status == 'ended') {
      return direction == 'incoming'
          ? 'Llamada finalizada'
          : 'Llamada terminada';
    }
    if (isRinging) {
      return direction == 'incoming' ? 'Llamada entrante' : 'Llamando...';
    }
    if (startedAt != null) {
      final elapsed = DateTime.now().difference(startedAt);
      final minutes =
          elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
      final seconds =
          elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
      final hours = elapsed.inHours;
      if (hours > 0) {
        return '$hours:$minutes:$seconds';
      }
      return '$minutes:$seconds';
    }
    return isVideo ? 'Videollamada activa' : 'Llamada activa';
  }

  String _buildAuxText({
    required String type,
    required String status,
    required DateTime? startedAt,
  }) {
    if (status == 'active' && startedAt != null) {
      return 'Iniciada ${DateFormat('h:mm a').format(startedAt)}';
    }
    return type == 'video' ? 'Videollamada segura' : 'Llamada segura';
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeCallSessionProvider(widget.userId));
    final controller = ref.watch(webRtcCallControllerProvider);

    return session.when(
      data: (call) {
        if (call == null ||
            call.status == 'ended' ||
            call.status == 'rejected') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final isVideo = call.type == 'video';
        final isRinging = call.status == 'ringing';
        final statusText = _buildStatusText(
          isRinging: isRinging,
          isVideo: isVideo,
          direction: call.direction,
          status: call.status,
          startedAt: call.startedAt,
          error: controller.error,
        );
        final bindSignature = '${call.callId}:${call.status}:${call.type}';
        if (_lastBoundCallId != call.callId ||
            _lastBindSignature != bindSignature) {
          _lastBoundCallId = call.callId;
          _lastBindSignature = bindSignature;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ref.read(webRtcCallControllerProvider).bindToSession(
                  session: call,
                  currentUserId: widget.userId,
                );
          });
        }

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Positioned.fill(
                child: controller.hasRemoteVideo && isVideo
                    ? RTCVideoView(
                        controller.remoteRenderer,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      )
                    : Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF050816), Color(0xFF111827)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                        child: Center(
                          child: UserAvatar(
                            photoUrl: call.contactPhoto,
                            name: call.contactName,
                            radius: 58,
                          ),
                        ),
                      ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                onPressed: () => ref
                                    .read(callsRepositoryProvider)
                                    .endActiveCall(widget.userId),
                                color: Colors.white,
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            call.contactName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            statusText,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: controller.error.isNotEmpty
                                  ? const Color(0xFFFCA5A5)
                                  : Colors.white70,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _buildAuxText(
                              type: call.type,
                              status: call.status,
                              startedAt: call.startedAt,
                            ),
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          width: 120,
                          height: 180,
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.white12),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: controller.hasLocalVideo
                              ? RTCVideoView(
                                  controller.localRenderer,
                                  mirror: controller.usingFrontCamera,
                                  objectFit: RTCVideoViewObjectFit
                                      .RTCVideoViewObjectFitCover,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 18,
                        runSpacing: 18,
                        children: [
                          _CallActionButton(
                            icon: controller.muted
                                ? Icons.mic_off_rounded
                                : Icons.mic_rounded,
                            label:
                                controller.muted ? 'Activar mic' : 'Silenciar',
                            onTap: () => ref
                                .read(webRtcCallControllerProvider)
                                .toggleMute(),
                          ),
                          _CallActionButton(
                            icon: controller.speakerOn
                                ? Icons.volume_up_rounded
                                : Icons.hearing_disabled_rounded,
                            label:
                                controller.speakerOn ? 'Altavoz' : 'Auricular',
                            onTap: () => ref
                                .read(webRtcCallControllerProvider)
                                .toggleSpeaker(),
                          ),
                          _CallActionButton(
                            icon: isVideo
                                ? Icons.call_rounded
                                : Icons.videocam_rounded,
                            label: isVideo ? 'Solo audio' : 'Video',
                            onTap: () async {
                              await ref
                                  .read(webRtcCallControllerProvider)
                                  .toggleVideo();
                              await ref
                                  .read(callsRepositoryProvider)
                                  .switchCallType(widget.userId);
                            },
                          ),
                          _CallActionButton(
                            icon: Icons.cameraswitch_rounded,
                            label: 'Cambiar cam',
                            onTap: () => ref
                                .read(webRtcCallControllerProvider)
                                .switchCamera(),
                          ),
                          _CallActionButton(
                            icon: call.screenSharing
                                ? Icons.stop_screen_share_rounded
                                : Icons.screen_share_rounded,
                            label: 'Pantalla',
                            onTap: () => ref
                                .read(webRtcCallControllerProvider)
                                .showScreenShareUnavailable(),
                          ),
                          if (call.direction == 'incoming' && isRinging)
                            _CallActionButton(
                              icon: Icons.call_rounded,
                              label: 'Contestar',
                              onTap: () async {
                                await ref
                                    .read(callsRepositoryProvider)
                                    .acceptActiveCall(widget.userId);
                                await ref
                                    .read(webRtcCallControllerProvider)
                                    .acceptIncomingCall(
                                      session: call,
                                      currentUserId: widget.userId,
                                    );
                              },
                              backgroundColor: Colors.green,
                            ),
                          _CallActionButton(
                            icon: Icons.call_end_rounded,
                            label: 'Colgar',
                            onTap: () => ref
                                .read(callsRepositoryProvider)
                                .endActiveCall(widget.userId),
                            backgroundColor: Colors.red,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              error.toString(),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.backgroundColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? Colors.white12;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.24),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
