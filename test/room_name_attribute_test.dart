import 'package:copy_cat/services/lan_socket_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('arabic room names stay ascii in the txt attribute', () {
    const name = 'غرفة التقليد';
    final encoded = encodeRoomAttribute(name);
    expect(encoded.contains(RegExp(r'[^\x00-\x7F]')), isFalse);
    expect(roomNameFromAttribute(encoded, 'copycat-ab12'), name);
  });

  test('a missing attribute falls back to the service name', () {
    expect(roomNameFromAttribute(null, 'copycat-ab12'), 'copycat-ab12');
    expect(roomNameFromAttribute('', 'copycat-ab12'), 'copycat-ab12');
    expect(roomNameFromAttribute('null', 'copycat-ab12'), 'copycat-ab12');
  });

  test('plain names pass through', () {
    expect(roomNameFromAttribute('Party', 'copycat-ab12'), 'Party');
  });
}
