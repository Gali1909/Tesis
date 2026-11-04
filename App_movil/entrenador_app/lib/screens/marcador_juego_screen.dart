import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/equipo.dart';
import '../services/database_helper.dart';
import '../services/marcador_db.dart';

const Color _fondoOscuro = Color(0xFF14171C);
const Color _acento = Color(0xFF0ABDCF);

class MarcadorJuegoScreen extends StatefulWidget {
  final int juegoId;

  const MarcadorJuegoScreen({super.key, required this.juegoId});

  @override
  State<MarcadorJuegoScreen> createState() => _MarcadorJuegoScreenState();
}

class _MarcadorJuegoScreenState extends State<MarcadorJuegoScreen> {
  final List<TextEditingController> _propias = [];
  final List<TextEditingController> _rival = [];
  final List<TextEditingController> _descartados = [];
  final TextEditingController _hitsPropios = TextEditingController();
  final TextEditingController _erroresPropios = TextEditingController();
  final TextEditingController _hitsRival = TextEditingController();
  final TextEditingController _erroresRival = TextEditingController();

  List<Equipo> _rivales = [];
  int? _rivalId;
  String _fecha = '';
  String _nombrePropio = 'Mi equipo';
  bool _cargando = true;
  bool _tieneEntradas = false;
  int? _finalPropias;
  int? _finalRival;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final c in [..._propias, ..._rival, ..._descartados]) {
      c.dispose();
    }
    _hitsPropios.dispose();
    _erroresPropios.dispose();
    _hitsRival.dispose();
    _erroresRival.dispose();
    super.dispose();
  }

  void _refrescar() {
    if (mounted) setState(() {});
  }

  TextEditingController _nuevoControlador(String texto) {
    final c = TextEditingController(text: texto);
    c.addListener(_refrescar);
    return c;
  }

  Future<void> _cargar() async {
    final db = DatabaseHelper.instance;
    final juego = await db.obtenerJuegoMarcador(widget.juegoId);
    final entradas = await db.obtenerEntradasJuego(widget.juegoId);
    final rivales = await db.obtenerEquiposRivales();
    final todosEquipos = await db.obtenerEquipos();
    if (!mounted) return;
    if (juego == null) {
      Navigator.pop(context);
      return;
    }

    final r = juego['equipo_rival_id'] as int?;
    _rivales = rivales;
    _rivalId = rivales.any((e) => e.equipoId == r) ? r : null;
    _fecha = juego['fecha'] as String;
    for (final e in todosEquipos) {
      if (e.tipo == 'propio') {
        _nombrePropio = e.nombre;
        break;
      }
    }
    _finalPropias = juego['carreras_propias'] as int?;
    _finalRival = juego['carreras_rival'] as int?;
    _tieneEntradas = entradas.isNotEmpty;

    for (final e in entradas) {
      _propias.add(_nuevoControlador('${e['carreras_propias']}'));
      _rival.add(_nuevoControlador('${e['carreras_rival']}'));
    }
    if (entradas.isEmpty) {
      for (var i = 0; i < 9; i++) {
        _propias.add(_nuevoControlador(''));
        _rival.add(_nuevoControlador(''));
      }
    }

    _hitsPropios.text = juego['hits_propios']?.toString() ?? '';
    _erroresPropios.text = juego['errores_propios']?.toString() ?? '';
    _hitsRival.text = juego['hits_rival']?.toString() ?? '';
    _erroresRival.text = juego['errores_rival']?.toString() ?? '';

    setState(() => _cargando = false);
  }

  String _fechaVista(String iso) {
    final p = iso.split('-');
    if (p.length != 3) return iso;
    return '${p[2]}/${p[1]}/${p[0]}';
  }

  String _nombreRival() {
    for (final e in _rivales) {
      if (e.equipoId == _rivalId) return e.nombre;
    }
    return 'Rival';
  }

  int _suma(List<TextEditingController> l) =>
      l.fold<int>(0, (a, c) => a + (int.tryParse(c.text.trim()) ?? 0));

  void _agregarEntrada() {
    setState(() {
      _propias.add(_nuevoControlador(''));
      _rival.add(_nuevoControlador(''));
    });
  }

  void _quitarEntrada() {
    if (_propias.length <= 1) return;
    setState(() {
      _descartados.add(_propias.removeLast());
      _descartados.add(_rival.removeLast());
    });
  }

  Future<void> _guardar() async {
    final propias = <int>[];
    final rival = <int>[];
    for (var i = 0; i < _propias.length; i++) {
      propias.add(int.tryParse(_propias[i].text.trim()) ?? 0);
      rival.add(int.tryParse(_rival[i].text.trim()) ?? 0);
    }
    int? opc(TextEditingController c) {
      final t = c.text.trim();
      return t.isEmpty ? null : int.tryParse(t);
    }

    await DatabaseHelper.instance.guardarMarcadorJuego(
      widget.juegoId,
      rivalId: _rivalId,
      propias: propias,
      rival: rival,
      hitsPropios: opc(_hitsPropios),
      erroresPropios: opc(_erroresPropios),
      hitsRival: opc(_hitsRival),
      erroresRival: opc(_erroresRival),
    );
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _quitarDesglose() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar desglose'),
        content: const Text(
          'Se borran las entradas, pero el juego conserva su marcador final actual.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('QUITAR'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DatabaseHelper.instance.quitarEntradasJuego(widget.juegoId);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Widget _celdaTexto(TextEditingController c) {
    return SizedBox(
      width: 44,
      height: 40,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(vertical: 8),
          ),
        ),
      ),
    );
  }

  Widget _celdaTitulo(String t) {
    return SizedBox(
      width: 44,
      child: Center(
        child: Text(
          t,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54),
        ),
      ),
    );
  }

  Widget _filaTitulos() {
    return Row(
      children: [
        const SizedBox(width: 96),
        for (var i = 0; i < _propias.length; i++) _celdaTitulo('${i + 1}'),
        _celdaTitulo('R'),
        _celdaTitulo('H'),
        _celdaTitulo('E'),
      ],
    );
  }

  Widget _filaEquipo(
    String nombre,
    List<TextEditingController> entradas,
    int total,
    TextEditingController hits,
    TextEditingController errores,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            nombre,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        for (final c in entradas) _celdaTexto(c),
        SizedBox(
          width: 44,
          child: Center(
            child: Text(
              '$total',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: _acento,
              ),
            ),
          ),
        ),
        _celdaTexto(hits),
        _celdaTexto(errores),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      appBar: AppBar(
        backgroundColor: _fondoOscuro,
        foregroundColor: Colors.white,
        title: const Text('MARCADOR'),
        actions: [
          if (_tieneEntradas)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'quitar') _quitarDesglose();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'quitar',
                  child: Text('Quitar desglose por entradas'),
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Guardar',
            onPressed: _cargando ? null : _guardar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Juego del ${_fechaVista(_fecha)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        DropdownButton<int?>(
                          isExpanded: true,
                          value: _rivalId,
                          items: [
                            const DropdownMenuItem<int?>(value: null, child: Text('Sin rival')),
                            for (final e in _rivales)
                              DropdownMenuItem<int?>(value: e.equipoId, child: Text(e.nombre)),
                          ],
                          onChanged: (v) => setState(() => _rivalId = v),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _filaTitulos(),
                          const SizedBox(height: 4),
                          _filaEquipo(_nombrePropio, _propias, _suma(_propias), _hitsPropios, _erroresPropios),
                          const SizedBox(height: 4),
                          _filaEquipo(_nombreRival(), _rival, _suma(_rival), _hitsRival, _erroresRival),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _agregarEntrada,
                      icon: const Icon(Icons.add),
                      label: const Text('Entrada'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _propias.length > 1 ? _quitarEntrada : null,
                      icon: const Icon(Icons.remove),
                      label: const Text('Entrada'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!_tieneEntradas && _finalPropias != null && _finalRival != null)
                  Text(
                    'Marcador final actual: $_finalPropias - $_finalRival. '
                    'Al guardar se reemplaza por la suma de las entradas.',
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                const SizedBox(height: 4),
                const Text(
                  'Las celdas vacias cuentan como 0. Hits (H) y errores (E) son opcionales.',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
    );
  }
}