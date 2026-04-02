import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../core/services/app_preferences_service.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/chat.dart';
import '../../../shared/models/message.dart';
import '../../auth/data/auth_repository.dart';
import '../../chats/data/chats_repository.dart';
import '../../profile/data/blocked_contacts_repository.dart';
import '../../profile/data/contacts_repository.dart';
import '../../profile/data/profile_repository.dart';
import '../data/messages_repository.dart';
import 'widgets/message_bubble.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({
    super.key,
    required this.chatId,
    required this.otherUserId,
    required this.otherUserName,
    required this.otherUsername,
    required this.otherUserPhoto,
    this.companyId,
  });

  final String chatId;
  final String otherUserId;
  final String otherUserName;
  final String otherUsername;
  final String otherUserPhoto;
  final String? companyId;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();
  final _itemScrollController = ItemScrollController();
  final _itemPositionsListener = ItemPositionsListener.create();
  
  List<File> _pendingAttachments = [];
  bool _isSending = false;
  Message? _replyingTo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final draft = ref.read(appPreferencesServiceProvider).getDraft(widget.chatId);
      _subjectController.text = draft['subject'] ?? '';
      _bodyController.text = draft['body'] ?? '';
      
      // Marcar mensajes como entregados al entrar
      ref.read(messagesRepositoryProvider).markRecentMessagesAsDelivered(
        chatId: widget.chatId,
      );
      ref.read(chatsRepositoryProvider).resetUnreadCount(widget.chatId);
    });
  }

  @override
  void dispose() {
    final pref = ref.read(appPreferencesServiceProvider);
    if (_subjectController.text.isNotEmpty || _bodyController.text.isNotEmpty) {
      pref.saveDraft(widget.chatId, _subjectController.text, _bodyController.text);
    } else {
      pref.clearDraft(widget.chatId);
    }
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _handleBlock() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("¿Bloquear contacto?", style: TextStyle(color: Colors.white)),
        content: const Text("No podrás recibir más correos de esta persona y la conversación se eliminará.", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCELAR")),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("BLOQUEAR", style: TextStyle(color: Colors.redAccent))
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final otherUser = AppUser(
        uid: widget.otherUserId,
        username: widget.otherUsername,
        usernameLower: widget.otherUsername.toLowerCase(),
        name: widget.otherUserName,
        email: '',
        photoUrl: widget.otherUserPhoto,
        bio: '',
        createdAt: null,
        isOnline: false,
        lastSeen: null,
      );

      await ref.read(blockedContactsRepositoryProvider).blockUser(otherUser);
      await ref.read(chatsRepositoryProvider).updateDirectMessageRequest(chatId: widget.chatId, status: 'declined');
      
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Usuario bloqueado")));
      }
    }
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null) {
      setState(() {
        _pendingAttachments.addAll(result.paths.where((p) => p != null).map((p) => File(p!)));
      });
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image != null) {
      setState(() {
        _pendingAttachments.add(File(image.path));
      });
    }
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (image != null) {
      setState(() {
        _pendingAttachments.add(File(image.path));
      });
    }
  }

  Future<void> _sendStructuredMessage() async {
    final subject = _subjectController.text.trim();
    var body = _bodyController.text.trim();
    if (subject.isEmpty && body.isEmpty && _pendingAttachments.isEmpty) return;

    setState(() => _isSending = true);
    try {
      final prefs = ref.read(appPreferencesServiceProvider);
      final signature = prefs.getUserSignature();
      if (signature.isNotEmpty && body.isNotEmpty) body = "$body\n\n--\n$signature";

      await ref
          .read(messagesRepositoryProvider)
          .sendEmailStyleMessage(
            chatId: widget.chatId,
            subject: subject,
            body: body,
            files: _pendingAttachments,
            replyTo: _replyingTo,
            replySenderName: _replyingTo != null
                ? (_replyingTo!.senderId ==
                        ref.read(authRepositoryProvider).currentUser?.uid
                    ? 'Tú'
                    : widget.otherUserName)
                : '',
          )
          .timeout(
            const Duration(seconds: 25),
            onTimeout: () {
              throw TimeoutException(
                'La app no recibio respuesta al enviar el mensaje.',
              );
            },
          );

      _subjectController.clear();
      _bodyController.clear();
      await prefs.clearDraft(widget.chatId);
      setState(() { 
        _pendingAttachments = []; 
        _isSending = false; 
        _replyingTo = null;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mensaje enviado.')),
      );
    } on TimeoutException catch (_) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El envio tardo demasiado. Revisa que Stream y el token provider sigan activos.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    }
  }

  void _forwardMessage(Message message) async {
    final chats = ref.read(userChatsProvider).valueOrNull ?? [];
    if (chats.isEmpty) return;

    final targetChat = await showModalBottomSheet<Chat>(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      builder: (context) => SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text("Reenviar a...", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: chats.length,
                itemBuilder: (context, index) {
                  final chat = chats[index];
                  final name = chat.type == 'direct' 
                    ? (chat.memberNames.entries.firstWhere((e) => e.key != ref.read(authRepositoryProvider).currentUser?.uid).value)
                    : chat.title;
                  return ListTile(
                    title: Text(name, style: const TextStyle(color: Colors.white)),
                    onTap: () => Navigator.pop(context, chat),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (targetChat != null) {
      await ref.read(messagesRepositoryProvider).forwardMessage(targetChatId: targetChat.id, originalMessage: message);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mensaje reenviado")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(chatMessagesProvider(widget.chatId));
    final chatAsync = ref.watch(chatProvider(widget.chatId));
    final currentUserId = ref.watch(authRepositoryProvider).currentUser?.uid;
    final otherUserAsync = ref.watch(userProfileProvider(widget.otherUserId));
    final isContactAsync = ref.watch(isContactProvider(widget.otherUserId));

    // Escuchar cambios en los mensajes para marcarlos como vistos automáticamente
    ref.listen(chatMessagesProvider(widget.chatId), (previous, next) {
      next.whenData((messages) {
        if (messages.isNotEmpty) {
          final unreadMessages = messages.where((m) => 
            m.senderId != currentUserId && !m.seenBy.contains(currentUserId)
          ).toList();
          
          if (unreadMessages.isNotEmpty) {
            ref.read(messagesRepositoryProvider).markMessagesAsSeen(
              chatId: widget.chatId,
              messages: unreadMessages,
            );
          }
        }
      });
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: InkWell(
          onTap: () => context.push('/contact/${widget.otherUserId}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.otherUserName, 
                    style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)
                  ),
                  otherUserAsync.when(
                    data: (user) => user?.isVerified == true 
                      ? const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.verified_rounded, color: Colors.blueAccent, size: 16),
                        )
                      : const SizedBox.shrink(),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ],
              ),
              Text('@${widget.otherUsername}', style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
            ],
          ),
        ),
        actions: [
          isContactAsync.when(
            data: (isContact) => isContact 
              ? const SizedBox.shrink()
              : IconButton(
                  icon: const Icon(Icons.person_add_outlined, color: Colors.blue),
                  onPressed: () => ref.read(contactsRepositoryProvider).addToContacts(widget.otherUserId),
                  tooltip: 'Agregar a contactos',
                ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: Column(
        children: [
          chatAsync.when(
            data: (chat) {
              if (chat == null) return const SizedBox.shrink();
              final isPending = chat.directMessageRequestStatus == 'pending';
              final isRecipient = chat.directMessageRequestRecipientId == currentUserId;
              
              if (isPending && isRecipient) {
                return Container(
                  color: Colors.blueAccent.withOpacity(0.1),
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: Row(
                    children: [
                      const Expanded(child: Text("¿Aceptar correo?", style: TextStyle(color: Colors.white, fontSize: 12))),
                      TextButton(
                        onPressed: () => ref.read(chatsRepositoryProvider).updateDirectMessageRequest(chatId: widget.chatId, status: 'accepted'),
                        child: const Text("ACEPTAR", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      TextButton(
                        onPressed: () => ref.read(chatsRepositoryProvider).updateDirectMessageRequest(chatId: widget.chatId, status: 'declined'),
                        child: const Text("RECHAZAR", style: TextStyle(fontSize: 12, color: Colors.orangeAccent)),
                      ),
                      TextButton(
                        onPressed: _handleBlock,
                        child: const Text("BLOQUEAR", style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          
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
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: MessageBubble(
                        message: message,
                        isMine: message.senderId == currentUserId,
                        viewerUserId: currentUserId ?? '',
                        onReply: (m) => setState(() => _replyingTo = m),
                        onForward: (m) => _forwardMessage(m),
                        onCopy: (m) {
                          Clipboard.setData(ClipboardData(text: m.text));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Texto copiado")));
                        },
                        onInfo: (m) {
                          final f = DateFormat('dd/MM/yyyy HH:mm:ss');
                          final deliveredAt = m.deliveredAt[widget.otherUserId];
                          final readAt = m.seenAt[widget.otherUserId];

                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              backgroundColor: const Color(0xFF1E293B),
                              title: const Text("Información del mensaje", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _infoRow(Icons.send_rounded, "Enviado", m.createdAt != null ? f.format(m.createdAt!) : "En proceso..."),
                                  const SizedBox(height: 12),
                                  _infoRow(Icons.done_all_rounded, "Entregado", deliveredAt != null ? f.format(deliveredAt) : "Pendiente"),
                                  const SizedBox(height: 12),
                                  _infoRow(Icons.visibility_rounded, "Leído", readAt != null ? f.format(readAt) : "No leído aún"),
                                ],
                              ),
                              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("CERRAR"))],
                            ),
                          );
                        },
                        onDeleteForMe: (m) async {
                          final confirm = await _showDeleteConfirm(false);
                          if (confirm) {
                            await ref.read(messagesRepositoryProvider).deleteMessageForMe(chatId: widget.chatId, messageId: m.id);
                          }
                        },
                        onDeleteForEveryone: (m) async {
                          final confirm = await _showDeleteConfirm(true);
                          if (confirm) {
                            await ref.read(messagesRepositoryProvider).deleteMessageForEveryone(chatId: widget.chatId, message: m);
                          }
                        },
                        onReplyTap: (originalMsgId) {
                          final idx = messages.indexWhere((msg) => msg.id == originalMsgId);
                          if (idx != -1) {
                            _itemScrollController.scrollTo(index: idx, duration: const Duration(milliseconds: 500), curve: Curves.easeInOutCubic);
                          }
                        },
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error: $err')),
            ),
          ),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.blueAccent),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
      ],
    );
  }

  Future<bool> _showDeleteConfirm(bool forEveryone) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(forEveryone ? "¿Eliminar para todos?" : "¿Eliminar para mí?", style: const TextStyle(color: Colors.white)),
        content: const Text("Esta acción no se puede deshacer.", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCELAR")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("ELIMINAR", style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(color: Color(0xFF1E293B), borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyingTo != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
                border: const Border(left: BorderSide(color: Colors.blue, width: 4)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _replyingTo!.senderId == ref.read(authRepositoryProvider).currentUser?.uid ? 'Responder a ti' : 'Responder a ${widget.otherUserName}',
                          style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        Text(
                          _replyingTo!.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: Colors.white54),
                    onPressed: () => setState(() => _replyingTo = null),
                  ),
                ],
              ),
            ),
          if (_pendingAttachments.isNotEmpty)
            SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _pendingAttachments.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Chip(
                    label: Text(_pendingAttachments[i].path.split(Platform.pathSeparator).last, style: const TextStyle(fontSize: 10)),
                    onDeleted: () => setState(() => _pendingAttachments.removeAt(i)),
                  ),
                ),
              ),
            ),
          TextField(
            controller: _subjectController,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(hintText: 'Asunto (opcional)', hintStyle: TextStyle(color: Colors.blueGrey), border: InputBorder.none),
          ),
          const Divider(color: Colors.white10),
          TextField(
            controller: _bodyController,
            maxLines: 5,
            minLines: 1,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(hintText: 'Redactar mensaje...', hintStyle: TextStyle(color: Colors.blueGrey), border: InputBorder.none),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.camera_alt_outlined, color: Colors.blue),
                onPressed: _takePhoto,
                tooltip: 'Cámara',
              ),
              IconButton(
                icon: const Icon(Icons.photo_outlined, color: Colors.blue),
                onPressed: _pickImage,
                tooltip: 'Galería',
              ),
              IconButton(
                icon: const Icon(Icons.attach_file, color: Colors.blue),
                onPressed: _pickFiles,
                tooltip: 'Archivos',
              ),
              const Spacer(),
              if (_isSending)
                const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              else
                FloatingActionButton.small(
                  onPressed: _sendStructuredMessage,
                  backgroundColor: Colors.blue,
                  child: const Icon(Icons.send_rounded, color: Colors.white),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
