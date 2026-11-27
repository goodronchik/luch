import 'package:flutter_test/flutter_test.dart';
import 'package:luch/core/app_version.dart';
import 'package:luch/main.dart';
import 'package:luch/state/luch_controller.dart';
import 'package:luch/ui/screens/home_screen.dart';
import 'package:luch/ui/screens/settings_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('LuchApp renders 4 navigation tabs and build version', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const LuchApp());
    await tester.pump();

    expect(find.text('Луч'), findsOneWidget);
    expect(find.text('Отправить'), findsOneWidget);
    expect(find.text('Принять'), findsOneWidget);
    expect(find.text('Устройства'), findsOneWidget);
    expect(find.text('Настройки'), findsOneWidget);

    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(ListView),
      ),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Версия сборки: $luchAppVersion (build $luchAppBuildNumber)'),
      findsOneWidget,
    );

    await tester.tap(find.text('Принять'));
    await tester.pumpAndSettle();
    final qrField = tester.widget<TextField>(find.byType(TextField));
    expect(qrField.controller?.text, isEmpty);
  });

  testWidgets('Deep link switches HomeScreen to Receive tab', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = LuchController();
    await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: controller)));
    await tester.runAsync(() async {
      await controller.initialize();
      await controller.handleIncomingLink('https://main.lolkas.ru/luch/#p=invalid');
    });
    await tester.pump();

    // Automatically switched to Receive tab.
    expect(find.byType(TextField), findsOneWidget);
    controller.dispose();
  });
}
