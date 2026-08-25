# Firebase / FCM integration

- Android Firebase config: `android/app/google-services.json`
- Firebase project: `wallet-102f8`
- Android package: `com.docwallet.doc_wallet`
- Flutter packages: `firebase_core`, `firebase_messaging`
- Foreground FCM messages are displayed through the existing local notification service.
- Background notification messages are handled by Firebase/Android automatically.
- The app logs the current FCM registration token. Do not commit server credentials or service-account keys.

After extracting the project, run `flutter pub get` and build the Android app.
