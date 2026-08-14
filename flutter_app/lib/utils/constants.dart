import 'package:flutter/material.dart';

class HiveBoxes {
  static const documents = 'documents_box';
  static const categories = 'categories_box';
  static const profiles = 'profiles_box';
  static const tasks = 'tasks_box';
  static const settings = 'settings_box';
}

class SettingsKeys {
  static const themeMode = 'theme_mode';
  static const biometricEnabled = 'biometric_enabled';
  static const maskByDefault = 'mask_by_default';
  static const reminderDaysBefore = 'reminder_days_before';
  static const onboarded = 'onboarded';
  static const activeProfile = 'active_profile';
  static const lockOnBackground = 'lock_on_background';
  static const appLockEnabled = 'app_lock_enabled';
}


class SecureKeys {
  static const pinHash = 'pin_hash';
  static const pinSalt = 'pin_salt';
}

/// Categories that always exist and cannot be deleted.
class DefaultCategories {
  static const seed = <Map<String, dynamic>>[
    {'id': 'aadhaar', 'name': 'Aadhaar', 'icon': 0xe7fd, 'color': 0xFF2E7D32, 'mask': true},
    {'id': 'pan', 'name': 'PAN Card', 'icon': 0xe19a, 'color': 0xFF1565C0, 'mask': true},
    {'id': 'dl', 'name': 'Driving Licence', 'icon': 0xe1d7, 'color': 0xFFEF6C00, 'mask': true},
    {'id': 'rc', 'name': 'Vehicle RC', 'icon': 0xe1d5, 'color': 0xFF6A1B9A, 'mask': false},
    {'id': 'passport', 'name': 'Passport', 'icon': 0xe071, 'color': 0xFFAD1457, 'mask': true},
    {'id': 'marksheet', 'name': 'Marksheets', 'icon': 0xe80c, 'color': 0xFF00838F, 'mask': false},
    {'id': 'insurance', 'name': 'Insurance', 'icon': 0xe32a, 'color': 0xFF4527A0, 'mask': false},
    {'id': 'other', 'name': 'Others', 'icon': 0xe2c7, 'color': 0xFF455A64, 'mask': false},
  ];
}

const kCardRadius = 20.0;
const kPagePadding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);
