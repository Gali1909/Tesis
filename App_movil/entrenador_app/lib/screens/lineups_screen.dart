import 'package:flutter/material.dart';

import '../services/database_helper.dart';
import '../services/lineups_db.dart';
import 'lineup_editor_screen.dart';

const Color _fondo = Color(0xFF14171C);
const Color _superficie = Color(0xFF1E232B);
const Color _cian = Color(0xFF0ABDCF);
const Color _textoSuave = Color(0xFF9AA4B2);

class LineupsScreen extends StatefulWidget {
  const LineupsScreen({super.key});

  @override
  State<LineupsScreen> createState() => _LineupsScreenState();
}

class _LineupsScreenState extends State<LineupsScreen> {
  List<Map<String, dynamic>> _lineups = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final r = await DatabaseHelper.instance.obtenerLineups();
    if (!mounted) return;
    setState(() {
      _lineups = r;
      _cargando = false;
    });
  }

  Future<void> _abrir([int? id]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LineupEditorScreen(lineupId: id)),
    );
    await _cargar();
  }

  Future<void> _eliminar(int id, String nombre) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar lineup'),
        content: Text(
          'Se elimina "$nombre". Los juegos ya iniciados con este lineup no cambian.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ELIMINAR'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DatabaseHelper.instance.eliminarLineup(id);
    await _cargar();
  }

  Widget _tarjeta(Map<String, dynamic> l) {
    final id = l['lineup_id'] as int;
    final nombre = l['nombre'] as String;
    final puestos = (l['puestos'] as int?) ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: _superficie,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onTap: () => _abrir(id),
          title: Text(
            nombre,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            '$puestos puestos',
            style: const TextStyle(color: _textoSuave),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, color: _textoSuave),
            onPressed: () => _eliminar(id, nombre),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fondo,
      appBar: AppBar(
        backgroundColor: _fondo,
        foregroundColor: Colors.white,
        title: const Text('LINEUPS'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrir(),
        backgroundColor: _cian,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('NUEVO LINEUP'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _lineups.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Todavia no hay lineups. Crea el primero con el boton de abajo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _textoSuave),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [for (final l in _lineups) _tarjeta(l)],
                ),
    );
  }
}