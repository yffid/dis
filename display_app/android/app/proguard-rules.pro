# ProGuard rules for Hermosa POS Display App
# Keep NearPay SDK classes
-keep class io.nearpay.** { *; }
-keep class io.nearpay.sdk.** { *; }

# Keep Flutter classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# Keep WebSocket classes
-keep class io.crossbar.autobahn.** { *; }

# Fix missing Play Core classes
-dontwarn com.google.android.play.core.**

# Remove logging in release
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
    public static *** w(...);
    public static *** e(...);
}

# Optimize
-optimizations !code/simplification/arithmetic,!code/simplification/cast,!field/*,!class/merging/*
-optimizationpasses 3
-allowaccessmodification
-dontpreverify
-dontwarn
