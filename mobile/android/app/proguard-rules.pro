# LeFu / PPBluetoothKit — не обфусцировать (ClassCastException на $Proxy в release)
-keep class com.lefu.ppbase.** { *; }
-keep class com.lefu.ppbluetoothkit.** { *; }
-keep class com.lefu.bluetooth.library.** { *; }
-keep class com.lefu.gson.** { *; }
-keep class com.peng.ppscale.** { *; }
-keep class com.besthealth.** { *; }
-keep class com.example.pp_bluetooth_kit_flutter.** { *; }

-keepattributes Signature, *Annotation*, InnerClasses, EnclosingMethod
-dontwarn com.lefu.**
-dontwarn com.peng.ppscale.**
