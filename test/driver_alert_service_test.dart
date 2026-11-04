import 'package:flutter_test/flutter_test.dart';
import 'package:driver_app/services/driver_alert_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('DriverAlertService starts inactive with null activeBookingId', () {
    final service = DriverAlertService();
    expect(service.isAlertActive, isFalse);
    expect(service.activeBookingId, isNull);
  });

  test('DriverAlertService stopAlert resets active state cleanly', () async {
    final service = DriverAlertService();
    await service.stopAlert();
    expect(service.isAlertActive, isFalse);
    expect(service.activeBookingId, isNull);
  });
}
