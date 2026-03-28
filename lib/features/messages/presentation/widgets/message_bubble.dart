import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/services/media_cache_service.dart';
import '../../../../shared/models/message.dart';
import '../../data/messages_repository.dart';

class MessageBubble extends ConsumerStatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.viewerUserId,
    this.onReply,
    this.onForward,
  });

  final Message message;
  final bool isMine;
  final String viewerUserId;
  final VoidCallback? onReply;
  final VoidCallback? onForward;

  @override
  ConsumerState<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends ConsumerState<MessageBubble> {
  @override
  Widget build(BuildContext context) {
    // Si el mensaje está borrado para este usuario, no mostramos nada
    if (widget.message.deletedFor.contains(widget.viewerUserId)) {
      return const SizedBox.shrink();
    }

    final isDeleted = widget.message.deletedForAll;
    final bgColor = widget.isMine ? const Color(0xFF1E293B) : Colors.white;
    final textColor = widget.isMine ? Colors.white : Colors.black87;
    final labelColor = widget.isMine ? Colors.white70 : Colors.black54;

    return GestureDetector(
      onLongPress: isDeleted ? null : () => _showActionsMenu(context),
      onTap: isDeleted ? null : () => _showDetailedInfo(context),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        decoration: BoxDecoration(
          color: isDeleted ? Colors.transparent : bgColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(widget.isMine ? 12 : 0),
            bottomRight: Radius.circular(widget.isMine ? 0 : 12),
          ),
          border: isDeleted 
            ? Border.all(color: Colors.white24, width: 0.5)
            : Border.all(
                color: widget.message.priority == 'urgent' 
                    ? Colors.red.withOpacity(0.5) 
                    : (widget.isMine ? Colors.blue.withOpacity(0.3) : Colors.grey.shade300),
                width: widget.message.priority == 'urgent' ? 2 : 1,
              ),
          boxShadow: isDeleted ? [] : [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isDeleted) ...[
              // Email Header
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: widget.message.priority == 'urgent' 
                      ? Colors.red.withOpacity(0.1)
                      : (widget.isMine ? Colors.blue.withOpacity(0.1) : Colors.grey.shade100),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.message.priority != 'normal')
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Icon(
                              widget.message.priority == 'urgent' ? Icons.priority_high_rounded : Icons.low_priority_rounded,
                              size: 14,
                              color: widget.message.priority == 'urgent' ? Colors.red : Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              widget.message.priority == 'urgent' ? 'URGENTE' : 'Prioridad Baja',
                              style: TextStyle(
                                fontSize: 10, 
                                fontWeight: FontWeight.bold, 
                                color: widget.message.priority == 'urgent' ? Colors.red : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (widget.message.forwardedFromSenderName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.forward_rounded, size: 14, color: Colors.blue),
                            const SizedBox(width: 4),
                            Text(
                              'Reenviado de ${widget.message.forwardedFromSenderName}',
                              style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.blue),
                            ),
                          ],
                        ),
                      ),
                    _buildHeaderRow('De:', widget.isMine ? 'Tú' : 'Contacto', labelColor),
                    if (widget.message.subject.isNotEmpty)
                      _buildHeaderRow('Asunto:', widget.message.subject, labelColor, isBold: true),
                    _buildHeaderRow('Fecha:', _formatDate(widget.message.createdAt), labelColor),
                  ],
                ),
              ),

              // Reply Content (if any)
              if (widget.message.replyToText.isNotEmpty)
                Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: widget.isMine ? Colors.white.withOpacity(0.05) : Colors.blue.withOpacity(0.05),
                    border: const Border(left: BorderSide(color: Colors.blue, width: 3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.message.replyToSenderName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue),
                      ),
                      Text(
                        widget.message.replyToText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: labelColor, fontSize: 11),
                      ),
                    ],
                  ),
                ),
            ],

            // Main Content
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isDeleted)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.block, size: 14, color: Colors.white38),
                        const SizedBox(width: 8),
                        Text(
                          'Este mensaje fue eliminado',
                          style: TextStyle(color: Colors.white38, fontSize: 14, fontStyle: FontStyle.italic),
                        ),
                      ],
                    )
                  else ...[
                    if (widget.message.type == 'image' || widget.message.type == 'file')
                      _MediaMessage(message: widget.message, isMine: widget.isMine),
                    
                    if (widget.message.text.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: (widget.message.type != 'text' ? 8.0 : 0.0)),
                        child: _FormattedText(
                          text: widget.message.text,
                          style: TextStyle(color: textColor, fontSize: 15, height: 1.4),
                        ),
                      ),
                  ],
                ],
              ),
            ),

            // Footer / Status
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    DateFormat('HH:mm').format(widget.message.createdAt ?? DateTime.now()),
                    style: TextStyle(fontSize: 10, color: labelColor),
                  ),
                  if (widget.isMine && !isDeleted) ...[
                    const SizedBox(width: 4),
                    _buildStatusIcon(),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderRow(String label, String value, Color color, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Text('$label ', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return DateFormat('dd MMM yyyy, HH:mm').format(date);
  }

  Widget _buildStatusIcon() {
    final isSeen = widget.message.seenBy.length > 1;
    final isDelivered = widget.message.deliveredTo.length > 1;

    if (isSeen) {
      return const Icon(Icons.done_all_rounded, size: 14, color: Colors.cyanAccent);
    } else if (isDelivered) {
      return const Icon(Icons.done_all_rounded, size: 14, color: Colors.white70);
    } else {
      return const Icon(Icons.done_rounded, size: 14, color: Colors.white70);
    }
  }

  void _showActionsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded, color: Colors.white),
              title: const Text('Responder', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                widget.onReply?.call();
              },
            ),
            ListTile(
              leading: const Icon(Icons.forward_rounded, color: Colors.white),
              title: const Text('Reenviar', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                widget.onForward?.call();
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded, color: Colors.white),
              title: const Text('Información', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showDetailedInfo(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded, color: Colors.white),
              title: const Text('Copiar texto', style: TextStyle(color: Colors.white)),
              onTap: () {
                // Implementar copiar al portapapeles si fuera necesario
                Navigator.pop(context);
              },
            ),
            const Divider(color: Colors.white12),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: const Text('Eliminar para mí', style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                Navigator.pop(context);
                await ref.read(messagesRepositoryProvider).deleteMessageForMe(
                  chatId: widget.message.chatId,
                  messageId: widget.message.id,
                );
              },
            ),
            if (widget.isMine)
              ListTile(
                leading: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
                title: const Text('Eliminar para todos', style: TextStyle(color: Colors.redAccent)),
                onTap: () async {
                  Navigator.pop(context);
                  await ref.read(messagesRepositoryProvider).deleteMessageForEveryone(
                    chatId: widget.message.chatId,
                    message: widget.message,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showDetailedInfo(BuildContext context) {
    if (!widget.isMine) return;

    showDialog(
      context: context,
      builder: (context) {
        final dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');
        // Obtenemos el primer timestamp de lectura/entrega que no sea del propio remitente
        final otherUserReadAt = widget.message.seenAt.entries
            .where((e) => e.key != widget.message.senderId)
            .map((e) => e.value)
            .firstOrNull;
            
        final otherUserDeliveredAt = widget.message.deliveredAt.entries
            .where((e) => e.key != widget.message.senderId)
            .map((e) => e.value)
            .firstOrNull;

        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Detalles del mensaje', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailItem(
                Icons.send_rounded, 
                'Enviado', 
                widget.message.createdAt != null ? dateFormat.format(widget.message.createdAt!) : 'Pendiente',
              ),
              const SizedBox(height: 12),
              _buildDetailItem(
                Icons.done_all_rounded, 
                'Entregado', 
                otherUserDeliveredAt != null 
                    ? dateFormat.format(otherUserDeliveredAt) 
                    : 'No entregado',
                color: Colors.white70,
              ),
              const SizedBox(height: 12),
              _buildDetailItem(
                Icons.visibility_rounded, 
                'Leído', 
                otherUserReadAt != null 
                    ? dateFormat.format(otherUserReadAt)
                    : 'No leído',
                color: Colors.cyanAccent,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
          ],
        );
      },
    );
  }

  Widget _buildDetailItem(IconData icon, String label, String value, {Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color ?? Colors.blue),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }
}

