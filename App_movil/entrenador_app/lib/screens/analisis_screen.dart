import 'package:flutter/material.dart';

import '../services/analisis_db.dart';
import '../services/database_helper.dart';

const Color _fondo = Color(0xFF14171C);
const Color _superficie = Color(0xFF1E232B);
const Color _cian = Color(0xFF0ABDCF);
const Color _textoSuave = Color(0xFF9AA4B2);

class AnalisisScreen extends StatefulWidget {
  const AnalisisScreen({super.key});

  @override
  State<AnalisisScreen> createState() => _AnalisisScreenState();
}

class _AnalisisScreenState extends State<AnalisisScreen> {
  List<Map<String, dynamic>> _juegos = [];
  List<Map<String, dynamic>> _bateadores = [];
  List<Map<String, dynamic>> _lanzadores = [];
  int? _juegoId;
  bool _batPropio = true;
  bool _lanPropio = true;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final db = DatabaseHelper.instance;
    final juegos = await db.obtenerJuegosAnalisis();
    if (!mounted) return;
    _juegos = juegos;
    if (juegos.isNotEmpty &&
        !juegos.any((j) => j['juego_id'] == _juegoId)) {
      _juegoId = juegos.first['juego_id'] as int;
    }
    await _cargarAnalisis();
  }

  Future<void> _cargarAnalisis() async {
    final db = DatabaseHelper.instance;
    var bat = <Map<String, dynamic>>[];
    var lan = <Map<String, dynamic>>[];
    if (_juegoId != null) {
      bat = await db.analisisBateadores(_juegoId!, propio: _batPropio);
      lan = await db.analisisLanzadores(_juegoId!, propio: _lanPropio);
    }
    if (!mounted) return;
    setState(() {
      _bateadores = bat;
      _lanzadores = lan;
      _cargando = false;
    });
  }

  String _pct(int a, int b) => b == 0 ? '-' : '${(a * 100 / b).round()}%';

  String _nombre(Map<String, dynamic> m) =>
      '${m['numero'] != null ? '#${m['numero']} ' : ''}${m['nombre']}';

  String _etiquetaJuego(Map<String, dynamic> j) {
    final rival = (j['rival'] as String?) ?? 'Sin rival';
    return '${j['fecha']}  vs $rival  (${j['carreras_propias'] ?? 0}-${j['carreras_rival'] ?? 0})';
  }

  Widget _selectorJuego() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(14),
      ),
      child: DropdownButton<int>(
        isExpanded: true,
        value: _juegoId,
        underline: const SizedBox.shrink(),
        dropdownColor: _superficie,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        items: [
          for (final j in _juegos)
            DropdownMenuItem<int>(
              value: j['juego_id'] as int,
              child: Text(_etiquetaJuego(j), overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) async {
          if (v == null) return;
          setState(() => _juegoId = v);
          await _cargarAnalisis();
        },
      ),
    );
  }

  Widget _toggle(bool propio, ValueChanged<bool> onChanged, String a, String b) {
    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          label: Text(a),
          selected: propio,
          selectedColor: _cian,
          backgroundColor: _superficie,
          labelStyle: TextStyle(color: propio ? Colors.black : Colors.white),
          onSelected: (_) => onChanged(true),
        ),
        ChoiceChip(
          label: Text(b),
          selected: !propio,
          selectedColor: _cian,
          backgroundColor: _superficie,
          labelStyle: TextStyle(color: !propio ? Colors.black : Colors.white),
          onSelected: (_) => onChanged(false),
        ),
      ],
    );
  }

  Widget _tarjeta(List<Widget> hijos) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: hijos),
    );
  }

  Widget _linea(String t, {Color color = Colors.white, double size = 13}) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text(t, style: TextStyle(color: color, fontSize: size)),
    );
  }

  Widget _titulo(String t) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        t,
        style: const TextStyle(color: _textoSuave, fontSize: 12, letterSpacing: 2),
      ),
    );
  }

  Widget _tarjetaBateador(Map<String, dynamic> b) {
    final tipos = (b['tipos'] as List).cast<Map<String, dynamic>>();
    Map<String, dynamic>? dano;
    Map<String, dynamic>? ponchador;
    for (final t in tipos) {
      if ((t['h'] as int) > 0 &&
          (dano == null || (t['h'] as int) > (dano['h'] as int))) {
        dano = t;
      }
      if ((t['k'] as int) > 0 &&
          (ponchador == null || (t['k'] as int) > (ponchador['k'] as int))) {
        ponchador = t;
      }
    }
    return _tarjeta([
      Text(
        _nombre(b),
        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
      ),
      _linea(
        'TB ${b['ab']}  -  H ${b['h']}  -  K ${b['k']}  -  BB ${b['bb']}',
        color: _cian,
        size: 14,
      ),
      _linea(
        dano == null
            ? 'Le hizo mas dano: sin hits en este juego'
            : 'Le hizo mas dano: ${dano['tipo']} (${dano['h']} H en ${dano['n']})',
      ),
      if (ponchador != null)
        _linea('Lo poncho: ${ponchador['tipo']} (${ponchador['k']} K)'),
      _titulo('POR TIPO DE PITCHEO'),
      for (final t in tipos)
        _linea('${t['tipo']}: ${t['n']} turnos, ${t['h']} H, ${t['k']} K'),
    ]);
  }

  Widget _tarjetaLanzador(Map<String, dynamic> p) {
    final n = p['n'] as int;
    final st = p['st'] as int;
    final tipos = (p['tipos'] as List).cast<Map<String, dynamic>>();
    final cuentas = (p['cuentas'] as List).cast<Map<String, dynamic>>();
    return _tarjeta([
      Text(
        _nombre(p),
        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
      ),
      _linea(
        '$n lanzamientos  -  ${_pct(st, n)} strikes  -  ${p['h']} H  -  ${p['k']} K',
        color: _cian,
        size: 14,
      ),
      _titulo('POR TIPO DE PITCHEO'),
      for (final t in tipos)
        _linea(
          '${t['tipo']}: ${t['n']} lanz., ${_pct(t['st'] as int, t['n'] as int)} strikes, ${t['h']} H, ${t['k']} K',
        ),
      _titulo('POR CUENTA (BOLAS-STRIKES)'),
      for (final c in cuentas)
        _linea(
          '${c['cuenta']}: ${c['n']} lanz., ${_pct(c['st'] as int, c['n'] as int)} strikes, ${c['bo']} bolas, ${c['h']} H, ${c['k']} K',
        ),
    ]);
  }

  Widget _vacio(String texto) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        texto,
        textAlign: TextAlign.center,
        style: const TextStyle(color: _textoSuave),
      ),
    );
  }

  Widget _pestanaBateadores() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _toggle(_batPropio, (v) async {
          setState(() => _batPropio = v);
          await _cargarAnalisis();
        }, 'Mi equipo', 'Rival'),
        const SizedBox(height: 12),
        if (_bateadores.isEmpty)
          _vacio('No hay turnos de este lado en el juego.')
        else
          for (final b in _bateadores) _tarjetaBateador(b),
        const Text(
          'Los turnos se asignan al tipo de pitcheo del ultimo lanzamiento. Si no marcaste tipo, cuentan como "Sin tipo".',
          textAlign: TextAlign.center,
          style: TextStyle(color: _textoSuave, fontSize: 12),
        ),
      ],
    );
  }

  Widget _pestanaLanzadores() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _toggle(_lanPropio, (v) async {
          setState(() => _lanPropio = v);
          await _cargarAnalisis();
        }, 'Mi lanzador', 'Lanzador rival'),
        const SizedBox(height: 12),
        if (_lanzadores.isEmpty)
          _vacio('No hay lanzamientos de este lado en el juego.')
        else
          for (final p in _lanzadores) _tarjetaLanzador(p),
        const Text(
          'Los hits y ponches se cuentan en el lanzamiento que cerro cada turno.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _textoSuave, fontSize: 12),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _fondo,
        appBar: AppBar(
          backgroundColor: _fondo,
          foregroundColor: Colors.white,
          title: const Text('ANALISIS'),
          bottom: const TabBar(
            indicatorColor: _cian,
            labelColor: _cian,
            unselectedLabelColor: _textoSuave,
            tabs: [Tab(text: 'BATEADORES'), Tab(text: 'LANZADORES')],
          ),
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _juegos.isEmpty
                ? Center(
                    child: _vacio(
                      'Todavia no hay juegos terminados con turnos registrados. Juega uno en "Juego en vivo" y terminalo.',
                    ),
                  )
                : Column(
                    children: [
                      _selectorJuego(),
                      Expanded(
                        child: TabBarView(
                          children: [_pestanaBateadores(), _pestanaLanzadores()],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}