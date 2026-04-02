import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../../../../shared/models/message.dart';
import '../../../../core/services/encryption_service.dart';
import '../../../../shared/widgets/fullscreen_image_page.dart';

class MessageBubble extends ConsumerStatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.viewerUserId,
    this.onReply,
    this.onForward,
    this.onCopy,
    this.onInfo,
    this.onDeleteForMe,
    this.onDeleteForEveryone,
    this.onReplyTap,
  });

  final Message message;
  final bool isMine;
  final String viewerUserId;
  final Function(Message)? onReply;
  final Function(Message)? onForward;
  final Function(Message)? onCopy;
  final Function(Message)? onInfo;
  final Function(Message)? onDeleteForMe;
  final Function(Message)? onDeleteForEveryone;
  final Function(String)? onReplyTap;

  @override
  ConsumerState<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends ConsumerState<MessageBubble> {
  String? _decryptedText;
  bool _isDecrypting = false;
  double _dragOffset = 0.0;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _checkAndDecrypt();
  }

  @override
  void didUpdateWidget(MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message.text != oldWidget.message.text) {
      _checkAndDecrypt();
    }
  }

  Future<void> _checkAndDecrypt() async {
    final text = widget.message.text;
    if (widget.message.isEncrypted || (text.startsWith('{') && text.contains('cipherText'))) {
      setState(() => _isDecrypting = true);
      try {
        final decrypted = await ref.read(encryptionServiceProvider).decryptMessage(
          text,
          widget.viewerUserId,
        );
        if (mounted) {
          setState(() {
            _decryptedText = decrypted;
            _isDecrypting = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _decryptedText = "[Error al descifrar]";
            _isDecrypting = false;
          });
        }
      }
    } else {
      setState(() {
        _decryptedText = null;
        _isDecrypting = false;
      });
    }
  }

  Future<void> _openFile(MessageAttachment attachment) async {
    setState(() => _isDownloading = true);
    try {
      final appDir = await getTemporaryDirectory();
      final filePath = path.join(appDir.path, attachment.name);
      final file = File(filePath);

      if (!await file.exists()) {
        final response = await http.get(Uri.parse(attachment.url));
        await file.writeAsBytes(response.bodyBytes);
      }

      await OpenFilex.open(filePath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir el archivo: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded, color: Colors.blue),
              title: const Text('Responder', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                widget.onReply?.call(widget.message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.forward_rounded, color: Colors.greenAccent),
              title: const Text('Reenviar', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                widget.onForward?.call(widget.message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded, color: Colors.orangeAccent),
              title: const Text('Copiar texto', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                widget.onCopy?.call(widget.message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded, color: Colors.white70),
              title: const Text('Información', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                widget.onInfo?.call(widget.message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: const Text('Eliminar para mí', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                widget.onDeleteForMe?.call(widget.message);
              },
            ),
            if (widget.isMine)
              ListTile(
                leading: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                title: const Text('Eliminar para todos', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(context);
                  widget.onDeleteForEveryone?.call(widget.message);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMine = widget.isMine;
    final message = widget.message;
    final bgColor = isMine ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isMine ? Colors.white : Colors.black87;
    final labelColor = isMine ? Colors.white70 : Colors.black54;

    final displayedText = _decryptedText ?? message.text;
    final isEncrypted = message.isEncrypted || (message.text.startsWith('{') && message.text.contains('cipherText'));

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showOptions(context),
        onHorizontalDragUpdate: (details) {
          if (details.delta.dx > 0) {
            setState(() {
              _dragOffset += details.delta.dx;
              if (_dragOffset > 70) _dragOffset = 70;
            });
          }
        },
        onHorizontalDragEnd: (details) {
          if (_dragOffset >= 60) {
            widget.onReply?.call(widget.message);
          }
          setState(() => _dragOffset = 0.0);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          transform: Matrix4.translationValues(_dragOffset, 0, 0),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (_dragOffset > 10)
                Positioned(
                  left: -40,
                  top: 0,
                  bottom: 0,
                  child: Icon(
                    Icons.reply_rounded,
                    color: Colors.blue.withOpacity((_dragOffset / 70).clamp(0, 1)),
                    size: 24,
                  ),
                ),
              
              Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isMine ? 16 : 4),
                    bottomRight: Radius.circular(isMine ? 4 : 16),
                  ),
                  border: Border.all(
                    color: message.priority == 'urgent' ? Colors.redAccent : Colors.transparent,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isMine ? Colors.white.withOpacity(0.05) : Colors.blue.withOpacity(0.05),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (message.subject.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                message.subject,
                                style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ),
                          Row(
                            children: [
                              Text(
                                isMine ? "Para: Contacto" : "De: Identificador", 
                                style: TextStyle(color: labelColor, fontSize: 11),
                              ),
                              const Spacer(),
                              if (isEncrypted)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Icon(Icons.lock_outline_rounded, color: labelColor, size: 12),
                                ),
                              if (message.priority == 'urgent')
                                const Icon(Icons.priority_high_rounded, color: Colors.redAccent, size: 14),
                            ],
                          ),
                        ],
                      ),
                    ),

                    if (message.replyToText.isNotEmpty)
                      InkWell(
                        onTap: () => widget.onReplyTap?.call(message.replyToMessageId),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: const Border(left: BorderSide(color: Colors.blue, width: 3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                message.replyToSenderName,
                                style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                              Text(
                                message.replyToText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: labelColor, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),

                    if (displayedText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: _isDecrypting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueGrey),
                              )
                            : Text(
                                displayedText,
                                style: TextStyle(color: textColor, fontSize: 14, height: 1.4),
                              ),
                      ),

                    if (message.attachments.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                        child: Column(
                          children: message.attachments.map((attr) => _AttachmentItem(
                            attachment: attr, 
                            isMine: isMine, 
                            heroTag: 'img_${message.id}_${attr.url}',
                            onOpenFile: () => _openFile(attr),
                            isDownloading: _isDownloading,
                          )).toList(),
                        ),
                      ),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            DateFormat('HH:mm').format(message.createdAt ?? DateTime.now()),
                            style: TextStyle(fontSize: 10, color: labelColor),
                          ),
                          if (isMine) ...[
                            const SizedBox(width: 4),
                            _buildStatusIcon(message),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon(Message message) {
    final isSeen = message.seenBy.length > 1;
    final isDelivered = message.deliveredTo.length > 1;

    if (isSeen) {
      return const Icon(Icons.done_all_rounded, size: 14, color: Colors.cyanAccent);
    } else if (isDelivered) {
      return const Icon(Icons.done_all_rounded, size: 14, color: Colors.white70);
    } else {
      return const Icon(Icons.done_rounded, size: 14, color: Colors.white70);
    }
  }
}

class _AttachmentItem extends StatelessWidget {
  final MessageAttachment attachment;
  final bool isMine;
  final String heroTag;
  final VoidCallback onOpenFile;
  final bool isDownloading;

  const _AttachmentItem({
    required this.attachment, 
    required this.isMine, 
    required this.heroTag,
    required this.onOpenFile,
    required this.isDownloading,
  });

  @override
  Widget build(BuildContext context) {
    final isImage = attachment.type == 'image';
    
    return InkWell(
      onTap: () {
        if (isImage) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FullscreenImagePage(
                imageUrl: attachment.url,
                heroTag: heroTag,
              ),
            ),
          );
        } else {
          onOpenFile();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        width: isImage ? 120 : double.infinity,
        height: isImage ? 120 : 60,
        decoration: BoxDecoration(
          color: isMine ? Colors.white.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: isImage 
          ? Hero(
              tag: heroTag,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  attachment.url,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  },
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  isDownloading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.insert_drive_file, color: Colors.blue, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          attachment.name,
                          style: const TextStyle(color: Colors.blue, fontSize: 13, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Toca para abrir',
                          style: TextStyle(color: isMine ? Colors.white54 : Colors.black54, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }
}
