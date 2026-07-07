# Пути проекта на диске D:

Все служебные файлы проекта хранятся рядом с кодом, а не в `C:\Users\...`.

| Путь | Назначение |
|------|------------|
| `D:\ucheba\podchet_kalloriy\.ssh\` | SSH-ключ для VPS Timeweb |
| `D:\ucheba\podchet_kalloriy\.cache\pub\` | Кэш Dart/Flutter пакетов |
| `D:\ucheba\podchet_kalloriy\.cache\gradle\` | Кэш Gradle (сборка APK) |
| `D:\ucheba\podchet_kalloriy\.cache\staging\` | Временные файлы деплоя |
| `D:\flutter\` | Flutter SDK |

## SSH

Подключение к серверу:

```powershell
ssh -F D:\ucheba\podchet_kalloriy\.ssh\config podchet-vps
```

Если SSH ругается на права ключа:

```powershell
.\config\fix-ssh-permissions.ps1
```

## Сборка APK

```powershell
cd mobile
.\build_apk.bat
```

Кэш pub и gradle пишется в `.cache\` на диске D:.

## Деплой

```powershell
cd backend
.\deploy\deploy-to-vps.ps1
```

Скрипт автоматически использует ключ из `.ssh\` проекта.
