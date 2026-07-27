import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pulsefile/main.dart';

void main() {
  testWidgets('PulseFile application starts', (WidgetTester tester) async {
    await tester.pumpWidget(const PulseFileApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
