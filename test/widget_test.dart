// Basic smoke test: the app boots and shows the ready screen.

import 'package:flutter_test/flutter_test.dart';

import 'package:subway_flutter/main.dart';

void main() {
  testWidgets('App boots to the ready screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MinimalRunnerApp());
    await tester.pump();

    expect(find.text('MINIMAL RUNNER'), findsOneWidget);
    expect(find.text('START'), findsOneWidget);
  });
}
