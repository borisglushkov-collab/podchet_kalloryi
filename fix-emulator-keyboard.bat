@echo off
set "ADB=C:\Users\msi\AppData\Local\Android\Sdk\platform-tools\adb.exe"
echo === Русская клавиатура в эмуляторе ===
"%ADB%" wait-for-device
"%ADB%" shell settings put secure show_ime_with_hard_keyboard 1
"%ADB%" shell settings put secure accessibility_soft_keyboard_mode 1
"%ADB%" shell settings put system system_locales ru-RU,en-US
"%ADB%" shell ime enable com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME
"%ADB%" shell ime set com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME
echo.
echo 1) Нажмите на поле поиска в приложении
echo 2) Внизу появится Gboard - нажмите ГЛОБУС и выберите Русский
echo 3) Или вводите латиницей: omlet, grechka, tvorog
echo.
echo Если физ. клавиатура мешает - перезапустите эмулятор (hw.keyboard=no).
