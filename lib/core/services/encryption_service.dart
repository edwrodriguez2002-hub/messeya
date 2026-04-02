import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final encryptionServiceProvider = Provider((ref) => EncryptionService());

class EncryptionService {
  final _storage = const FlutterSecureStorage();
  final _algorithm = X25519();
  final _cipher = AesGcm.with256bits();

  /// Verifica si existe la clave privada localmente
  Future<bool> hasPrivateKey(String uid) async {
    final key = await _storage.read(key: 'priv_key_$uid');
    return key != null && key.isNotEmpty;
  }

  /// Genera un par de claves X25519 para el usuario.
  Future<String> generateAndStoreKeyPair(String uid) async {
    final keyPair = await _algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKey = await keyPair.extractPrivateKeyBytes();

    await _storage.write(key: 'priv_key_$uid', value: base64Encode(privateKey));
    
    return base64Encode(publicKey.bytes);
  }

  Future<SimpleKeyPair> _getStoredKeyPair(String uid) async {
    final privKeyBase64 = await _storage.read(key: 'priv_key_$uid');
    if (privKeyBase64 == null) throw Exception('No se encontró la clave privada local.');
    
    final seed = base64Decode(privKeyBase64);
    final keyPair = await _algorithm.newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    
    return SimpleKeyPairData(
      seed,
      publicKey: publicKey,
      type: KeyPairType.x25519,
    );
  }

  /// Encrypts for multiple recipients (e.g., sender and receiver)
  Future<String> encryptMessage(String text, Map<String, String> uidToPublicKey) async {
    if (text.isEmpty) return '';

    // 1. Generate a random AES key for the message body
    final aesKey = await _cipher.newSecretKey();
    final aesKeyBytes = await aesKey.extractBytes();
    final nonce = _cipher.newNonce();

    // 2. Encrypt the body with the AES key
    final bodyBox = await _cipher.encrypt(
      utf8.encode(text),
      secretKey: aesKey,
      nonce: nonce,
    );

    // 3. Prepare for DH key exchange
    final ephemeralKeyPair = await _algorithm.newKeyPair();
    final ephemeralPublicKey = await ephemeralKeyPair.extractPublicKey();

    final encryptedKeys = <String, String>{};
    final keyMacs = <String, String>{};

    // 4. Encrypt the AES key for each recipient
    for (var entry in uidToPublicKey.entries) {
      final recipientPublicKey = SimplePublicKey(
        base64Decode(entry.value),
        type: KeyPairType.x25519,
      );

      final sharedSecret = await _algorithm.sharedSecretKey(
        keyPair: ephemeralKeyPair,
        remotePublicKey: recipientPublicKey,
      );

      final keyBox = await _cipher.encrypt(
        aesKeyBytes,
        secretKey: sharedSecret,
        nonce: nonce, // We can reuse the same nonce for the key encryption
      );

      encryptedKeys[entry.key] = base64Encode(keyBox.cipherText);
      keyMacs[entry.key] = base64Encode(keyBox.mac.bytes);
    }

    return jsonEncode({
      'v': '2', // Version 2
      'ephemeralKey': base64Encode(ephemeralPublicKey.bytes),
      'nonce': base64Encode(nonce),
      'bodyCipherText': base64Encode(bodyBox.cipherText),
      'bodyMac': base64Encode(bodyBox.mac.bytes),
      'keys': encryptedKeys,
      'macs': keyMacs,
    });
  }

  Future<String> decryptMessage(String encryptedJson, String myUid) async {
    try {
      final payload = jsonDecode(encryptedJson) as Map<String, dynamic>;
      
      // VERSION 2: Multi-recipient
      if (payload['v'] == '2') {
        final encryptedKeys = payload['keys'] as Map<String, dynamic>;
        final keyMacs = payload['macs'] as Map<String, dynamic>;

        if (!encryptedKeys.containsKey(myUid)) {
          return "[No tienes acceso a este mensaje]";
        }

        final ephemeralKey = SimplePublicKey(
          base64Decode(payload['ephemeralKey']),
          type: KeyPairType.x25519,
        );

        final myKeyPair = await _getStoredKeyPair(myUid);
        final sharedSecret = await _algorithm.sharedSecretKey(
          keyPair: myKeyPair,
          remotePublicKey: ephemeralKey,
        );

        final nonce = base64Decode(payload['nonce']);
        
        // Decrypt the AES key
        final aesKeyBytes = await _cipher.decrypt(
          SecretBox(
            base64Decode(encryptedKeys[myUid]),
            nonce: nonce,
            mac: Mac(base64Decode(keyMacs[myUid])),
          ),
          secretKey: sharedSecret,
        );
        
        final aesKey = await _cipher.newSecretKeyFromBytes(aesKeyBytes);

        // Decrypt the body
        final decryptedBytes = await _cipher.decrypt(
          SecretBox(
            base64Decode(payload['bodyCipherText']),
            nonce: nonce,
            mac: Mac(base64Decode(payload['bodyMac'])),
          ),
          secretKey: aesKey,
        );

        return utf8.decode(decryptedBytes);
      }

      // VERSION 1: Original single-recipient (fallback)
      final ephemeralKey = SimplePublicKey(
        base64Decode(payload['ephemeralKey']),
        type: KeyPairType.x25519,
      );
      final nonce = base64Decode(payload['nonce']);
      final cipherText = base64Decode(payload['cipherText']);
      final macBytes = base64Decode(payload['mac'] ?? '');

      final myKeyPair = await _getStoredKeyPair(myUid);
      final sharedSecret = await _algorithm.sharedSecretKey(
        keyPair: myKeyPair,
        remotePublicKey: ephemeralKey,
      );

      final decryptedBytes = await _cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
        secretKey: sharedSecret,
      );

      return utf8.decode(decryptedBytes);
    } catch (e) {
      return "[Error al descifrar mensaje]";
    }
  }

  /// Legacy version for single recipient (used by Cloud Functions if needed)
  Future<String> encryptMessageLegacy(String text, String recipientPublicKeyBase64) async {
    if (text.isEmpty) return '';
    
    final recipientPublicKey = SimplePublicKey(
      base64Decode(recipientPublicKeyBase64),
      type: KeyPairType.x25519,
    );

    final ephemeralKeyPair = await _algorithm.newKeyPair();
    final sharedSecret = await _algorithm.sharedSecretKey(
      keyPair: ephemeralKeyPair,
      remotePublicKey: recipientPublicKey,
    );

    final secretBox = await _cipher.encrypt(
      utf8.encode(text),
      secretKey: sharedSecret,
    );

    final ephemeralPublicKey = await ephemeralKeyPair.extractPublicKey();

    final payload = {
      'ephemeralKey': base64Encode(ephemeralPublicKey.bytes),
      'nonce': base64Encode(secretBox.nonce),
      'cipherText': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    };

    return jsonEncode(payload);
  }
}
