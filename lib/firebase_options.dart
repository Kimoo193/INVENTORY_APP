import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) throw UnsupportedError('Web not supported');
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError('Platform not supported');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCg92js1Kwg6V9eBg3GPB24cQAaIe-ydFo',
    appId: '1:854488781428:android:45ce27f6b9f3a4b55ef721',
    messagingSenderId: '854488781428',
    projectId: 'karamstock-1a3a5',
    storageBucket: 'karamstock-1a3a5.firebasestorage.app',
  );
}