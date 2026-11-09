import 'package:flutter_test/flutter_test.dart';
import 'package:entrenador_app/services/pantalla_protocolo.dart';

void main() {
  test('armar: cabecera, largo little-endian y xor', () {
    final t = PantallaProtocolo.armar(0x10, 3, [1, 2, 3]);
    expect(t.sublist(0, 2), [0xAA, 0x55]);
    expect(t[2], 0x10);
    expect(t[3], 3);
    expect(t[4] | (t[5] << 8), 3);
    expect(t.sublist(6, 9), [1, 2, 3]);
    var x = 0;
    for (var i = 2; i < t.length - 1; i++) {
      x ^= t[i];
    }
    expect(t.last, x);
  });

  test('armar: largo de 2 bytes para payloads grandes', () {
    final t = PantallaProtocolo.armar(0x12, 255, List.filled(1500, 7));
    expect(t[4] | (t[5] << 8), 1500);
    expect(t.length, 6 + 1500 + 1);
  });
}