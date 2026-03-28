import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'hybrid_local_message.dart';

final hybridLocalQueueServiceProvider =
    Provider<HybridLocalQueueService>((ref) {
  return HybridLocalQueueService();
});

final hybridChatMessagesProvider =
    StreamProvider.family<List<HybridLocalMessage>, String>((ref, chatId) {
  return ref
      .watch(hybridLocalQueueServiceProvider)
      .watchMessagesForChat(chatId);
});

final hybridPendingMessagesProvider = StreamProvider<List<HybridLocalMessage>>(
  (ref) => ref.watch(hybridLocalQueueServiceProvider).watchPendingMessages(),
);

class HybridLocalQueueService {
  Database? _database;
  final _changes = StreamController<void>.broadcast();

  Future<void> initialize() async {
    if (_database != null) return;
    final directory = await getApplicationDocumentsDirectory();
    final dbPath = path.join(directory.path, 'messeya_hybrid.db');
    _database = await openDatabase(
      dbPath,
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE hybrid_messages(
            local_id INTEGER PRIMARY KEY AUTOINCREMENT,
            message_uuid TEXT UNIQUE,
            chat_id TEXT NOT NULL,
            sender_id TEXT NOT NULL,
            sender_name TEXT NOT NULL,
            recipient_id TEXT NOT NULL,
            text TEXT NOT NULL,
            created_at_ms INTEGER NOT NULL,
            direction TEXT NOT NULL,
            status TEXT NOT NULL,
            relay_hops_left INTEGER NOT NULL DEFAULT 0,
            last_error TEXT NOT NULL DEFAULT '',
            packet_type TEXT NOT NULL DEFAULT 'message',
            original_sender_id TEXT NOT NULL DEFAULT '',
            retry_count INTEGER NOT NULL DEFAULT 0,
            last_attempt_at_ms INTEGER NOT NULL DEFAULT 0,
            attachment_path TEXT NOT NULL DEFAULT '',
            attachment_name TEXT NOT NULL DEFAULT '',
            voice_duration_ms INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE mesh_seen(
            packet_uuid TEXT PRIMARY KEY,
            packet_type TEXT NOT NULL,
            seen_at_ms INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE mesh_acks(
            ack_uuid TEXT PRIMARY KEY,
            message_uuid TEXT NOT NULL,
            from_user_id TEXT NOT NULL,
            to_user_id TEXT NOT NULL,
            created_at_ms INTEGER NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE hybrid_messages ADD COLUMN packet_type TEXT NOT NULL DEFAULT 'message'",
          );
          await db.execute(
            "ALTER TABLE hybrid_messages ADD COLUMN original_sender_id TEXT NOT NULL DEFAULT ''",
          );
          await db.execute('''
            CREATE TABLE IF NOT EXISTS mesh_seen(
              packet_uuid TEXT PRIMARY KEY,
              packet_type TEXT NOT NULL,
              seen_at_ms INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS mesh_acks(
              ack_uuid TEXT PRIMARY KEY,
              message_uuid TEXT NOT NULL,
              from_user_id TEXT NOT NULL,
              to_user_id TEXT NOT NULL,
              created_at_ms INTEGER NOT NULL
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute(
            "ALTER TABLE hybrid_messages ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0",
          );
          await db.execute(
            "ALTER TABLE hybrid_messages ADD COLUMN last_attempt_at_ms INTEGER NOT NULL DEFAULT 0",
          );
        }
        if (oldVersion < 4) {
          await db.execute(
            "ALTER TABLE hybrid_messages ADD COLUMN attachment_path TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE hybrid_messages ADD COLUMN attachment_name TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE hybrid_messages ADD COLUMN voice_duration_ms INTEGER NOT NULL DEFAULT 0",
          );
        }
      },
    );
  }

  Future<Database> get _db async {
    await initialize();
    return _database!;
  }

  Stream<List<HybridLocalMessage>> watchMessagesForChat(String chatId) async* {
    yield await getMessagesForChat(chatId);
    yield* _changes.stream.asyncMap((_) => getMessagesForChat(chatId));
  }

  Stream<List<HybridLocalMessage>> watchPendingMessages() async* {
    yield await getPendingMessages();
    yield* _changes.stream.asyncMap((_) => getPendingMessages());
  }

  Future<List<HybridLocalMessage>> getMessagesForChat(String chatId) async {
    final db = await _db;
    final rows = await db.query(
      'hybrid_messages',
      where: 'chat_id = ?',
      whereArgs: [chatId],
      orderBy: 'created_at_ms ASC',
    );
    return rows.map(HybridLocalMessage.fromMap).toList();
  }

  Future<List<HybridLocalMessage>> getPendingMessages() async {
    final db = await _db;
    final rows = await db.query(
      'hybrid_messages',
      where:
          "direction = 'outgoing' AND packet_type IN ('message','cloud_text','cloud_attachment_image','cloud_attachment_video','cloud_attachment_file','cloud_voice') AND status != 'cloud_synced'",
      orderBy: 'created_at_ms ASC',
    );
    return rows.map(HybridLocalMessage.fromMap).toList();
  }

  Future<List<HybridLocalMessage>> getPendingMeshPackets({
    int retryCooldownMs = 8000,
    int maxRetryCount = 12,
  }) async {
    final db = await _db;
    final retryBefore = DateTime.now().millisecondsSinceEpoch - retryCooldownMs;
    final rows = await db.query(
      'hybrid_messages',
      where:
          "packet_type IN ('message','ack') AND retry_count < ? AND (last_attempt_at_ms = 0 OR last_attempt_at_ms <= ?) AND status IN ('pending', 'mesh_pending', 'mesh_sent', 'mesh_forwarded', 'ack_pending', 'ack_forwarded')",
      whereArgs: [maxRetryCount, retryBefore],
      orderBy: 'created_at_ms ASC',
    );
    return rows.map(HybridLocalMessage.fromMap).toList();
  }

  Future<bool> exists(String messageUuid) async {
    final db = await _db;
    final rows = await db.query(
      'hybrid_messages',
      columns: ['message_uuid'],
      where: 'message_uuid = ?',
      whereArgs: [messageUuid],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<bool> hasSeenPacket(String packetUuid) async {
    final db = await _db;
    final rows = await db.query(
      'mesh_seen',
      columns: ['packet_uuid'],
      where: 'packet_uuid = ?',
      whereArgs: [packetUuid],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> markPacketSeen(
    String packetUuid, {
    required String packetType,
  }) async {
    final db = await _db;
    await db.insert(
      'mesh_seen',
      {
        'packet_uuid': packetUuid,
        'packet_type': packetType,
        'seen_at_ms': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> insert(HybridLocalMessage message) async {
    final db = await _db;
    await db.insert(
      'hybrid_messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    _changes.add(null);
  }

  Future<void> updateStatus(
    String messageUuid, {
    required String status,
    String? error,
    bool trackAttempt = false,
  }) async {
    final db = await _db;
    if (trackAttempt) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      await db.rawUpdate(
        '''
        UPDATE hybrid_messages
        SET status = ?, retry_count = retry_count + 1, last_attempt_at_ms = ?, last_error = COALESCE(?, last_error)
        WHERE message_uuid = ?
        ''',
        [status, timestamp, error, messageUuid],
      );
    } else {
      await db.update(
        'hybrid_messages',
        {
          'status': status,
          if (error != null) 'last_error': error,
        },
        where: 'message_uuid = ?',
        whereArgs: [messageUuid],
      );
    }
    _changes.add(null);
  }

  Future<void> storeAck({
    required String ackUuid,
    required String messageUuid,
    required String fromUserId,
    required String toUserId,
  }) async {
    final db = await _db;
    await db.insert(
      'mesh_acks',
      {
        'ack_uuid': ackUuid,
        'message_uuid': messageUuid,
        'from_user_id': fromUserId,
        'to_user_id': toUserId,
        'created_at_ms': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> decrementRelayHops(String messageUuid) async {
    final db = await _db;
    await db.rawUpdate(
      'UPDATE hybrid_messages SET relay_hops_left = CASE WHEN relay_hops_left > 0 THEN relay_hops_left - 1 ELSE 0 END WHERE message_uuid = ?',
      [messageUuid],
    );
    _changes.add(null);
  }

  Future<void> clearSyncedForChat(String chatId) async {
    final db = await _db;
    await db.delete(
      'hybrid_messages',
      where: 'chat_id = ? AND status = ?',
      whereArgs: [chatId, 'cloud_synced'],
    );
    _changes.add(null);
  }

  Future<void> touchForRetry(String messageUuid) async {
    final db = await _db;
    await db.update(
      'hybrid_messages',
      {'last_attempt_at_ms': DateTime.now().millisecondsSinceEpoch},
      where: 'message_uuid = ?',
      whereArgs: [messageUuid],
    );
    _changes.add(null);
  }

  Future<void> expirePacket(String messageUuid, {String? error}) async {
    await updateStatus(
      messageUuid,
      status: 'expired',
      error: error,
      trackAttempt: true,
    );
  }
}
