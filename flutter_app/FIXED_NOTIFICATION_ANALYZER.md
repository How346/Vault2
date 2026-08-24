# Notification analyzer fix

Fixed notification_service.dart:
- Removed unused `_activeNotificationColor`.
- Removed unused `_lateNotificationColor`.
- Removed the misplaced Material import/constants.
- Restored valid Dart directive ordering: imports/directives come before declarations.
- Preserved the existing reminder, image, ongoing notification, overdue timer, and tap-to-stop implementation.
