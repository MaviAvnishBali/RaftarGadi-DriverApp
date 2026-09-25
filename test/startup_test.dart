import 'package:flutter_test/flutter_test.dart';
import 'package:driver_app/app/bootstrap.dart';
import 'package:driver_app/app/driver_app.dart';

void main() {
  testWidgets('App boots up', (WidgetTester tester) async {
    await bootstrapAndRun(const RaftarDriverApp());
  });
}
