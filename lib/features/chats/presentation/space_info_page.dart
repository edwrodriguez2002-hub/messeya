import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/widgets/async_value_widget.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/data/auth_repository.dart';
import '../../profile/data/profile_repository.dart';
import '../data/chats_repository.dart';

class SpaceInfoPage extends ConsumerWidget {
  const SpaceInfoPage({
    super.key,
    required this.chatId,
  });

  final String chatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(chatProvider(chatId));
    final currentUserId = ref.watch(currentUserProvider)?.uid ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Informacion del espacio')),
      body: AsyncValueWidget(
        value: chatState,
        data: (chat) {
          if (chat == null) {
            return const Center(
              child: Text('No se encontro la informacion del espacio.'),
            );
          }

          final isAdmin = chat.adminIds.contains(currentUserId);
          final isOwner = chat.ownerId == currentUserId;
          final memberIds = chat.members.where((id) => id.isNotEmpty).toList();

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _SpaceHeaderCard(
                chatId: chatId,
                title: chat.title,
                description: chat.description,
                type: chat.type,
                photoUrl: chat.photoUrl,
                coverUrl: chat.coverUrl,
                inviteLink:
                    ref.read(chatsRepositoryProvider).buildInviteLink(chat),
                onlyAdminsCanPost: chat.onlyAdminsCanPost,
                isAdmin: isAdmin,
                isOwner: isOwner,
              ),
              const SizedBox(height: 16),
              Text(
                'Miembros',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              for (final userId in memberIds)
                _SpaceMemberTile(
                  chatId: chatId,
                  userId: userId,
                  currentUserId: currentUserId,
                  isAdmin: isAdmin,
                  isOwner: isOwner,
                  ownerId: chat.ownerId,
                  adminIds: chat.adminIds,
                  moderatorIds: chat.moderatorIds,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SpaceHeaderCard extends ConsumerWidget {
  const _SpaceHeaderCard({
    required this.chatId,
    required this.title,
    required this.description,
    required this.type,
    required this.photoUrl,
    required this.coverUrl,
    required this.inviteLink,
    required this.onlyAdminsCanPost,
    required this.isAdmin,
    required this.isOwner,
  });

  final String chatId;
  final String title;
  final String description;
  final String type;
  final String photoUrl;
  final String coverUrl;
  final String inviteLink;
  final bool onlyAdminsCanPost;
  final bool isAdmin;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (coverUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.network(
                  coverUrl,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            if (coverUrl.isNotEmpty) const SizedBox(height: 14),
            Row(
              children: [
                UserAvatar(
                  photoUrl: photoUrl,
                  name: title.isEmpty ? 'Espacio' : title,
                  radius: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isEmpty ? 'Espacio' : title,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description.isEmpty ? 'Sin descripcion' : description,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(type == 'channel' ? 'Canal' : 'Grupo')),
                if (onlyAdminsCanPost)
                  const Chip(label: Text('Solo admins publican')),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.link_rounded),
                title: const Text('Invitacion por enlace'),
                subtitle: Text(inviteLink),
                trailing: IconButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: inviteLink));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enlace copiado.')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded),
                ),
              ),
            ),
            if (isAdmin) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _editDetails(context, ref),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar datos'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pickSpaceMedia(context, ref, true),
                    icon: const Icon(Icons.photo_camera_back_outlined),
                    label: const Text('Foto'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pickSpaceMedia(context, ref, false),
                    icon: const Icon(Icons.panorama_outlined),
                    label: const Text('Portada'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final code = await ref
                          .read(chatsRepositoryProvider)
                          .regenerateInviteCode(chatId);
                      if (!context.mounted) return;
                      await Clipboard.setData(
                        ClipboardData(text: 'messeya://join/$code'),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Nuevo enlace creado y copiado.'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Nuevo enlace'),
                  ),
                ],
              ),
            ],
            if (type == 'channel' && isAdmin) ...[
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Canal solo lectura'),
                subtitle: const Text(
                  'Solo admins y moderadores pueden publicar.',
                ),
                value: onlyAdminsCanPost,
                onChanged: (value) async {
                  await ref.read(chatsRepositoryProvider).setOnlyAdminsCanPost(
                        chatId: chatId,
                        enabled: value,
                      );
                },
              ),
            ],
            if (isOwner) ...[
              const SizedBox(height: 8),
              Text(
                'Como propietario puedes transferir el grupo o canal desde la lista de miembros.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _editDetails(BuildContext context, WidgetRef ref) async {
    final titleController = TextEditingController(text: title);
    final descriptionController = TextEditingController(text: description);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Descripcion'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Guardar cambios'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (saved != true) return;
    await ref.read(chatsRepositoryProvider).updateSpaceDetails(
          chatId: chatId,
          title: titleController.text,
          description: descriptionController.text,
        );
  }

  Future<void> _pickSpaceMedia(
    BuildContext context,
    WidgetRef ref,
    bool isPhoto,
  ) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null) return;
    await ref.read(chatsRepositoryProvider).updateSpaceMedia(
          chatId: chatId,
          photoFile: isPhoto ? File(file.path) : null,
          coverFile: isPhoto ? null : File(file.path),
        );
  }
}

