import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/models/app_user.dart';
import '../../../shared/widgets/messeya_ui.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/data/auth_repository.dart';
import '../../chats/data/chats_repository.dart';
import '../../profile/data/profile_repository.dart';
import '../../search/data/search_repository.dart';
import '../data/messages_repository.dart';
import '../data/drafts_repository.dart';

class ComposePage extends ConsumerStatefulWidget {
  const ComposePage({super.key, this.draftId});

  final String? draftId;

  @override
  ConsumerState<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends ConsumerState<ComposePage> {
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  final _searchController = TextEditingController();
  
  final List<AppUser> _selectedUsers = [];
  List<AppUser> _searchResults = [];
  final List<File> _attachedFiles = [];
  bool _isSearching = false;
  bool _isSending = false;
  String? _currentDraftId;

  @override
  void initState() {
    super.initState();
    _currentDraftId = widget.draftId;
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    if (_currentDraftId != null) {
      final drafts = await ref.read(draftsRepositoryProvider).getDrafts();
      final draft = drafts.where((d) => d.id == _currentDraftId).firstOrNull;
      
      if (draft != null) {
        _subjectController.text = draft.subject;
        _messageController.text = draft.text;
        
        for (var i = 0; i < draft.recipientIds.length; i++) {
          final uid = draft.recipientIds[i];
          final name = draft.recipientNames[i];
          
          _selectedUsers.add(AppUser(
            uid: uid,
            name: name,
            username: '',
            usernameLower: '',
            email: '',
            photoUrl: '',
            bio: '',
            createdAt: null,
            isOnline: false,
            lastSeen: null,
          ));
        }
        setState(() {});
      }
    }
  }

  Future<void> _saveAsDraft() async {
    if (_isSending) return;
    final subject = _subjectController.text.trim();
    final text = _messageController.text.trim();
    
    if (subject.isNotEmpty || text.isNotEmpty || _selectedUsers.isNotEmpty) {
      final draft = Draft(
        id: _currentDraftId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        subject: subject,
        text: text,
        recipientIds: _selectedUsers.map((u) => u.uid).toList(),
        recipientNames: _selectedUsers.map((u) => u.name).toList(),
        updatedAt: DateTime.now(),
      );
      await ref.read(draftsRepositoryProvider).saveDraft(draft);
    }
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isSearching = true);
    final currentUid = ref.read(currentUserProvider)?.uid;
    if (currentUid == null) {
      setState(() => _isSearching = false);
      return;
    }
    final results = await ref.read(searchRepositoryProvider).searchUsers(query, excludeUid: currentUid);
    setState(() {
      _searchResults = results;
      _isSearching = false;
    });
  }

