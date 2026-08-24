# ML Kit text recognition ships optional language bundles (Chinese, Devanagari,
# Japanese, Korean). We only bundle Latin, so tell R8 the rest are fine to miss.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }

# Flutter / plugins
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.**

# Play Core (referenced by Flutter deferred components)
-dontwarn com.google.android.play.core.**

# flutter_local_notifications 17.x uses Gson to persist scheduled
# notification data. R8 must preserve generic signatures or Gson
# TypeToken fails at runtime in release builds.
-keepattributes Signature
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Preserve Gson generic metadata and annotations used by notification cache.
-keepattributes InnerClasses,EnclosingMethod,*Annotation*
-dontwarn com.google.gson.**
