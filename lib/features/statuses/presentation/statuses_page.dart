import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/models/status_item.dart';
import '../../../shared/widgets/async_value_widget.dart';
import '../../../shared/widgets/fullscreen_image_page.dart';
import '../../../shared/widgets/messeya_ui.dart';
import '../../../shared/widgets/profile_aware_avatar.dart';
import '../../auth/data/auth_repository.dart';
import '../../linked_devices/data/linked_devices_repository.dart';
import '../../profile/data/profile_repository.dart';
import '../data/statuses_repository.dart';
import 'status_video_player_page.dart';

class StatusesPage extends ConsumerStatefulWidget {
  const StatusesPage({super.key});

  @override
  ConsumerState<StatusesPage> createState() => _StatusesPageState();
}

class _StatusesPageState extends ConsumerState<StatusesPage> {
  final _controller = TextEditingController();
  bool _publishing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _publishStatus({
    File? imageFile,
    File? videoFile,
  }) async {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty && imageFile == null && videoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agrega texto, imagen o video para publicar.'),
        ),
      );
      return;
    }

    setState(() => _publishing = true);
    try {
      await ref.read(statusesRepositoryProvider).createStatus(
            text: trimmed,
            imageFile: imageFile,
            videoFile: videoFile,
          );
      _controller.clear();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Estado publicado.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _openComposer() async {
    final picker = ImagePicker();
    File? imageFile;
    File? videoFile;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nuevo estado',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _controller,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Comparte algo con tus contactos',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final file = await picker.pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 85,
                          );
                          if (file == null) return;
                          setModalState(() {
                            imageFile = File(file.path);
                            videoFile = null;
                          });
                        },
                        icon: const Icon(Icons.image_outlined),
                        label: Text(
                          imageFile == null
                              ? 'Agregar imagen'
                              : 'Imagen seleccionada',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final file = await picker.pickVideo(
                            source: ImageSource.gallery,
                          );
                          if (file == null) return;
                          setModalState(() {
                            videoFile = File(file.path);
                            imageFile = null;
                          });
                        },
                        icon: const Icon(Icons.videocam_outlined),
                        label: Text(
                          videoFile == null
                              ? 'Agregar video'
                              : 'Video seleccionado',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _publishing
                          ? null
                          : () => _publishStatus(
                                imageFile: imageFile,
                                videoFile: videoFile,
                              ),
                      child: _publishing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Publicar estado'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openStatusDetails({
    required BuildContext context,
    required String currentUserId,
    required StatusItem status,
  }) async {
    await ref.read(statusesRepositoryProvider).markViewed(
          status.id,
          viewerUserId: currentUserId,
        );

    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final isMine = status.userId == currentUserId;
        final viewerNames = ref.watch(statusViewersProvider(status.viewedBy));

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    status.userName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text('@${status.username}'),
                  if (status.text.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(status.text),
                  ],
                  if (status.mediaType == 'image' &&
                      status.mediaUrl.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => FullscreenImagePage(
                                imageUrl: status.mediaUrl,
                                heroTag: 'status-image-${status.id}',
                                caption: status.text,
                              ),
                            ),
                          );
                        },
                        child: Hero(
                          tag: 'status-image-${status.id}',
                          child: Image.network(
                            status.mediaUrl,
                            width: double.infinity,
                            height: 260,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (status.mediaType == 'video' &&
                      status.mediaUrl.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.play_circle_outline_rounded),
                        title: const Text('Video del estado'),
                        subtitle: const Text('Toca para abrir el reproductor'),
                        onTap: () async {
                          if (!context.mounted) return;
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => StatusVideoPlayerPage(
                                videoUrl: status.mediaUrl,
                                title: status.userName,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  if (isMine) ...[
                    const SizedBox(height: 18),
                    Text(
                      'Vistas',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    viewerNames.when(
                      data: (names) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Total: ${names.length}'),
                          const SizedBox(height: 8),
                          for (final name in names)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text('- $name'),
                            ),
                        ],
                      ),
                      loading: () => const CircularProgressIndicator(),
                      error: (_, __) =>
                          const Text('No se pudieron cargar las vistas.'),
                    ),
                  ] else ...[
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _showReplyComposer(status);
                        },
                        icon: const Icon(Icons.reply_rounded),
                        label: const Text('Responder estado'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showReplyComposer(StatusItem status) async {
    final controller = TextEditingController();
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        var sending = false;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Responder a ${status.userName}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Escribe una respuesta para este estado',
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: sending
                            ? null
                            : () async {
                                setModalState(() => sending = true);
                                try {
                                  await ref
                                      .read(statusesRepositoryProvider)
                                      .replyToStatus(
                                        status: status,
                                        text: controller.text,
                                      );
                                  if (context.mounted) {
                                    Navigator.of(context).pop(true);
                                  }
                                } catch (error) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          error.toString().replaceFirst(
                                                'Exception: ',
                                                '',
                                              ),
                                        ),
                                      ),
                                    );
                                  }
                                  setModalState(() => sending = false);
                                }
                              },
                        child: sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Enviar respuesta'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    controller.dispose();
    if (submitted == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Respuesta enviada al chat.')),
      );
    }
  }

  Future<void> _deleteStatus(StatusItem status) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Borrar estado'),
          content: const Text(
            'Este estado dejara de estar visible para tus contactos. ¿Quieres borrarlo?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Borrar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await ref.read(statusesRepositoryProvider).deleteStatus(status.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Estado borrado.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final statuses = ref.watch(statusesProvider);
    final currentUserId = ref.watch(effectiveMessagingUserIdProvider);
    final desktopSession = ref.watch(desktopClientSessionProvider);
    final isDesktopLinked = ref.watch(currentUserProvider)?.isAnonymous == true;

    return Scaffold(
      body: MesseyaBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 18, bottom: 16),
                  child: MesseyaTopBar(
                    title: 'Estados',
                    actions: [
                      const MesseyaRoundIconButton(icon: Icons.search_rounded),
                      MesseyaRoundIconButton(
                        icon: Icons.more_vert_rounded,
                        onTap: () => context.push('/statuses/hidden'),
                      ),
                    ],
                  ),
                ),
                if (isDesktopLinked)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: MesseyaPanel(
                      padding: const EdgeInsets.all(14),
                      borderRadius: 22,
                      child: Text(
                        desktopSession.valueOrNull?.ownerName.isNotEmpty == true
                            ? 'Estas viendo estados desde Windows vinculado a ${desktopSession.valueOrNull!.ownerName}. La publicacion sigue disponible solo en Android.'
                            : 'Estas viendo estados desde Windows. La publicacion sigue disponible solo en Android.',
                      ),
                    ),
                  ),
                if (!isDesktopLinked) _OwnStatusCard(onTap: _openComposer),
                const SizedBox(height: 18),
                MesseyaSectionLabel(
                  'Estados recientes',
                  trailing: MesseyaPillButton(
                    label: 'Privacidad',
                    icon: Icons.lock_outline_rounded,
                    onTap: () => context.push('/statuses/hidden'),
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: AsyncValueWidget(
                    value: statuses,
                    data: (items) {
                      if (items.isEmpty) {
                        return const Center(
                          child: Text(
                              'Todavia no hay estados. Publica el primero.'),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.only(top: 2, bottom: 140),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 14),
                        itemBuilder: (context, index) {
                          final status = items[index];
                          final isMine = status.userId == currentUserId;
                          return _StatusTile(
                            status: status,
                            isMine: isMine,
                            currentUserId: currentUserId,
                            onTap: () => _openStatusDetails(
                              context: context,
                              currentUserId: currentUserId,
                              status: status,
                            ),
                            onDelete:
                                isMine ? () => _deleteStatus(status) : null,
                            trailingText: isMine
                                ? '${status.viewedBy.length} vistas'
                                : _relativeStatusTime(status.createdAt),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _relativeStatusTime(DateTime? date) {
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    return 'Hace ${diff.inDays} d';
  }
}

class _OwnStatusCard extends ConsumerWidget {
  const _OwnStatusCard({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appUser = ref.watch(currentAppUserProvider);
    return appUser.when(
      data: (user) {
        if (user == null) return const SizedBox.shrink();
        return MesseyaPanel(
          child: Column(
            children: [
              Row(
                children: [
                  ProfileAwareAvatar(
                    userId: user.uid,
                    fallbackPhotoUrl: user.photoUrl,
                    name: user.name,
                    radius: 34,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '@${user.username}',
                          style: const TextStyle(
                            color: MesseyaUi.textMuted,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(22),
                child: Ink(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: MesseyaUi.accent,
                        child: Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      SizedBox(width: 14),
                      Text(
                        'Añade un estado',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.status,
    required this.isMine,
    required this.currentUserId,
    required this.onTap,
    required this.trailingText,
    this.onDelete,
  });

  final StatusItem status;
  final bool isMine;
  final String currentUserId;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final String trailingText;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: isMine
                          ? const [Color(0xFF5BA7FF), Color(0xFF74F0B5)]
                          : const [Color(0xFFE5F0A2), Color(0xFF74F0B5)],
                    ),
                  ),
                  child: ProfileAwareAvatar(
                    userId: status.userId,
                    fallbackPhotoUrl: status.userPhoto,
                    name: status.userName,
                    radius: 30,
                  ),
                ),
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: isMine ? MesseyaUi.accent : MesseyaUi.success,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: const Color(0xFF111A33), width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status.userName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@${status.username}',
                    style: const TextStyle(
                      color: MesseyaUi.textMuted,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
            ),
            if (isMine)
              IconButton(
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.white,
                ),
              )
            else
              Text(
                trailingText,
                style: const TextStyle(
                  color: MesseyaUi.textMuted,
                  fontSize: 18,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
