import 'package:flutter/material.dart' show Colors, Material;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/widgets/port_ui/port_ui.dart';

Widget toolHost(Widget child, {double width = 520}) => PortApp(
  home: Align(
    alignment: Alignment.topCenter,
    child: SizedBox(
      width: width,
      child: SingleChildScrollView(
        child: Material(color: Colors.transparent, child: child),
      ),
    ),
  ),
);

Future<void> tapToolKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
