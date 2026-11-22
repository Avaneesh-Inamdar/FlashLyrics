# Flutter specific rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep Flutter embedding
-keep class io.flutter.embedding.** { *; }

# Play Core (deferred components) - ignore missing classes
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Audio Service
-keep class com.ryanheise.audioservice.** { *; }
-keep class com.google.android.exoplayer2.** { *; }

# Just Audio
-keep class com.ryanheise.just_audio.** { *; }

# Permission Handler
-keep class com.baseflow.permissionhandler.** { *; }

# Keep model classes if using JSON serialization
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Preserve enums
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# WorkManager / Room (used by Google Play services and plugins). R8 under
# AGP 9 strips the generated WorkDatabase_Impl otherwise, which crashes the
# app at startup ("Failed to create an instance of androidx.work.impl.WorkDatabase").
-keep class * extends androidx.room.RoomDatabase { <init>(...); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class androidx.work.impl.** { *; }
-keep class androidx.work.** { *; }
-keep class androidx.startup.** { *; }
-dontwarn androidx.work.**
-dontwarn androidx.room.**