class _FormattedText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const _FormattedText({required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    List<TextSpan> spans = [];
    final regExp = RegExp(r'(\*.*?\*)|(_.*?_)');
    
    int lastMatchEnd = 0;
    final matches = regExp.allMatches(text);

    for (var match in matches) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(text: text.substring(lastMatchEnd, match.start)));
      }

      String matchText = match.group(0)!;
      if (matchText.startsWith('*') && matchText.endsWith('*') && matchText.length > 2) {
        spans.add(TextSpan(
          text: matchText.substring(1, matchText.length - 1),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ));
      } else if (matchText.startsWith('_') && matchText.endsWith('_') && matchText.length > 2) {
        spans.add(TextSpan(
          text: matchText.substring(1, matchText.length - 1),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      } else {
        spans.add(TextSpan(text: matchText));
      }

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastMatchEnd)));
    }

    return RichText(
      text: TextSpan(style: style, children: spans),
    );
  }
}

class _MediaMessage extends ConsumerWidget {
  const _MediaMessage({required this.message, required this.isMine});
  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previewWidth = double.infinity;

    if (message.type == 'image') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(message.attachmentUrl, width: previewWidth, height: 180, fit: BoxFit.cover),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isMine ? Colors.white.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file, color: Colors.blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message.fileName.isEmpty ? 'Archivo' : message.fileName,
              style: TextStyle(color: isMine ? Colors.white : Colors.black87, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.download_rounded, size: 20, color: Colors.blue),
            onPressed: () async {
               final uri = Uri.tryParse(message.attachmentUrl);
               if (uri != null) await launchUrl(uri);
            },
          ),
        ],
      ),
    );
  }
}
