import 'package:flutter/material.dart';

import '../models/equipo.dart';
import '../services/database_helper.dart';
import '../services/juego_vivo_db.dart';
import 'juego_lineup_screen.dart';

const Color _fondo = Color(0xFF14171C);
const Color _superficie = Color(0xFF1E232B);
const Color _cian = Color(0xFF0ABDCF);
const Color _textoSuave = Color(0xFF9AA4B2);

/// Si hay un juego en curso lo retoma; si no, pide los datos para iniciar uno.
class JuegoVivoInicioScreen extends StatefulWidget {
  const JuegoVivoInicioScreen({super.key});

  @override
  State<JuegoVivoInicioScreen> createState() => _JuegoVivoInicioScreenState();
}

class _JuegoVivoInicioScreenState extends State<JuegoVivoInicioScreen> {
  List<Equipo> _rivales = [];
  int? _rivalId;
  DateTime _fecha = DateTime.now();
  bool _local = true;
  bool _cargando = true;
  bool _creando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final db = DatabaseHelper.instance;
    final enCurso = await db.obtenerJuegoEnCurso();
    final rivales = await db.obtenerEquiposRivales();
    if (!mounted) return;
    if (enCurso != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => JuegoLineupScreen(juegoId: enCurso['juego_id'] as int),
        ),
      );
      return;
    }
    setState(() {
      _rivales = rivales;
      _cargando = false;
    });
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _vista(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _elegirFecha() async {
    final f = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (f != null) setState(() => _fecha = f);
  }

  Future<void> _iniciar() async {
    if (_creando) return;
    setState(() => _creando = true);
    try {
      final id = await DatabaseHelper.instance.iniciarJuegoVivo(
        fecha: _iso(_fecha),
        rivalId: _rivalId,
        propioLocal: _local,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => JuegoLineupScreen(juegoId: id)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _creando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo iniciar el juego: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fondo,
      appBar: AppBar(
        backgroundColor: _fondo,
        foregroundColor: Colors.white,
        title: const Text('NUEVO JUEGO EN VIVO'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _superficie,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('FECHA',
                          style: TextStyle(color: _textoSuave, fontSize: 12, letterSpacing: 2)),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: _elegirFecha,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, color: _cian, size: 18),
                              const SizedBox(width: 10),
                              Text(
                                _vista(_fecha),
                                style: const TextStyle(color: Colors.white, fontSize: 18),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('RIVAL',
                          style: TextStyle(color: _textoSuave, fontSize: 12, letterSpacing: 2)),
                      DropdownButton<int?>(
                        isExpanded: true,
                        value: _rivalId,
                        dropdownColor: _superficie,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('Sin rival')),
                          for (final e in _rivales)
                            DropdownMenuItem<int?>(value: e.equipoId, child: Text(e.nombre)),
                        ],
                        onChanged: (v) => setState(() => _rivalId = v),
                      ),
                      if (_rivales.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'No hay rivales creados. Puedes crearlos en "Equipos y rivales" o asignar el rival despues, desde Record y juegos.',
                            style: TextStyle(color: _textoSuave, fontSize: 12),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Material(color: Colors.transparent, child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: _cian,
                        title: const Text('Mi equipo juega de local',
                            style: TextStyle(color: Colors.white)),
                        subtitle: Text(
                          _local ? 'Batea en la baja de cada entrada' : 'Batea en la alta de cada entrada',
                          style: const TextStyle(color: _textoSuave, fontSize: 12),
                        ),
                        value: _local,
                        onChanged: (v) => setState(() => _local = v),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _creando ? null : _iniciar,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('INICIAR JUEGO',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _cian,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ),
    );
  }
}