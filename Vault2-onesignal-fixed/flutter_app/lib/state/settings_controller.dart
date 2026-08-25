import 'package:flutter/material.dart';

import '../services/security_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';

class SettingsController extends ChangeNotifier {
  final _box = StorageService.instance.settings;

  ThemeMode get themeMode =>
      ThemeMode.values[_box.get(SettingsKeys.themeMode, defaultValue: 0) as int];

  bool get biometricEnabled =>
      _box.get(SettingsKeys.biometricEnabled, defaultValue: true) as bool;

  bool get maskByDefault =>
      _box.get(SettingsKeys.maskByDefault, defaultValue: true) as bool;

  int get reminderDaysBefore =>
      _box.get(SettingsKeys.reminderDaysBefore, defaultValue: 30) as int;

  bool get onboarded => _box.get(SettingsKeys.onboarded, defaultValue: false) as bool;

  /// When false the app opens straight into the wallet (no PIN / biometric).
  bool get appLockEnabled =>
      _box.get(SettingsKeys.appLockEnabled, defaultValue: true) as bool;

  Future<void> setThemeMode(ThemeMode mode) async {
    await _box.put(SettingsKeys.themeMode, mode.index);
    notifyListeners();
  }

  Future<void> setBiometricEnabled(bool v) async {
    await _box.put(SettingsKeys.biometricEnabled, v);
    notifyListeners();
  }

  Future<void> setMaskByDefault(bool v) async {
    await _box.put(SettingsKeys.maskByDefault, v);
    notifyListeners();
  }

  Future<void> setReminderDaysBefore(int v) async {
    await _box.put(SettingsKeys.reminderDaysBefore, v);
    notifyListeners();
  }

  Future<void> setPin(String pin) async {
    await SecurityService.instance.setPin(pin);
    await _box.put(SettingsKeys.onboarded, true);
    await _box.put(SettingsKeys.appLockEnabled, true);
    notifyListeners();
  }

  /// Turning the lock off removes the stored PIN hash entirely.
  Future<void> setAppLockEnabled(bool v) async {
    await _box.put(SettingsKeys.appLockEnabled, v);
    if (!v) await SecurityService.instance.clearPin();
    notifyListeners();
  }
}
