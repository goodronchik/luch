/// Single source of truth for application build version.
/// Keep in sync with `pubspec.yaml` (`version:`) and `CHANGELOG.md`.
const String luchAppVersion = '0.0.1';
const int luchAppBuildNumber = 1;
const String luchFullVersion = '$luchAppVersion+$luchAppBuildNumber';
