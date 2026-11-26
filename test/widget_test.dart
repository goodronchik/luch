import 'package:flutter_test/flutter_test.dart';
import 'package:luch/main.dart';

void main() {
  testWidgets('LuchApp renders main navigation tabs', (tester) async {
    await tester.pumpWidget(const LuchApp());
    await tester.pump();

    expect(find.text('Луч'), findsOneWidget);
    expect(find.text('Отправить'), findsOneWidget);
    expect(find.text('Принять'), findsOneWidget);
    expect(find.text('История'), findsOneWidget);
    expect(find.text('Выбрать файлы'), findsOneWidget);
  });
}
