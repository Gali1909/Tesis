import 'dart:async';
import 'dart:math';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'pantalla_protocolo.dart';

/// Conexion BLE con la pantalla del coach (servicio tipo Nordic UART).
class PantallaBle {
  static final PantallaBle instance = PantallaBle._();
  PantallaBle._();

  static final Guid servicio = Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
  static final Guid _charRx = Guid('6e400002-b5a3-f393-e0a9-e50e24dcca9e');
  static final Guid _charTx = Guid('6e400003-b5a3-f393-e0a9-e50e24dcca9e');

  BluetoothDevice? _dispositivo;
  BluetoothCharacteristic? _rx;
  StreamSubscription<List<int>>? _subTx;
  final List<int> _buf = [];
  Completer<int>? _espera;
  int _seq = 0;
  int _seqEsperado = -1;
  int _mtu = 23;

  bool get conectado => _dispositivo != null && _rx != null;
  String get nombre => _dispositivo?.platformName ?? '';

  Future<void> conectar(BluetoothDevice d) async {
    await desconectar();
    if (!d.isConnected) await d.connect();
    try {
      _mtu = await d.requestMtu(247);
    } catch (_) {
      _mtu = 23;
    }
    final servicios = await d.discoverServices();
    BluetoothService? s;
    for (final x in servicios) {
      if (x.uuid == servicio) s = x;
    }
    if (s == null) {
      await d.disconnect();
      throw StateError('Este dispositivo no ofrece el servicio de la pantalla.');
    }
    BluetoothCharacteristic? rx;
    BluetoothCharacteristic? tx;
    for (final c in s.characteristics) {
      if (c.uuid == _charRx) rx = c;
      if (c.uuid == _charTx) tx = c;
    }
    if (rx == null || tx == null) {
      await d.disconnect();
      throw StateError('Faltan las caracteristicas de datos en la pantalla.');
    }
    await tx.setNotifyValue(true);
    _subTx = tx.onValueReceived.listen(_alRecibir);
    d.cancelWhenDisconnected(_subTx!);
    _dispositivo = d;
    _rx = rx;
    _buf.clear();
  }

  Future<void> desconectar() async {
    await _subTx?.cancel();
    _subTx = null;
    final d = _dispositivo;
    _dispositivo = null;
    _rx = null;
    if (d != null && d.isConnected) await d.disconnect();
  }

  void _alRecibir(List<int> datos) {
    _buf.addAll(datos);
    while (_buf.length >= 7) {
      if (_buf[0] != 0xAA || _buf[1] != 0x55) {
        _buf.removeAt(0);
        continue;
      }
      final largo = _buf[4] | (_buf[5] << 8);
      final total = 7 + largo;
      if (largo > PantallaProtocolo.maxPayload) {
        _buf.removeAt(0);
        continue;
      }
      if (_buf.length < total) break;
      var x = 0;
      for (var i = 2; i < total - 1; i++) {
        x ^= _buf[i];
      }
      final ok = x == _buf[total - 1];
      final tipo = _buf[2];
      final seq = _buf[3];
      final estado = largo > 0 ? _buf[6] : 0;
      _buf.removeRange(0, total);
      if (ok &&
          tipo == PantallaProtocolo.tAck &&
          seq == _seqEsperado &&
          _espera != null &&
          !_espera!.isCompleted) {
        _espera!.complete(estado);
      }
    }
  }

  /// Envia un mensaje y espera la confirmacion (ACK) de la pantalla.
  /// Devuelve 0 si la pantalla lo acepto, -1 si no respondio, o el codigo
  /// de error que devolvio la pantalla.
  Future<int> enviar(int tipo, List<int> payload) async {
    final rx = _rx;
    if (rx == null) throw StateError('No hay una pantalla conectada.');
    _seq = (_seq + 1) & 0xFF;
    final seq = _seq;
    _seqEsperado = seq;
    final espera = Completer<int>();
    _espera = espera;
    final trama = PantallaProtocolo.armar(tipo, seq, payload);
    final paso = max(20, min(244, _mtu - 3));
    for (var i = 0; i < trama.length; i += paso) {
      final fin = min(i + paso, trama.length);
      await rx.write(trama.sublist(i, fin), withoutResponse: false);
    }
    return espera.future.timeout(const Duration(seconds: 5), onTimeout: () => -1);
  }
}