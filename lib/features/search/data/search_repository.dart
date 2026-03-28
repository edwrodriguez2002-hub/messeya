import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../shared/models/app_user.dart';

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return SearchRepository(ref.watch(firestoreProvider));
});

class SearchRepository {
  SearchRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Future<List<AppUser>> searchUsers(
    String query, {
    required String excludeUid,
  }) async {
    // CORRECCIÓN: Si el ID está vacío, devolvemos lista vacía en lugar de error
    if (excludeUid.isEmpty) return [];

    final trimmed = query.trim().toLowerCase();
    
    // Obtenemos bloqueados de forma segura
    final blockedSnapshot = await _firestore
        .collection('users')
        .doc(excludeUid)
        .collection('blocked_users')
        .get();
    final blockedIds = blockedSnapshot.docs.map((doc) => doc.id).toSet();

    final snapshot = await _firestore.collection('users').get();
    return snapshot.docs
        .map(AppUser.fromDoc)
        .where(
          (user) =>
              user.uid.isNotEmpty && // Aseguramos que el usuario encontrado tenga ID
              user.uid != excludeUid &&
              !blockedIds.contains(user.uid) &&
              (trimmed.isEmpty ||
                  user.name.toLowerCase().contains(trimmed) ||
                  user.email.toLowerCase().contains(trimmed) ||
                  user.usernameLower.contains(trimmed)),
        )
        .toList();
  }
}
