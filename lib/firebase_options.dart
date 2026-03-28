import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'Configura Firebase para web o usa flutterfire configure.',
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError('Messeya esta configurada solo para Android.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCo1GmzrN0ArG5Yyy-sxz8scX1iR71cy70',
    appId: '1:353282297748:android:1fb00eb58a9d627d2a8981',
    messagingSenderId: '353282297748',
    projectId: 'messeya-chat-6fec8',
    storageBucket: 'messeya-chat-6fec8.firebasestorage.app',
  );
}
