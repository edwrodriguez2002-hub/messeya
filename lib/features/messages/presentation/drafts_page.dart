import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../data/drafts_repository.dart';

class DraftsPage extends ConsumerWidget {
  const DraftsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Borradores'),
        backgroundColor: const Color(0xFF1E293B),
      ),
      body: FutureBuilder<List<Draft>>(
        future: ref.read(draftsRepositoryProvider).getDrafts(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final drafts = snapshot.data ?? [];
          if (drafts.isEmpty) {
            return const Center(
              child: Text(
                'No tienes borradores guardados.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: drafts.length,
            separatorBuilder: (context, index) => const Divider(color: Colors.white12),
            itemBuilder: (context, index) {
              final draft = drafts[index];
              return ListTile(
                title: Text(
                  draft.subject.isEmpty ? '(Sin asunto)' : draft.subject,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      draft.text.isEmpty ? '(Sin mensaje)' : draft.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Última edición: ${DateFormat('dd MMM, HH:mm').format(draft.updatedAt)}',
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () async {
                    await ref.read(draftsRepositoryProvider).deleteDraft(draft.id);
                    // Force rebuild
                    (context as Element).markNeedsBuild();
                  },
                ),
                onTap: () {
                  context.push('/compose?draftId=${draft.id}');
                },
              );
            },
          );
        },
      ),
    );
  }
}
