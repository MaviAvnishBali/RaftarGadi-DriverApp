import 'package:flutter_test/flutter_test.dart';
import 'package:driver_app/services/driver_alert_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Driver app boots up cleanly with alert service ready', () {
    final service = DriverAlertService();
    expect(service.isAlertActive, isFalse);
    expect(service.activeBookingId, isNull);
  });
}
