// Developer-owned Firebase values are supplied at build time; no shared backend.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const messagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const databaseUrl = String.fromEnvironment('FIREBASE_DATABASE_URL');
  static const storageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
  static const authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');

  static bool get isConfigured => apiKey.isNotEmpty && appId.isNotEmpty &&
      messagingSenderId.isNotEmpty && projectId.isNotEmpty && databaseUrl.isNotEmpty;

  static FirebaseOptions get currentPlatform {
    if (!isConfigured) {
      throw StateError('WAN is not configured. Supply your own config/firebase.local.json; see docs/FIREBASE_SETUP.md.');
    }
    return const FirebaseOptions(apiKey: apiKey, appId: appId,
      messagingSenderId: messagingSenderId, projectId: projectId,
      databaseURL: databaseUrl, storageBucket: storageBucket, authDomain: authDomain);
  }
}
