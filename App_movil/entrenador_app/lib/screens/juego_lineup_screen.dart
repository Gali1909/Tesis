import 'package:flutter/material.dart';

import '../services/database_helper.dart';
import '../services/juego_lineup_db.dart';
import '../services/juego_vivo_db.dart';
import '../services/lineups_db.dart';
import 'juego_vivo_screen.dart';
import 'lineups_screen.dart';

const Color _fondo = Color(0xFF14171C);
const Color _superficie = Color(0xFF1E232B);
const Color _cian = Color(0xFF0ABDCF);
const Color _rojo = Color(0xFFE63946);
const Color _textoSuave = Color(0xFF9AA4B2);

const int _puestos = 9;

/// Elige un lineup guardado (9 al bate + lanzador). Si el juego ya tiene
/// lineup, pasa directo a la pantalla del juego.
class JuegoLineupScreen extends StatefulWidget {
  final int juegoId;

  const JuegoLineupScreen({super.key, required this.juegoId});

  @override
  State<JuegoLineupScreen> createState() => _JuegoLineupScreenState();
}

class _JuegoLineupScreenState extends State<JuegoLineupScreen> {
  List<Map<String, dynamic>> _lineups = [];
  List<Map<String, dynamic>> _vista = [];
  int? _lineupId;
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final db = DatabaseHelper.instance;
    final existente = await db.obtenerLineupJuego(widget.juegoId);
    if (!mounted) return;
    if (existente.isNotEmpty) {
      _irAlJuego();
      return;
    }
    final lineups = await db.obtenerLineups();
    if (_lineupId != null &&
        !lineups.any((l) => l['lineup_id'] == _lineupId)) {
      _lineupId = null;
    }
    final vista = _lineupId == null
        ? <Map<String, dynamic>>[]
        : await db.obtenerPuestosLineup(_lineupId!);
    if (!mounted) return;
    setState(() {
      _lineups = lineups;
      _vista = vista;
      _cargando = false;
    });
  }

  void _irAlJuego() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => JuegoVivoScreen(juegoId: widget.juegoId)),
    );
  }

  Map<String, dynamic>? get _seleccionado {
    for (final l in _lineups) {
      if (l['lineup_id'] == _lineupId) return l;
    }
    return null;
  }

  String? get _lanzador => _seleccionado?['lanzador'] as String?;

  Future<void> _elegirLineup(int? id) async {
    final vista = id == null
        ? <Map<String, dynamic>>[]
        : await DatabaseHelper.instance.obtenerPuestosLineup(id);
    if (!mounted) return;
    setState(() {
      _lineupId = id;
      _vista = vista;
    });
  }

  Future<void> _administrar() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LineupsScreen()),
    );
    if (!mounted) return;
    await _cargar();
  }

  String _lineaPuesto(Map<String, dynamic> p) {
    final numero = p['numero'];
    final pos = p['posicion'];
    final prefijo = numero != null ? '#$numero ' : '';
    final sufijo = pos != null ? '  ($pos)' : '';
    return '${p['orden']}. $prefijo${p['nombre']}$sufijo';
  }

  bool get _completo =>
      _lineupId != null && _vista.length >= _puestos && _lanzador != null;

  Future<void> _comenzar() async {
    if (!_completo || _guardando) return;
    setState(() => _guardando = true);
    try {
      await DatabaseHelper.instance.copiarLineupAJuego(widget.juegoId, _lineupId!);
      if (!mounted) return;
      _irAlJuego();
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo comenzar el juego: ${e.toString().replaceFirst('Bad state: ', '')}',
          ),
        ),
      );
    }
  }

  Future<void> _descartar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar juego'),
        content: const Text('Se borra este juego en curso. No se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DESCARTAR'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await DatabaseHelper.instance.descartarJuegoVivo(widget.juegoId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo descartar: $e')),
      );
      return;
    }
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Widget _cuerpo() {
    final sinLineups = _lineups.isEmpty;
    return ListView(
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
              const Text(
                'LINEUP',
                style: TextStyle(color: _textoSuave, fontSize: 12, letterSpacing: 2),
              ),
              if (sinLineups)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Todavia no tienes lineups guardados. Crea uno y vuelve aqui.',
                    style: TextStyle(color: _textoSuave),
                  ),
                )
              else
                DropdownButton<int?>(
                  isExpanded: true,
                  value: _lineupId,
                  hint: const Text('Elegir lineup', style: TextStyle(color: _textoSuave)),
                  dropdownColor: _superficie,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  items: [
                    for (final l in _lineups)
                      DropdownMenuItem<int?>(
                        value: l['lineup_id'] as int,
                        child: Text(
                          l['nombre'] as String,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _elegirLineup,
                ),
              if (_lineupId != null && _vista.length < _puestos)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Este lineup tiene menos de 9 puestos. Editalo en Lineups.',
                    style: TextStyle(color: _rojo, fontSize: 12),
                  ),
                ),
              if (_vista.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final p in _vista)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      _lineaPuesto(p),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
              ],
              if (_lineupId != null) ...[
                const SizedBox(height: 10),
                if (_lanzador != null)
                  Text(
                    'Lanzador: $_lanzador',
                    style: const TextStyle(
                      color: _cian,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                else
                  const Text(
                    'Este lineup no tiene lanzador. Editalo en Lineups.',
                    style: TextStyle(color: _rojo, fontSize: 12),
                  ),
              ],
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _administrar,
                icon: const Icon(Icons.format_list_numbered),
                label: const Text('ADMINISTRAR LINEUPS'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: (_completo && !_guardando) ? _comenzar : null,
          icon: const Icon(Icons.sports_baseball),
          label: const Text(
            'COMENZAR JUEGO',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _cian,
            foregroundColor: Colors.black,
            disabledBackgroundColor: const Color(0xFF2A303A),
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fondo,
      appBar: AppBar(
        backgroundColor: _fondo,
        foregroundColor: Colors.white,
        title: const Text('ALINEACION'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'descartar') _descartar();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'descartar', child: Text('Descartar juego')),
            ],
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _cuerpo(),
    );
  }
}