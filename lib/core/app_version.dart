/// Single source of truth for application build version.
/// Versioning rules:
/// - Minimal fixes: append letter (`0.0.2a`, `0.0.2b`, `0.0.2c`, ...) and increment `buildNumber`.
/// - Regular fixes/releases: increment patch digit (`0.0.1`, `0.0.2`, `0.0.3`, ...) and increment `buildNumber`.
/// - Big features/releases: increment minor digit (`0.1.0`, `0.2.0`, `0.3.0`, ...) and increment `buildNumber`.
/// Keep `pubspec.yaml` (`<semver>+<buildNumber>`) and `CHANGELOG.md` in sync.
const String luchAppVersion = '0.0.2a';
const String luchSemver = '0.0.2';
const int luchAppBuildNumber = 2;
const String luchFullVersion = '$luchAppVersion+$luchAppBuildNumber';
