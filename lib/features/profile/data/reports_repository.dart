import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../shared/models/app_user.dart';

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  return ReportsRepository(
    ref.watch(firestoreProvider),
    ref.watch(firebaseAuthProvider),
  );
});

class ReportsRepository {
  ReportsRepository(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  Future<void> reportUser({
    required AppUser user,
    String reason = 'spam',
    String details = '',
  }) async {
    final reporterId = _auth.currentUser?.uid;
    if (reporterId == null) throw Exception('No hay sesion activa.');

    await _firestore.collection('reports').add({
      'reporterId': reporterId,
      'reportedUserId': user.uid,
      'reportedUsername': user.username,
      'reason': reason,
      'details': details.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'open',
    });
  }
}
