import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/ble_service.dart';

class BleScanScreen extends StatefulWidget {
  const BleScanScreen({super.key});

  @override
  State<BleScanScreen> createState() => _BleScanScreenState();
}

class _BleScanScreenState extends State<BleScanScreen> {
  List<ScanResult> _resultados = [];
  bool _escaneando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    BleService.instance.resultadosEscaneo.listen((resultados) {
      if (!mounted) return;
      setState(() => _resultados = resultados);
    });
  }

  Future<void> _escanear() async {
    setState(() {
      _error = null;
      _resultados = [];
    });

    final permisosOk = await BleService.instance.solicitarPermisos();
    if (!permisosOk) {
      setState(() => _error = 'Permisos de Bluetooth/ubicacion denegados');
      return;
    }

    final soportado = await BleService.instance.bluetoothDisponible();
    if (!soportado) {
      setState(() => _error = 'Este dispositivo no soporta Bluetooth Low Energy');
      return;
    }

    setState(() => _escaneando = true);
    await BleService.instance.iniciarEscaneo();
    setState(() => _escaneando = false);
  }

  Future<void> _conectar(BluetoothDevice dispositivo) async {
    try {
      await BleService.instance.conectar(dispositivo);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Conectado a ${dispositivo.platformName}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al conectar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buscar dispositivos Bluetooth')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: _escaneando ? null : _escanear,
              icon: _escaneando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bluetooth_searching),
              label: Text(_escaneando ? 'Buscando...' : 'Buscar dispositivos'),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: _resultados.isEmpty
                ? const Center(child: Text('Sin dispositivos encontrados todavia'))
                : ListView.builder(
                    itemCount: _resultados.length,
                    itemBuilder: (context, index) {
                      final r = _resultados[index];
                      final nombre = r.device.platformName.isNotEmpty
                          ? r.device.platformName
                          : '(sin nombre)';
                      return ListTile(
                        title: Text(nombre),
                        subtitle: Text('${r.device.remoteId} - RSSI: ${r.rssi}'),
                        trailing: ElevatedButton(
                          onPressed: () => _conectar(r.device),
                          child: const Text('Conectar'),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
