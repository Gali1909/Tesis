import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BleService {
  static final BleService instance = BleService._init();
  BleService._init();

  Future<bool> solicitarPermisos() async {
    final estados = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    return estados.values.every((estado) => estado.isGranted);
  }

  Future<bool> bluetoothDisponible() async {
    return await FlutterBluePlus.isSupported;
  }

  Stream<List<ScanResult>> get resultadosEscaneo => FlutterBluePlus.scanResults;

  Future<void> iniciarEscaneo({Duration duracion = const Duration(seconds: 8)}) async {
    await FlutterBluePlus.startScan(timeout: duracion);
  }

  Future<void> detenerEscaneo() async {
    await FlutterBluePlus.stopScan();
  }

  Future<void> conectar(BluetoothDevice dispositivo) async {
    await dispositivo.connect();
  }

  Future<void> desconectar(BluetoothDevice dispositivo) async {
    await dispositivo.disconnect();
  }
}
