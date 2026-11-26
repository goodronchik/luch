import 'package:flutter_test/flutter_test.dart';
import 'package:luch/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('LuchApp renders 4 navigation tabs', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const LuchApp());
    await tester.pump();

    expect(find.text('Луч'), findsOneWidget);
    expect(find.text('Отправить'), findsOneWidget);
    expect(find.text('Принять'), findsOneWidget);
    expect(find.text('Устройства'), findsOneWidget);
    expect(find.text('Настройки'), findsOneWidget);
  });
}