  void _showUserInfo(AppUser user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: MesseyaUi.cardFor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            UserAvatar(photoUrl: user.photoUrl, name: user.name, radius: 40),
            const SizedBox(height: 16),
            Text(
              user.name,
              style: TextStyle(
                color: MesseyaUi.textPrimaryFor(context),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text('@${user.username}', style: const TextStyle(color: Colors.blue, fontSize: 14)),
            const SizedBox(height: 8),
            Text(
              user.bio.isEmpty ? 'Sin biografía' : user.bio,
              textAlign: TextAlign.center,
              style: TextStyle(color: MesseyaUi.textMutedFor(context)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
          if (!_selectedUsers.any((u) => u.uid == user.uid))
            ElevatedButton(
              onPressed: () {
                setState(() => _selectedUsers.add(user));
                Navigator.pop(context);
              },
              child: const Text('Seleccionar'),
            ),
        ],
      ),
    );
  }

  Future<void> _sendBroadcast() async {
    if (_selectedUsers.isEmpty ||
        (_messageController.text.isEmpty && _attachedFiles.isEmpty)) {
      return;
    }

    setState(() => _isSending = true);
    try {
      final repo = ref.read(messagesRepositoryProvider);
      final chatsRepo = ref.read(chatsRepositoryProvider);
      final currentUser = await ref.read(profileRepositoryProvider).getCurrentUser();
      if (currentUser == null) {
        throw StateError('No se encontro el usuario actual para enviar el mensaje.');
      }

      for (final user in _selectedUsers) {
        final chatId = await chatsRepo
            .createOrGetDirectChat(user, currentUser)
            .timeout(
              const Duration(seconds: 35),
              onTimeout: () => throw TimeoutException(
                'No se pudo abrir el chat con ${user.name} a tiempo.',
              ),
            );

        if (_attachedFiles.isNotEmpty) {
          for (int i = 0; i < _attachedFiles.length; i++) {
            await repo.sendAttachmentMessage(
              chatId: chatId,
              type: _isImage(_attachedFiles[i].path) ? 'image' : 'file',
              file: _attachedFiles[i],
              text: i == 0 ? _messageController.text : '',
              subject: i == 0 ? _subjectController.text : '',
            );
          }
        } else {
          await repo.sendTextMessage(
            chatId: chatId,
            text: _messageController.text,
            subject: _subjectController.text,
          );
        }
      }

      if (_currentDraftId != null) {
        await ref.read(draftsRepositoryProvider).deleteDraft(_currentDraftId!);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mensajes enviados correctamente')),
      );
      context.pop();
    } on TimeoutException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'La operacion excedio el tiempo de espera.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo enviar el mensaje: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  bool _isImage(String path) {
    final ext = path.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = MesseyaUi.backgroundFor(context);
    final surfaceColor = MesseyaUi.cardFor(context);
    final primaryTextColor = MesseyaUi.textPrimaryFor(context);
    final mutedTextColor = MesseyaUi.textMutedFor(context);
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          await _saveAsDraft();
        }
      },
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          title: const Text('Redactar Correo'),
          backgroundColor: surfaceColor,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          actions: [
            if (_isSending)
              const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()))
            else
              IconButton(icon: const Icon(Icons.send_rounded, color: Colors.blue), onPressed: _sendBroadcast),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Para:',
                style: TextStyle(color: mutedTextColor, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ..._selectedUsers.map((u) => Chip(
                    backgroundColor: Colors.blue.withValues(alpha: 0.18),
                    label: Text(u.name, style: TextStyle(color: primaryTextColor)),
                    onDeleted: () => setState(() => _selectedUsers.remove(u)),
                    deleteIconColor: mutedTextColor,
                  )),
                  ActionChip(
                    backgroundColor: surfaceColor,
                    label: const Icon(Icons.add, color: Colors.blue, size: 20),
                    onPressed: () => _showSearchDialog(),
                  ),
                ],
              ),
              Divider(color: mutedTextColor.withValues(alpha: 0.18), height: 32),
              
              TextField(
                controller: _subjectController,
                style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: 'Asunto',
                  hintStyle: TextStyle(color: mutedTextColor),
                  border: InputBorder.none,
                ),
              ),
              Divider(color: mutedTextColor.withValues(alpha: 0.18)),
              
              TextField(
                controller: _messageController,
                maxLines: null,
                minLines: 5,
                style: TextStyle(color: primaryTextColor),
                decoration: InputDecoration(
                  hintText: 'Escribe tu mensaje...',
                  hintStyle: TextStyle(color: mutedTextColor),
                  border: InputBorder.none,
                ),
              ),
              
              if (_attachedFiles.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Adjuntos:',
                  style: TextStyle(color: mutedTextColor, fontSize: 12),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 60,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _attachedFiles.length,
                    itemBuilder: (context, index) => Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: MesseyaUi.isDark(context)
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.attach_file, color: Colors.blue, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            _attachedFiles[index].path.split('/').last,
                            style: TextStyle(color: primaryTextColor, fontSize: 12),
                          ),
                          IconButton(icon: const Icon(Icons.close, size: 16, color: Colors.red), onPressed: () => setState(() => _attachedFiles.removeAt(index))),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        bottomNavigationBar: BottomAppBar(
          color: surfaceColor,
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.photo_library_outlined, color: Colors.blue), onPressed: _pickImages),
              IconButton(icon: const Icon(Icons.attach_file_rounded, color: Colors.blue), onPressed: _pickFiles),
            ],
          ),
        ),
      ),
    );
  }

  void _showSearchDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: MesseyaUi.backgroundFor(context),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: MesseyaUi.textPrimaryFor(context)),
                decoration: InputDecoration(
                  hintText: 'Buscar usuario...',
                  hintStyle: TextStyle(color: MesseyaUi.textMutedFor(context)),
                  prefixIcon: const Icon(Icons.search, color: Colors.blue),
                  filled: true,
                  fillColor: MesseyaUi.cardFor(context),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                onChanged: (val) async {
                  await _searchUsers(val);
                  setModalState(() {});
                },
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isSearching 
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final user = _searchResults[index];
                        final isSelected = _selectedUsers.any((u) => u.uid == user.uid);
                        return ListTile(
                          leading: UserAvatar(photoUrl: user.photoUrl, name: user.name),
                          title: Text(
                            user.name,
                            style: TextStyle(color: MesseyaUi.textPrimaryFor(context)),
                          ),
                          subtitle: Text(
                            '@${user.username}',
                            style: TextStyle(color: MesseyaUi.textMutedFor(context)),
                          ),
                          trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.blue) : null,
                          onTap: () => _showUserInfo(user),
                        );
                      },
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage();
    if (images.isNotEmpty) setState(() => _attachedFiles.addAll(images.map((i) => File(i.path))));
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null) setState(() => _attachedFiles.addAll(result.paths.whereType<String>().map((p) => File(p))));
  }
}
