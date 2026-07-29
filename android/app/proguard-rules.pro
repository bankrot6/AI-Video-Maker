# Flutter proguard rules
# Сохраняем основные классы Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Сохраняем awesome_notifications
-keep class me.carda.awesome_notifications.** { *; }

# Сохраняем uni_links
-keep class name.avioli.unilinks.** { *; }

# Сохраняем camera плагины
-keep class io.flutter.plugins.camera.** { *; }

# Сохраняем Dart классы
-keep class dartffi.** { *; }

# Общие правила для предотвращения проблем с рефлексией
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Не предупреждать о недостающих классах
-dontwarn okio.**
-dontwarn retrofit2.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# Сохраняем методы главного класса приложения
-keep public class * extends android.app.Application
-keep public class * extends android.app.Activity
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver

# Google Play Core (для deferred components)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Flutter deferred components
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }
-keep class io.flutter.app.FlutterPlayStoreSplitApplication { *; }

# RuStore Billing SDK
-keep class ru.rustore.** { *; }
-keep class ru.vk.store.** { *; }
-dontwarn ru.rustore.**
-dontwarn ru.vk.store.**

# VK ID SDK - для корректной работы авторизации и обнаружения сессий
-keep class com.vk.** { *; }
-keep class com.vk.api.** { *; }
-keep class com.vk.auth.** { *; }
-keep class com.vk.id.** { *; }
-keep class com.vk.silentauth.** { *; }
-keep class com.vk.superapp.** { *; }
-dontwarn com.vk.**

# VK SDK - работа с токенами и сессиями
-keep class com.vk.sdk.** { *; }
-keepclassmembers class * {
    @com.vk.api.sdk.** *;
}

# Kotlin Serialization для RuStore/VK SDK
-keepattributes RuntimeVisibleAnnotations,RuntimeVisibleParameterAnnotations
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }
-dontwarn kotlin.**
-dontwarn kotlinx.**

# OkHttp для RuStore/VK SDK
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.** 