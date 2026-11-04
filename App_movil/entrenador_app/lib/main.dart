import 'package:flutter/material.dart';
import 'models/equipo.dart';
import 'services/database_helper.dart';
import 'screens/menu_principal_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper.instance.database;
  runApp(const EntrenadorApp());
}

class EntrenadorApp extends StatelessWidget {
  const EntrenadorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Entrenador',
      debugShowCheckedModeBanner: false,
      home: const _PantallaInicial(),
    );
  }
}

class _PantallaInicial extends StatefulWidget {
  const _PantallaInicial();

  @override
  State<_PantallaInicial> createState() => _PantallaInicialState();
}

class _PantallaInicialState extends State<_PantallaInicial> {
  int? _equipoId;
  String _nombreEquipo = 'Mi Equipo';

  @override
  void initState() {
    super.initState();
    _prepararEquipoDePrueba();
  }

  Future<void> _prepararEquipoDePrueba() async {
    final equipos = await DatabaseHelper.instance.obtenerEquipos();
    if (equipos.isEmpty) {
      final id = await DatabaseHelper.instance.crearEquipo(
        Equipo(nombre: 'Mi Equipo', tipo: 'propio'),
      );
      setState(() => _equipoId = id);
    } else {
      final propio = equipos.firstWhere(
        (e) => e.tipo == 'propio',
        orElse: () => equipos.first,
      );
      setState(() {
        _equipoId = propio.equipoId;
        _nombreEquipo = propio.nombre;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_equipoId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return MenuPrincipalScreen(
      equipoId: _equipoId!,
      nombreEquipo: _nombreEquipo,
      onNombreCambiado: (n) => setState(() => _nombreEquipo = n),
    );
  }
}