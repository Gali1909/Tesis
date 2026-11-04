import 'package:flutter/material.dart';

import '../models/equipo.dart';
import '../models/jugador.dart';
import '../services/database_helper.dart';
import '../services/lineups_db.dart';

const Color _fondo = Color(0xFF14171C);
const Color _superficie = Color(0xFF1E232B);
const Color _cian = Color(0xFF0ABDCF);
const Color _textoSuave = Color(0xFF9AA4B2);
const Color _rojo = Color(0xFFE63946);

const int _puestos = 9;
const List<String> _posiciones = [
  'C', '1B', '2B', '3B', 'SS', 'LF', 'CF', 'RF', 'BD',
];

class LineupEditorScreen extends StatefulWidget {
  final int? lineupId;

  const LineupEditorScreen({super.key, this.lineupId});

  @override
  State<LineupEditorScreen> createState() => _LineupEditorScreenState();
}

class _LineupEditorScreenState extends State<LineupEditorScreen> {
  final TextEditingController _nombre = TextEditingController();
  List<Jugador> _bateadores = [];
  List<Jugador> _lanzadores = [];
  final List<int?> _ids = List<int?>.filled(_puestos, null);
  final List<String?> _pos = List<String?>.filled(_puestos, null);
  int? _lanzadorId;
  Map<int, Set<String>> _posJugador = {};
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final db = DatabaseHelper.instance;
    final equipos = await db.obtenerEquipos();
    int? propioId;
    for (final Equipo e in equipos) {
      if (e.tipo == 'propio') {
        propioId = e.equipoId;
        break;
      }
    }
    var todos = <Jugador>[];
    if (propioId != null) {
      todos = await db.obtenerJugadoresPorEquipo(propioId);
    }
    final bateadores = todos.where((j) => j.rol == 'bateador').toList();
    final lanzadores = todos.where((j) => j.rol == 'lanzador').toList();
    final rawDb = await db.database;
    final filasPos = await rawDb.query('jugador_posicion');
    final posJugador = <int, Set<String>>{};
    for (final f in filasPos) {
      posJugador
          .putIfAbsent(f['jugador_id'] as int, () => <String>{})
          .add(f['posicion'] as String);
    }

    var nombre = '';
    int? lanzadorId;
    var puestos = <Map<String, dynamic>>[];
    if (widget.lineupId != null) {
      final info = await db.obtenerLineup(widget.lineupId!);
      nombre = (info?['nombre'] as String?) ?? '';
      lanzadorId = info?['lanzador_id'] as int?;
      puestos = await db.obtenerPuestosLineup(widget.lineupId!);
    }
    if (!mounted) return;

