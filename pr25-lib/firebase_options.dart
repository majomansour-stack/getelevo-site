// File generated from google-services.json and GoogleService-Info.plist
// Project: elevo-aa4ed  |  Sender ID: 309177379607
// Do not edit manually — regenerate by running `flutterfire configure` if
// the Firebase project changes.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      // Web is not configured — push notifications run on mobile only.
      // Returning android options as a safe fallback so Firebase.initializeApp()
      // does not throw when accidentally called on web (main.dart guards with !kIsWeb).
      return android;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return android;
    }
  }

  /// Android — sourced from google-services.json
  /// package_name: com.getelevo.app
  /// mobilesdk_app_id: 1:309177379607:android:b49381d983654d9ac6a552
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBuxR69pGN3mNDyxQZPYiW-Dol8pFKzQ8M',
    appId: '1:309177379607:android:b49381d983654d9ac6a552',
    messagingSenderId: '309177379607',
    projectId: 'elevo-aa4ed',
    storageBucket: 'elevo-aa4ed.firebasestorage.app',
  );

  /// iOS — sourced from GoogleService-Info.plist
  /// BUNDLE_ID: com.getelevo.app
  /// GOOGLE_APP_ID: 1:309177379607:ios:4a1cb397471adad9c6a552
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAaF5BpD8bKlpgH2Wis-fLY8tN1nl0YGMI',
    appId: '1:309177379607:ios:4a1cb397471adad9c6a552',
    messagingSenderId: '309177379607',
    projectId: 'elevo-aa4ed',
    storageBucket: 'elevo-aa4ed.firebasestorage.app',
    iosBundleId: 'com.getelevo.app',
  );
}
