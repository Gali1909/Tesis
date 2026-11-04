import 'package:flutter/material.dart';

import '../services/cambios_db.dart';
import '../services/database_helper.dart';
import '../services/juego_lineup_db.dart';
import '../services/juego_vivo_db.dart';

const Color _fondo = Color(0xFF14171C);
const Color _superficie = Color(0xFF1E232B);
const Color _cian = Color(0xFF0ABDCF);
const Color _textoSuave = Color(0xFF9AA4B2);

const List<String> _posiciones = [
  'C', '1B', '2B', '3B', 'SS', 'LF', 'CF', 'RF', 'BD',
];

class CambiosScreen extends StatefulWidget {
  final int juegoId;

  const CambiosScreen({super.key, required this.juegoId});

  @override
  State<CambiosScreen> createState() => _CambiosScreenState();
}

class _CambiosScreenState extends State<CambiosScreen> {
  Map<String, dynamic>? _lanzador;
  List<Map<String, dynamic>> _lanzadores = [];
  List<Map<String, dynamic>> _lineup = [];
  List<Map<String, dynamic>> _banca = [];
  Map<int, List<String>> _posJugadores = {};
  bool _cargando = true;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  String _mensaje(Object e) => e.toString().replaceFirst('Bad state: ', '');

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _cargar() async {
    final db = DatabaseHelper.instance;
    final juego = await db.obtenerJuegoVivo(widget.juegoId);
    if (!mounted) return;
    if (juego == null || juego['estado'] != 'en_juego') {
      Navigator.pop(context, true);
      return;
    }
    final lanzador = await db.obtenerLanzadorPropioActual(widget.juegoId);
    final lanzadores = await db.obtenerLanzadoresPropios();
    final lineup = await db.obtenerLineupJuego(widget.juegoId);
    final banca = await db.obtenerBancaBateadores(widget.juegoId);
    final pos = await db.obtenerPosicionesJugadores();
    if (!mounted) return;
    setState(() {
      _lanzador = lanzador;
      _lanzadores = lanzadores;
      _lineup = lineup;
      _banca = banca;
      _posJugadores = pos;
      _cargando = false;
    });
  }

  Future<void> _ejecutar(Future<void> Function() accion) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      await accion();
    } catch (e) {
      _aviso(_mensaje(e));
    }
    await _cargar();
    if (mounted) setState(() => _ocupado = false);
  }

  String _etiqueta(Map<String, dynamic> j) =>
      '${j['numero'] != null ? '#${j['numero']} ' : ''}${j['nombre']}';

  Future<void> _cambiarLanzador() async {
    final actualId = _lanzador?['jugador_id'];
    final opciones = _lanzadores.where((l) => l['jugador_id'] != actualId).toList();
    if (opciones.isEmpty) {
      _aviso('No hay otros lanzadores en tu equipo.');
      return;
    }
    final id = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Nuevo lanzador'),
        children: [
          for (final l in opciones)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, l['jugador_id'] as int),
              child: Text(_etiqueta(l)),
            ),
        ],
      ),
    );
    if (id == null) return;
    await _ejecutar(() => DatabaseHelper.instance.cambiarLanzadorPropio(widget.juegoId, id));
  }

  Future<void> _sustituir(Map<String, dynamic> puesto) async {
    if (_banca.isEmpty) {
      _aviso('No hay mas bateadores disponibles en tu equipo.');
      return;
    }
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoSustitucion(
        orden: puesto['orden'] as int,
        saliente: _etiqueta(puesto),
        posicionActual: puesto['posicion'] as String?,
        banca: _banca,
        posiciones: _posJugadores,
      ),
    );
    if (r == null) return;
    await _ejecutar(
      () => DatabaseHelper.instance.sustituirBateadorPropio(
        widget.juegoId,
        orden: puesto['orden'] as int,
        nuevoId: r['id'] as int,
        posicion: r['pos'] as String?,
      ),
    );
  }

  Widget _tarjeta({required Widget hijo}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(16),
      ),
      child: hijo,
    );
  }

  Widget _filaPuesto(Map<String, dynamic> p) {
    final pos = p['posicion'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${p['orden']}',
              style: const TextStyle(color: _cian, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          Expanded(
            child: Text(
              '${_etiqueta(p)}${pos != null ? '  ($pos)' : ''}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.swap_horiz, color: _cian),
            onPressed: _ocupado ? null : () => _sustituir(p),
          ),
        ],
      ),
    );
  }

  Widget _cuerpo() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _tarjeta(
          hijo: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'LANZADOR ACTUAL',
                style: TextStyle(color: _textoSuave, fontSize: 12, letterSpacing: 2),
              ),
              const SizedBox(height: 4),
              Text(
                _lanzador == null ? 'Sin lanzador' : _etiqueta(_lanzador!),
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: _ocupado ? null : _cambiarLanzador,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('CAMBIAR LANZADOR'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _tarjeta(
          hijo: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ORDEN AL BATE',
                style: TextStyle(color: _textoSuave, fontSize: 12, letterSpacing: 2),
              ),
              const SizedBox(height: 4),
              for (final p in _lineup) _filaPuesto(p),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Los cambios aplican desde el siguiente turno y no se pueden hacer con un turno abierto. Los turnos ya registrados no cambian.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _textoSuave, fontSize: 12),
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
        title: const Text('CAMBIOS'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _cuerpo(),
    );
  }
}

class _DialogoSustitucion extends StatefulWidget {
  final int orden;
  final String saliente;
  final String? posicionActual;
  final List<Map<String, dynamic>> banca;
  final Map<int, List<String>> posiciones;

  const _DialogoSustitucion({
    required this.orden,
    required this.saliente,
    required this.posicionActual,
    required this.banca,
    required this.posiciones,
  });

  @override
  State<_DialogoSustitucion> createState() => _DialogoSustitucionState();
}

class _DialogoSustitucionState extends State<_DialogoSustitucion> {
  int? _id;
  String? _pos;

  List<String> _permitidas(int? id) {
    if (id == null) return const [];
    final juega = widget.posiciones[id] ?? const <String>[];
    return _posiciones.where((p) => p == 'BD' || juega.contains(p)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Sustituir al #${widget.orden}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sale: ${widget.saliente}'),
          const SizedBox(height: 8),
          DropdownButton<int?>(
            isExpanded: true,
            value: _id,
            hint: const Text('Jugador que entra'),
            items: [
              for (final b in widget.banca)
                DropdownMenuItem<int?>(
                  value: b['jugador_id'] as int,
                  child: Text(
                    '${b['numero'] != null ? '#${b['numero']} ' : ''}${b['nombre']}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() {
              _id = v;
              _pos = _permitidas(v).contains(widget.posicionActual)
                  ? widget.posicionActual
                  : null;
            }),
          ),
          DropdownButton<String?>(
            isExpanded: true,
            value: _pos,
            hint: const Text('Posicion'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('-')),
              for (final p in _permitidas(_id))
                DropdownMenuItem<String?>(value: p, child: Text(p)),
            ],
            onChanged: (v) => setState(() => _pos = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),
        TextButton(
          onPressed: _id == null
              ? null
              : () => Navigator.pop(context, {'id': _id, 'pos': _pos}),
          child: const Text('SUSTITUIR'),
        ),
      ],
    );
  }
}