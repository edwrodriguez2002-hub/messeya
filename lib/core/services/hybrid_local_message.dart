class HybridLocalMessage {
  const HybridLocalMessage({
    required this.localId,
    required this.messageUuid,
    required this.chatId,
    required this.senderId,
    required this.senderName,
    required this.recipientId,
    required this.text,
    required this.createdAtMs,
    required this.direction,
    required this.status,
    required this.relayHopsLeft,
    required this.lastError,
    required this.packetType,
    required this.originalSenderId,
    required this.retryCount,
    required this.lastAttemptAtMs,
    required this.attachmentPath,
    required this.attachmentName,
    required this.voiceDurationMs,
  });

  final int localId;
  final String messageUuid;
  final String chatId;
  final String senderId;
  final String senderName;
  final String recipientId;
  final String text;
  final int createdAtMs;
  final String direction;
  final String status;
  final int relayHopsLeft;
  final String lastError;
  final String packetType;
  final String originalSenderId;
  final int retryCount;
  final int lastAttemptAtMs;
  final String attachmentPath;
  final String attachmentName;
  final int voiceDurationMs;

  factory HybridLocalMessage.fromMap(Map<String, Object?> map) {
    return HybridLocalMessage(
      localId: map['local_id'] as int? ?? 0,
      messageUuid: map['message_uuid'] as String? ?? '',
      chatId: map['chat_id'] as String? ?? '',
      senderId: map['sender_id'] as String? ?? '',
      senderName: map['sender_name'] as String? ?? '',
      recipientId: map['recipient_id'] as String? ?? '',
      text: map['text'] as String? ?? '',
      createdAtMs: map['created_at_ms'] as int? ?? 0,
      direction: map['direction'] as String? ?? 'outgoing',
      status: map['status'] as String? ?? 'pending',
      relayHopsLeft: map['relay_hops_left'] as int? ?? 0,
      lastError: map['last_error'] as String? ?? '',
      packetType: map['packet_type'] as String? ?? 'message',
      originalSenderId: map['original_sender_id'] as String? ?? '',
      retryCount: map['retry_count'] as int? ?? 0,
      lastAttemptAtMs: map['last_attempt_at_ms'] as int? ?? 0,
      attachmentPath: map['attachment_path'] as String? ?? '',
      attachmentName: map['attachment_name'] as String? ?? '',
      voiceDurationMs: map['voice_duration_ms'] as int? ?? 0,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'local_id': localId == 0 ? null : localId,
      'message_uuid': messageUuid,
      'chat_id': chatId,
      'sender_id': senderId,
      'sender_name': senderName,
      'recipient_id': recipientId,
      'text': text,
      'created_at_ms': createdAtMs,
      'direction': direction,
      'status': status,
      'relay_hops_left': relayHopsLeft,
      'last_error': lastError,
      'packet_type': packetType,
      'original_sender_id': originalSenderId,
      'retry_count': retryCount,
      'last_attempt_at_ms': lastAttemptAtMs,
      'attachment_path': attachmentPath,
      'attachment_name': attachmentName,
      'voice_duration_ms': voiceDurationMs,
    };
  }

  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdAtMs);
}
