import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Draft {
  final String id;
  final String subject;
  final String text;
  final List<String> recipientIds;
  final List<String> recipientNames;
  final DateTime updatedAt;

  Draft({
    required this.id,
    required this.subject,
    required this.text,
    required this.recipientIds,
    required this.recipientNames,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'subject': subject,
      'text': text,
      'recipientIds': recipientIds,
      'recipientNames': recipientNames,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Draft.fromMap(Map<String, dynamic> map) {
    return Draft(
      id: map['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      subject: map['subject'] ?? '',
      text: map['text'] ?? '',
      recipientIds: List<String>.from(map['recipientIds'] ?? []),
      recipientNames: List<String>.from(map['recipientNames'] ?? []),
      updatedAt: map['updatedAt'] != null 
          ? DateTime.parse(map['updatedAt']) 
          : DateTime.now(),
    );
  }
}

final draftsRepositoryProvider = Provider<DraftsRepository>((ref) {
  return DraftsRepository();
});

final draftsListProvider = FutureProvider.autoDispose<List<Draft>>((ref) async {
  return ref.watch(draftsRepositoryProvider).getDrafts();
});

class DraftsRepository {
  static const String _key = 'messeya_drafts_list';

  Future<void> saveDraft(Draft draft) async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await getDrafts();
    
    final index = drafts.indexWhere((d) => d.id == draft.id);
    if (index != -1) {
      drafts[index] = draft;
    } else {
      drafts.insert(0, draft);
    }

    final data = drafts.map((d) => d.toMap()).toList();
    await prefs.setString(_key, jsonEncode(data));
  }

  Future<List<Draft>> getDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data == null) return [];
    try {
      final List<dynamic> list = jsonDecode(data);
      return list.map((item) => Draft.fromMap(item)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> deleteDraft(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await getDrafts();
    drafts.removeWhere((d) => d.id == id);
    final data = drafts.map((d) => d.toMap()).toList();
    await prefs.setString(_key, jsonEncode(data));
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