class _SpaceMemberTile extends ConsumerWidget {
  const _SpaceMemberTile({
    required this.chatId,
    required this.userId,
    required this.currentUserId,
    required this.isAdmin,
    required this.isOwner,
    required this.ownerId,
    required this.adminIds,
    required this.moderatorIds,
  });

  final String chatId;
  final String userId;
  final String currentUserId;
  final bool isAdmin;
  final bool isOwner;
  final String ownerId;
  final List<String> adminIds;
  final List<String> moderatorIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userState = ref.watch(userProfileProvider(userId));

    return userState.when(
      data: (user) {
        if (user == null) return const SizedBox.shrink();

        final userIsOwner = ownerId == user.uid;
        final userIsAdmin = adminIds.contains(user.uid);
        final userIsModerator = moderatorIds.contains(user.uid);
        final canManage = isAdmin && user.uid != currentUserId;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: UserAvatar(
              photoUrl: user.photoUrl,
              name: user.name,
            ),
            title: Text(user.name),
            subtitle: Text(
              userIsOwner
                  ? '@${user.username} - Propietario'
                  : userIsAdmin
                      ? '@${user.username} - Admin'
                      : userIsModerator
                          ? '@${user.username} - Moderador'
                          : '@${user.username}',
            ),
            trailing: canManage
                ? PopupMenuButton<String>(
                    onSelected: (value) async {
                      final repository = ref.read(chatsRepositoryProvider);
                      if (value == 'make_admin') {
                        await repository.updateMemberRole(
                          chatId: chatId,
                          userId: user.uid,
                          role: 'admin',
                          enabled: true,
                        );
                      } else if (value == 'remove_admin') {
                        await repository.updateMemberRole(
                          chatId: chatId,
                          userId: user.uid,
                          role: 'admin',
                          enabled: false,
                        );
                      } else if (value == 'make_moderator') {
                        await repository.updateMemberRole(
                          chatId: chatId,
                          userId: user.uid,
                          role: 'moderator',
                          enabled: true,
                        );
                      } else if (value == 'remove_moderator') {
                        await repository.updateMemberRole(
                          chatId: chatId,
                          userId: user.uid,
                          role: 'moderator',
                          enabled: false,
                        );
                      } else if (value == 'transfer_owner') {
                        await repository.transferOwnership(
                          chatId: chatId,
                          newOwner: user,
                        );
                      } else if (value == 'expel') {
                        await repository.removeMember(
                          chatId: chatId,
                          user: user,
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      if (!userIsAdmin)
                        const PopupMenuItem(
                          value: 'make_admin',
                          child: Text('Hacer admin'),
                        ),
                      if (userIsAdmin && !userIsOwner)
                        const PopupMenuItem(
                          value: 'remove_admin',
                          child: Text('Quitar admin'),
                        ),
                      if (!userIsModerator)
                        const PopupMenuItem(
                          value: 'make_moderator',
                          child: Text('Hacer moderador'),
                        ),
                      if (userIsModerator)
                        const PopupMenuItem(
                          value: 'remove_moderator',
                          child: Text('Quitar moderador'),
                        ),
                      if (isOwner)
                        const PopupMenuItem(
                          value: 'transfer_owner',
                          child: Text('Transferir propiedad'),
                        ),
                      if (!userIsOwner)
                        const PopupMenuItem(
                          value: 'expel',
                          child: Text('Expulsar miembro'),
                        ),
                    ],
                  )
                : null,
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
