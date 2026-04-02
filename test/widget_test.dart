import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:messeya/main.dart';

void main() {
  testWidgets('Messeya smoke test', (WidgetTester tester) async {
    // Ajustado para usar MesseyaApp en lugar de MyApp
    await tester.pumpWidget(const MesseyaApp());

    // Verificamos que la app inicie (puedes ajustar esto según tu pantalla de inicio)
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
