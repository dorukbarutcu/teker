import 'package:flutter_test/flutter_test.dart';
import 'package:teker/main.dart';

void main() {
  testWidgets('Teker app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TekerApp());
    expect(find.byType(TekerApp), findsOneWidget);
  });
}
