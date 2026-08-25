# Doc Wallet — Offline Privacy-First Document Wallet (Flutter)

100% local. No Firebase, no cloud, no network calls. Everything lives in Hive +
app-private file storage on the device.

## Run / build

```bash
cd flutter_app
flutter pub get
flutter run                 # debug
flutter build apk --release # APK
```

> This code is source-only in this repo; it is not compiled or previewed here.

## Structure

```
lib/
  main.dart                  app bootstrap, Hive init, providers
  app.dart                   MaterialApp, Material 3 themes, routing
  models/                    Hive models + manual TypeAdapters (no build_runner)
  services/                  storage, notifications, security, sharing
  state/                     ChangeNotifier controllers
  screens/                   lock, home hub, category, add/edit, viewer, settings
  widgets/                   reusable cards / animations
  utils/                     masking, formatting, constants
```

## Permissions

Android `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.USE_BIOMETRIC"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
```

Add inside `<application>` for cropping:

```xml
<activity android:name="com.yalantis.ucrop.UCropActivity"
  android:screenOrientation="portrait"
  android:theme="@style/Theme.AppCompat.Light.NoActionBar"/>
```

`MainActivity` must extend `FlutterFragmentActivity` (required by `local_auth`).

iOS `Info.plist`: `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`,
`NSFaceIDUsageDescription`.

## Notes

- Files are copied into the app-private documents dir, never shared storage.
- PIN is stored as a salted SHA-256 hash in `flutter_secure_storage`.
- Masking is applied at render/share time; the original value stays intact.
