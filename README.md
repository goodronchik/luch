# Луч (Luch)

Кроссплатформенное устанавливаемое приложение для быстрого обмена файлами между **Android, iOS, Windows и Linux** через **QR-код** по локальной сети Wi-Fi.

## Возможности
- **Прямая передача по локальному Wi-Fi** — без интернета, облачных серверов и сжатия файлов.
- **Потоковая передача** — файлы передаются напрямую с диска на диск (`IOSink` / `File.openRead`), не нагружая оперативную память даже на многогигабайтных видео и архивах.
- **QR-код совместим и с приложением, и с браузером**:
  - На телефоне с приложением «Луч» можно отсканировать QR-код камерой и скачать/отправить файлы в одно касание.
  - На устройстве, где приложение ещё не установлено, тот же QR-код открывает встроенный веб-интерфейс в обычном браузере.
- **Двусторонний сценарий для ПК без камеры**:
  - На Windows / Linux можно распознать QR-код из картинки/скриншота (`zxing2`), вставить ссылку **или** нажать «Показать мой QR для приёма файлов», чтобы отправить файлы с телефона на ПК камерой телефона.
- **Безопасность сессии**: каждая раздача/приём защищены случайным 128-битным токеном и санитизацией имён файлов.

## Сборка устанавливаемых пакетов

### Android (`.apk`)
```bash
flutter build apk --release
# Файл: build/app/outputs/flutter-apk/app-release.apk
```

### iOS (`.ipa`)
Для установки через Xcode на подключённый iPhone:
```bash
flutter run --release
```
Или сборка `.ipa` с подписью / без подписи:
```bash
flutter build ipa
# либо без подписи для AltStore / Sideloadly:
flutter build ios --release --no-codesign
```

### Windows (`.exe` установщик)
```bash
flutter build windows --release
iscc packaging/windows/luch_setup.iss
# Файл: packaging/windows/Output/Luch-Windows-Setup.exe
```

### Linux (`.deb` пакет)
```bash
flutter build linux --release
chmod +x packaging/linux/build_deb.sh
./packaging/linux/build_deb.sh 1.0.0
# Файл: build/deb/luch_1.0.0_amd64.deb
```

### Автоматическая сборка под все 4 ОС в GitHub Actions
В репозитории настроен workflow [build.yml](.github/workflows/build.yml), который автоматически запускает тесты и собирает `.apk`, `.ipa`, `.exe` и `.deb` для всех целевых платформ.

## Тестирование
```bash
flutter analyze
flutter test
```
