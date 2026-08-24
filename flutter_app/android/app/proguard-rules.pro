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
