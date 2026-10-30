import 'package:firebase_core/firebase_core.dart';

// Public client configuration, filled from the registered Firebase Android app.
// These are application identifiers, not a service-account private key.
class FirebaseConfig {
  static const projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'ducltdd',
  );
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static bool get configured =>
      apiKey.isNotEmpty && appId.isNotEmpty && senderId.isNotEmpty;
  static FirebaseOptions get options => const FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: senderId,
    projectId: projectId,
  );
}
