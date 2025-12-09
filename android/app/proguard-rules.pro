# Keep Spotify SDK classes
-keep class com.spotify.** { *; }
-keep interface com.spotify.** { *; }

# Keep Jackson annotations and classes used by Spotify
-dontwarn com.fasterxml.jackson.**
-keep class com.fasterxml.jackson.** { *; }

# Keep annotation classes
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-dontwarn com.spotify.base.annotations.**

# Keep all classes referenced by Spotify
-keep class * extends com.fasterxml.jackson.databind.deser.std.StdDeserializer
-keep class * extends com.fasterxml.jackson.databind.ser.std.StdSerializer

# Keep methods with annotations
-keepclassmembers class * {
    @com.google.errorprone.annotations.* <methods>;
    @javax.annotation.* <methods>;
    @com.spotify.base.annotations.* <methods>;
}