    final validos = bateadores.map((j) => j.jugadorId).toSet();
    final usados = <int>{};
    for (var i = 0; i < _puestos; i++) {
      _ids[i] = null;
      _pos[i] = null;
      if (i < puestos.length) {
        final id = puestos[i]['jugador_id'] as int;
        if (validos.contains(id) && usados.add(id)) {
          _ids[i] = id;
          _pos[i] = puestos[i]['posicion'] as String?;
          final permitidas = <String>{'BD', ...(posJugador[id] ?? <String>{})};
          if (_pos[i] != null && !permitidas.contains(_pos[i])) _pos[i] = null;
        }
      }
    }
    if (lanzadorId != null && !lanzadores.any((j) => j.jugadorId == lanzadorId)) {
      lanzadorId = null;
    }
    _lanzadorId = lanzadorId;
    _nombre.text = nombre;
    setState(() {
      _bateadores = bateadores;
      _posJugador = posJugador;
      _lanzadores = lanzadores;
      _cargando = false;
    });
  }

  Map<String, List<int>> _repetidas() {
    final porPos = <String, List<int>>{};
    for (var i = 0; i < _ids.length; i++) {
      final p = _pos[i];
      if (_ids[i] == null || p == null) continue;
      porPos.putIfAbsent(p, () => <int>[]).add(i);
    }
    porPos.removeWhere((_, l) => l.length < 2);
    return porPos;
  }

  Set<int> _filasRepetidas() => {
        for (final l in _repetidas().values) ...l,
      };

  String _nombreDe(int? id) {
    for (final j in _bateadores) {
      if (j.jugadorId == id) return j.nombre;
    }
    return '?';
  }

  String? _avisoDuplicadas() {
    final r = _repetidas();
    if (r.isEmpty) return null;
    final partes = <String>[];
    r.forEach((pos, filas) {
      final nombres = filas.map((i) => '${i + 1}. ${_nombreDe(_ids[i])}').join(', ');
      partes.add('$pos: $nombres');
    });
    return 'Posicion repetida en el lineup:\n${partes.join('\n')}';
  }

  List<String> _posicionesDe(int? jugadorId) {
    if (jugadorId == null) return const [];
    final juega = _posJugador[jugadorId] ?? <String>{};
    return _posiciones.where((p) => p == 'BD' || juega.contains(p)).toList();
  }

  String _etiqueta(Jugador j) =>
      '${j.numero != null ? '#${j.numero} ' : ''}${j.nombre}';

  bool get _completo =>
      _nombre.text.trim().isNotEmpty &&
      _ids.every((i) => i != null) &&
      _lanzadorId != null;

  Future<void> _guardar() async {
    if (!_completo || _guardando) return;
    setState(() => _guardando = true);
    try {
      await DatabaseHelper.instance.guardarLineup(
        lineupId: widget.lineupId,
        nombre: _nombre.text.trim(),
        lanzadorId: _lanzadorId,
        puestos: [
          for (var i = 0; i < _ids.length; i++)
            {'jugador_id': _ids[i], 'posicion': _pos[i]},
        ],
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el lineup: $e')),
      );
    }
  }

  Widget _fila(int i) {
    final usados = <int>{
      for (var k = 0; k < _ids.length; k++)
        if (k != i && _ids[k] != null) _ids[k]!,
    };
    final repetida = _filasRepetidas().contains(i);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: repetida ? const Color(0x33E63946) : null,
        border: Border.all(color: repetida ? _rojo : Colors.transparent),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${i + 1}',
              style: const TextStyle(
                color: _cian,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          Expanded(
            child: DropdownButton<int?>(
              isExpanded: true,
              value: _ids[i],
              hint: const Text('Bateador', style: TextStyle(color: _textoSuave)),
              dropdownColor: _superficie,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              items: [
                for (final j in _bateadores)
                  if (!usados.contains(j.jugadorId))
                    DropdownMenuItem<int?>(
                      value: j.jugadorId,
                      child: Text(_etiqueta(j), overflow: TextOverflow.ellipsis),
                    ),
              ],
              onChanged: (v) => setState(() {
                _ids[i] = v;
                if (_pos[i] != null && !_posicionesDe(v).contains(_pos[i])) {
                  _pos[i] = null;
                }
              }),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 76,
            child: DropdownButton<String?>(
              isExpanded: true,
              value: _pos[i],
              hint: const Text('Pos', style: TextStyle(color: _textoSuave)),
              dropdownColor: _superficie,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('-')),
                for (final p in _posicionesDe(_ids[i]))
                  DropdownMenuItem<String?>(value: p, child: Text(p)),
              ],
              onChanged: (v) => setState(() => _pos[i] = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cuerpo() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _superficie,
            borderRadius: BorderRadius.circular(16),
          ),
          child: TextField(
            controller: _nombre,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Nombre del lineup',
              labelStyle: TextStyle(color: _textoSuave),
              hintText: 'Ej. Titular vs derechos',
              hintStyle: TextStyle(color: _textoSuave),
            ),
          ),
        ),
        const SizedBox(height: 12),
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
                'ORDEN AL BATE (JUGADORES DE POSICION)',
                style: TextStyle(color: _textoSuave, fontSize: 12, letterSpacing: 2),
              ),
              const SizedBox(height: 4),
              for (var i = 0; i < _puestos; i++) _fila(i),
            ],
          ),
        ),
        if (_avisoDuplicadas() != null)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0x33E63946),
              border: Border.all(color: _rojo),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _avisoDuplicadas()!,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        if (_bateadores.length < _puestos)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Tu equipo tiene menos de 9 jugadores de posicion. Agrega los que falten en Jugadores.',
              style: TextStyle(color: _textoSuave, fontSize: 12),
            ),
          ),
        const SizedBox(height: 12),
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
                'LANZADOR',
                style: TextStyle(color: _textoSuave, fontSize: 12, letterSpacing: 2),
              ),
              DropdownButton<int?>(
                isExpanded: true,
                value: _lanzadorId,
                hint: Text(
                  _lanzadores.isEmpty ? 'No hay lanzadores en tu equipo' : 'Elegir lanzador',
                  style: const TextStyle(color: _textoSuave),
                ),
                dropdownColor: _superficie,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                items: [
                  for (final j in _lanzadores)
                    DropdownMenuItem<int?>(
                      value: j.jugadorId,
                      child: Text(_etiqueta(j), overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _lanzadorId = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: (_completo && !_guardando) ? _guardar : null,
          icon: const Icon(Icons.save),
          label: const Text(
            'GUARDAR LINEUP',
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
        title: Text(widget.lineupId == null ? 'NUEVO LINEUP' : 'EDITAR LINEUP'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _cuerpo(),
    );
  }
}