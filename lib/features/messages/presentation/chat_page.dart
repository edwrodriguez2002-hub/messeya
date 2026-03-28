import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../shared/models/message.dart';
import '../../auth/data/auth_repository.dart';
import '../../chats/data/chats_repository.dart';
import '../data/messages_repository.dart';
import '../data/drafts_repository.dart';
import 'widgets/message_bubble.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({
    super.key,
    required this.chatId,
    required this.otherUserId,
    required this.otherUserName,
    required this.otherUsername,
    required this.otherUserPhoto,
  });

  final String chatId;
  final String otherUserId;
  final String otherUserName;
  final String otherUsername;
  final String otherUserPhoto;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _messageController = TextEditingController();
  final _subjectController = TextEditingController();
  final _itemScrollController = ItemScrollController();
  final _itemPositionsListener = ItemPositionsListener.create();
  final _focusNode = FocusNode();
  
  final List<File> _attachedFiles = [];
  Message? _replyTo;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_updateTyping);
    _subjectController.addListener(_updateTyping);
    _loadDraft();
  }

  Future<void> _loadDraft() async {
    final draftsRepo = ref.read(draftsRepositoryProvider);
    final drafts = await draftsRepo.getDrafts();
    final draft = drafts.where((d) => d.id == widget.chatId).firstOrNull;
    if (draft != null) {
      setState(() {
        _messageController.text = draft.text;
        _subjectController.text = draft.subject;
        _isTyping = _messageController.text.isNotEmpty || _subjectController.text.isNotEmpty;
      });
    }
  }

  Future<void> _saveDraft() async {
    final text = _messageController.text.trim();
    final subject = _subjectController.text.trim();
    final draftsRepo = ref.read(draftsRepositoryProvider);

    if (text.isEmpty && subject.isEmpty) {
      await draftsRepo.deleteDraft(widget.chatId);
    } else {
      await draftsRepo.saveDraft(Draft(
        id: widget.chatId,
        subject: subject,
        text: text,
        recipientIds: [widget.otherUserId],
        recipientNames: [widget.otherUserName],
        updatedAt: DateTime.now(),
      ));
    }
  }

  void _updateTyping() {
    final typing = _messageController.text.trim().isNotEmpty || 
                   _subjectController.text.trim().isNotEmpty || 
                   _attachedFiles.isNotEmpty;
    if (typing != _isTyping) {
      setState(() => _isTyping = typing);
    }
    _saveDraft();
  }

  @override
  void dispose() {
    _saveDraft();
    _messageController.dispose();
    _subjectController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    final subject = _subjectController.text.trim();
    
    if (text.isEmpty && subject.isEmpty && _attachedFiles.isEmpty) return;

    final repo = ref.read(messagesRepositoryProvider);
    final draftsRepo = ref.read(draftsRepositoryProvider);

    try {
      if (_attachedFiles.isNotEmpty) {
        // Enviar todos los archivos en un SOLO mensaje
        await repo.sendMultiAttachmentMessage(
          chatId: widget.chatId,
          files: _attachedFiles,
          text: text,
          subject: subject,
          replyTo: _replyTo,
          replySenderName: _replyTo?.senderId == ref.read(authRepositoryProvider).currentUser?.uid ? 'Tú' : widget.otherUserName,
        );
      } else {
        await repo.sendTextMessage(
          chatId: widget.chatId, 
          text: text,
          subject: subject,
          replyTo: _replyTo,
          replySenderName: _replyTo?.senderId == ref.read(authRepositoryProvider).currentUser?.uid ? 'Tú' : widget.otherUserName,
        );
      }

      _messageController.clear();
      _subjectController.clear();
      await draftsRepo.deleteDraft(widget.chatId);
      
      setState(() {
        _attachedFiles.clear();
        _replyTo = null;
        _isTyping = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar: $e')),
        );
      }
    }
  }

  void _forwardMessage(Message message) {
     showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      builder: (context) {
        final chats = ref.watch(userChatsForProvider(ref.read(authRepositoryProvider).currentUser?.uid ?? ''));
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Reenviar a...', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: chats.when(
                data: (items) => ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final chat = items[index];
                    return ListTile(
                      title: Text(chat.title.isEmpty ? 'Chat' : chat.title, style: const TextStyle(color: Colors.white)),
                      onTap: () async {
                        await ref.read(messagesRepositoryProvider).forwardMessage(
                          targetChatId: chat.id,
                          originalMessage: message,
                        );
                        if (context.mounted) Navigator.pop(context);
                      },
                    );
                  },
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const Center(child: Text('Error')),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() {
        _attachedFiles.addAll(images.map((f) => File(f.path)));
        _isTyping = true;
      });
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null) {
      setState(() {
        _attachedFiles.addAll(result.paths.where((p) => p != null).map((p) => File(p!)));
        _isTyping = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(chatMessagesProvider(widget.chatId));
    final currentUserId = ref.watch(authRepositoryProvider).currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), 
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: InkWell(
          onTap: () => context.push('/contact/${widget.otherUserId}'),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: widget.otherUserPhoto.isNotEmpty ? NetworkImage(widget.otherUserPhoto) : null,
                child: widget.otherUserPhoto.isEmpty ? const Icon(Icons.person, size: 20) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.otherUserName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    Text('@${widget.otherUsername}', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              data: (messages) {
                return ScrollablePositionedList.builder(
                  itemScrollController: _itemScrollController,
                  itemPositionsListener: _itemPositionsListener,
                  itemCount: messages.length,
                  reverse: true,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isMine = message.senderId == currentUserId;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Align(
                        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                        child: MessageBubble(
                          message: message, 
                          isMine: isMine, 
                          viewerUserId: currentUserId ?? '',
                          onReply: () => setState(() => _replyTo = message),
                          onForward: () => _forwardMessage(message),
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error: $err')),
            ),
          ),
          _buildEmailInputArea(),
        ],
      ),
    );
  }

  Widget _buildEmailInputArea() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10)],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyTo != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  border: const Border(left: BorderSide(color: Colors.blue, width: 4)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Respondiendo a:', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12)),
                          Text(_replyTo!.text.isEmpty ? 'Archivo/Imagen' : _replyTo!.text, 
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.close, size: 18, color: Colors.white70), onPressed: () => setState(() => _replyTo = null)),
                  ],
                ),
              ),

            if (_attachedFiles.isNotEmpty)
              Container(
                height: 80,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _attachedFiles.length,
                  itemBuilder: (context, index) {
                    return Stack(
                      children: [
                        Container(
                          width: 80,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.withOpacity(0.5)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _isImage(_attachedFiles[index].path)
                                ? Image.file(_attachedFiles[index], fit: BoxFit.cover)
                                : const Icon(Icons.insert_drive_file, color: Colors.white),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 8,
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _attachedFiles.removeAt(index);
                              _updateTyping();
                            }),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                              child: const Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _subjectController,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      hintText: 'Asunto...',
                      hintStyle: TextStyle(color: Color(0xFF64748B)),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: InputBorder.none,
                    ),
                  ),
                  const Divider(color: Color(0xFF1E293B), height: 1),
                  TextField(
                    controller: _messageController,
                    focusNode: _focusNode,
                    maxLines: 5,
                    minLines: 1,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Escribe tu mensaje (*negrita*, _cursiva_)...',
                      hintStyle: TextStyle(color: Color(0xFF64748B)),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: InputBorder.none,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(icon: const Icon(Icons.photo_library_outlined, color: Colors.blue), onPressed: _pickFromGallery),
                IconButton(icon: const Icon(Icons.attach_file_rounded, color: Colors.blue), onPressed: _pickFile),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _isTyping ? _sendMessage : null,
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Enviar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue,
                    disabledBackgroundColor: Colors.grey.withOpacity(0.2),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _isImage(String path) {
    final ext = path.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);
  }
}
