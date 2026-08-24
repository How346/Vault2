# Fixes applied

## Notifications
- Request Android 13+ notification permission during startup.
- Request exact-alarm access on Android where available.
- Added `SCHEDULE_EXACT_ALARM` manifest permission.
- Correctly bind the timezone scheduler to the device's OS timezone.
- Rebuild document and task schedules on app startup.
- Use exact-while-idle scheduling with an inexact fallback.
- Added dedicated notification channels with sound/vibration.
- Replaced runtime-dependent Dart `hashCode` notification IDs with stable IDs.
- Added boot permission already required by the notification plugin.

## Document/image quality
- Gallery imports now keep the original image quality/resolution.
- Camera capture uses maximum image quality without forced 2000px downscaling.
- Crop compression raised to 100.
- Normal document imports no longer auto-enhance, normalize, change saturation, contrast, gamma, or colours.
- Scanner defaults to `Original` instead of applying a colour-changing enhancement.
- Scanner output JPEG quality raised to 100 and forced resizing removed.

## Visual design
- Replaced the old teal-first light theme with the requested premium palette:
  - Top: `#F8FAFF`
  - Middle: `#F1F6FF`
  - Bottom: `#E8F1FF`
  - Primary: `#172B4D`
  - Accent Blue: `#1683FF`
  - Background: `#F8FAFF`
  - Cards: `#FFFFFF`
  - Text: `#101828`
  - Secondary: `#667085`
  - Success: `#0F9D78`
- Added a global light background gradient.
- Updated cards, fields, buttons, dividers, snackbar and progress colours for consistency.
