import 'package:flutter/material.dart';

import '../services/cambios_db.dart';
import '../services/corredores_db.dart';
import '../services/database_helper.dart';
import '../services/jugadas_corredor_db.dart';
import '../services/juego_vivo_db.dart';
import '../services/lanzador_rival_db.dart';
import '../services/marcador_db.dart';
import '../services/turno_db.dart';
import '../services/turno_vista_db.dart';
import 'cambios_screen.dart';

const Color _fondo = Color(0xFF14171C);
const Color _superficie = Color(0xFF1E232B);
const Color _borde = Color(0xFF2E3541);
const Color _cian = Color(0xFF0ABDCF);
const Color _rojo = Color(0xFFE63946);
const Color _naranja = Color(0xFFF08A24);
const Color _textoSuave = Color(0xFF9AA4B2);
const Map<String, String> _hitsDirectos = {
  'hit': 'sencillo',
  'h2': 'doble',
  'h3': 'triple',
  'hr': 'home_run',
};

const Map<String, String> _etiquetas = {
  'sencillo': 'Sencillo',
  'doble': 'Doble',
  'triple': 'Triple',
  'home_run': 'Jonron',
  'out_roletazo': 'Out por roletazo',
  'out_elevado': 'Out por elevado',
  'out_linea': 'Out por linea',
  'error': 'Error',
  'boleto': 'Boleto',
  'ponche': 'Ponche',
  'golpeado': 'Golpeado',
};

const Map<String, String> _cortoRes = {
  'bola': 'Bola',
  'strike_cantado': 'Strike',
  'strike_swing': 'Strike',
  'foul': 'Foul',
  'en_juego': 'En juego',
  'golpeado': 'Golpeado',
};

const Map<String, String> _etiquetasJugada = {
  'robo': 'Robo de base',
  'robo_frustrado': 'Robo frustrado',
  'wild_pitch': 'Wild pitch',
  'passed_ball': 'Passed ball',
  'balk': 'Balk',
};

class TurnoScreen extends StatefulWidget {
  final int juegoId;

  const TurnoScreen({super.key, required this.juegoId});

  @override
  State<TurnoScreen> createState() => _TurnoScreenState();
}

class _TurnoScreenState extends State<TurnoScreen> {
  Map<String, dynamic>? _juego;
  Map<String, dynamic>? _turno;
  Map<String, dynamic>? _siguiente;
  Map<String, dynamic>? _lanzadorRival;
  Map<String, dynamic>? _pendiente;
  Map<String, dynamic>? _corr;
  Map<String, dynamic>? _ultimaJugada;
  Map<String, dynamic> _vista = {};
  List<Map<String, dynamic>> _entradas = [];
  List<Map<String, dynamic>> _lanzamientos = [];
  List<Map<String, dynamic>> _tipos = [];
  int? _tipoId;
  bool _tipoCargado = false;
  bool _filtrado = false;
  bool _cargando = true;
  bool _ocupado = false;
  bool _dialogoCorredores = false;
  bool _ignorarPendiente = false;
  bool _dpPendiente = false;
  String? _sel;
  String _subStrike = 'strike_cantado';
  String _subOut = 'out_roletazo';
  Offset? _zona;

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
    final turno = await db.obtenerTurnoAbierto(widget.juegoId);
    final lanzadorRival = await db.obtenerLanzadorRivalActual(widget.juegoId);
    final pendiente = await db.obtenerPendienteCorredores(widget.juegoId);
    final corr = await db.obtenerCorredoresActuales(widget.juegoId);
    final ultimaJugada = await db.obtenerUltimaJugadaDeshacible(widget.juegoId);
    final entradas = await db.obtenerEntradasJuego(widget.juegoId);

    Map<String, dynamic>? siguiente;
    var lanzamientos = <Map<String, dynamic>>[];
    if (turno == null) {
      try {
        siguiente = await db.siguienteBateadorTurno(widget.juegoId);
      } catch (e) {
        _aviso(_mensaje(e));
      }
    } else {
      lanzamientos = await db.obtenerLanzamientosTurnoZona(turno['id'] as int);
    }

    if (turno != null) {
      final lanzadorId = turno['lanzador_id'] as int?;
      _tipos = await db.obtenerTiposPitcheoLanzador(lanzadorId);
      _filtrado = lanzadorId != null;
      if (_tipos.isEmpty && turno['propio'] == 1) {
        _tipos = await db.obtenerTiposPitcheo();
        _filtrado = false;
      }
    } else if (_tipos.isEmpty) {
      _tipos = await db.obtenerTiposPitcheo();
    }
    if (!_tipoCargado) {
      _tipoId = await db.ultimoTipoPitcheo(widget.juegoId);
      _tipoCargado = true;
    }
    if (_tipoId != null &&
        !_tipos.any((t) => t['tipo_lanzamiento_id'] == _tipoId)) {
      _tipoId = null;
    }

    int? lanzadorId;
    int? bateadorId;
    if (turno != null) {
      lanzadorId = turno['lanzador_id'] as int?;
      bateadorId = turno['bateador_id'] as int?;
    } else if (siguiente != null) {
      bateadorId = siguiente['jugador_id'] as int?;
      if (siguiente['propio'] == true) {
        lanzadorId = lanzadorRival?['jugador_id'] as int?;
      } else {
        final lp = await db.obtenerLanzadorPropioActual(widget.juegoId);
        lanzadorId = lp?['jugador_id'] as int?;
      }
    }
    final vista = await db.obtenerVistaTurno(
      widget.juegoId,
      bateadorId: bateadorId,
      lanzadorId: lanzadorId,
    );

    if (!mounted) return;
    setState(() {
      _juego = juego;
      _turno = turno;
      _siguiente = siguiente;
      _lanzadorRival = lanzadorRival;
      _pendiente = pendiente;
      _corr = corr;
      _ultimaJugada = ultimaJugada;
      _entradas = entradas;
      _lanzamientos = lanzamientos;
      _vista = vista;
      if (turno == null) {
        _sel = null;
        _zona = null;
      }
      _cargando = false;
    });

    if (turno == null &&
        pendiente != null &&
        !_dialogoCorredores &&
        !_ignorarPendiente) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resolverPendiente();
      });
    }
  }

  Future<bool> _ejecutar(Future<void> Function() accion) async {
    if (_ocupado) return false;
    setState(() => _ocupado = true);
    var ok = true;
    try {
      await accion();
    } catch (e) {
      ok = false;
      _aviso(_mensaje(e));
    }
    await _cargar();
    if (mounted) setState(() => _ocupado = false);
    return ok;
  }

  // ------------------------------------------------------------------
  // Acciones
  // ------------------------------------------------------------------
  Future<void> _enviar() async {
    final s = _sel;
    final turno = _turno;
    if (s == null || turno == null) return;
    var res = 'bola';
    String? cierre;
    if (s == 'strike') {
      res = _subStrike;
    } else if (s == 'foul') {
      res = 'foul';
    } else if (s == 'out') {
      res = 'en_juego';
      cierre = _subOut;
    } else if (s == 'dp') {
      res = 'en_juego';
      cierre = 'out_roletazo';
    } else if (s == 'error') {
      res = 'en_juego';
      cierre = 'error';
    } else if (_hitsDirectos.containsKey(s)) {
      res = 'en_juego';
      cierre = _hitsDirectos[s];
    }
    _dpPendiente = s == 'dp';
    final z = _zona;
    final ok = await _ejecutar(() async {
      final c = await DatabaseHelper.instance.registrarLanzamientoTurno(
        widget.juegoId,
        turno['id'] as int,
        res,
        resultadoTurno: cierre,
        tipoId: _tipoId,
        zonaX: z?.dx,
        zonaY: z?.dy,
      );
      if (c != null) _aviso(_etiquetas[c] ?? c);
    });
    if (!ok) _dpPendiente = false;
    if (ok && mounted) {
      setState(() {
        _sel = null;
        _zona = null;
      });
    }
  }

  Future<void> _iniciarTurno() async {
    final s = _siguiente!;
    if (s['propio'] == true && _lanzadorRival == null) {
      final ok = await _elegirLanzadorRival();
      if (!ok) return;
    }
    await _ejecutar(() async {
      await DatabaseHelper.instance.iniciarTurno(
        widget.juegoId,
        bateadorId: s['jugador_id'] as int,
        orden: s['orden'] as int,
      );
    });
  }

  Future<void> _agregarRival() async {
    final orden = _siguiente!['orden'] as int;
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoRival(orden: orden),
    );
    if (r == null) return;
    await _ejecutar(() async {
      final db = DatabaseHelper.instance;
      final id = await db.agregarBateadorRival(
        widget.juegoId,
        r['nombre'] as String,
        r['numero'] as int?,
      );
      await db.iniciarTurno(widget.juegoId, bateadorId: id, orden: orden);
    });
  }

  Future<bool> _elegirLanzadorRival() async {
    final db = DatabaseHelper.instance;
    List<Map<String, dynamic>> existentes;
    List<Map<String, dynamic>> tipos;
    try {
      existentes = await db.obtenerLanzadoresRival(widget.juegoId);
      tipos = await db.obtenerTiposPitcheo();
    } catch (e) {
      _aviso(_mensaje(e));
      return false;
    }
    if (!mounted) return false;
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoLanzadorRival(existentes: existentes, tipos: tipos),
    );
    if (r == null) return false;
    try {
      if (r['id'] != null) {
        await db.fijarLanzadorRival(widget.juegoId, r['id'] as int);
      } else {
        await db.crearLanzadorRival(
          widget.juegoId,
          nombre: r['nombre'] as String,
          numero: r['numero'] as int?,
          mano: r['mano'] as String?,
          tipos: (r['tipos'] as List).cast<int>(),
        );
      }
    } catch (e) {
      _aviso(_mensaje(e));
      return false;
    }
    await _cargar();
    return true;
  }

  Future<void> _resolverPendiente() async {
    if (_dialogoCorredores || _pendiente == null) return;
    _dialogoCorredores = true;
    final p = _pendiente!;
    final r = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogoCorredores(pendiente: p, dobleJugada: _dpPendiente),
    );
    _dialogoCorredores = false;
    if (r == null) {
      _ignorarPendiente = true;
      return;
    }
    _ignorarPendiente = false;
    if (!mounted) return;
    _dpPendiente = false;
    await _ejecutar(() async {
      await DatabaseHelper.instance.resolverCorredores(
        widget.juegoId,
        p['turno_id'] as int,
        r,
      );
    });
  }

  Future<void> _jugadaCorredores() async {
    final corr =
        ((_corr?['corredores'] as List?) ?? const []).cast<Map<String, dynamic>>();
    if (corr.isEmpty) return;
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoJugada(
        corredores: corr,
        outs: (_corr?['outs'] as int?) ?? 0,
      ),
    );
    if (r == null) return;
    await _ejecutar(() async {
      await DatabaseHelper.instance.registrarJugadaCorredores(
        widget.juegoId,
        r['tipo'] as String,
        (r['movs'] as List).cast<Map<String, dynamic>>(),
      );
    });
  }

  Future<void> _deshacerJugada() async {
    await _ejecutar(() async {
      final ok = await DatabaseHelper.instance.deshacerJugadaCorredores(widget.juegoId);
      if (!ok) {
        _aviso('No hay ninguna jugada que deshacer.');
      }
    });
  }

  Future<void> _deshacer() async {
    final ok = await _ejecutar(() async {
      final r = await DatabaseHelper.instance.deshacerLanzamientoTurno(widget.juegoId);
      if (!r) {
        _aviso('No hay ningun lanzamiento que deshacer.');
      }
    });
    if (ok && mounted) {
      setState(() {
        _sel = null;
        _zona = null;
      });
    }
  }

  Future<void> _abrirCambios() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CambiosScreen(juegoId: widget.juegoId)),
    );
    if (!mounted) return;
    await _cargar();
  }

  Future<void> _terminar() async {
    if (_turno != null || _pendiente != null) {
      _aviso('Cierra el turno en curso y anota los corredores antes de terminar.');
      return;
    }
    final p = _total('carreras_propias');
    final r = _total('carreras_rival');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Terminar juego'),
        content: Text('Se guarda el marcador final ($p - $r) y el juego cuenta para el record.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('TERMINAR'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await DatabaseHelper.instance.terminarJuegoVivo(widget.juegoId);
    } catch (e) {
      _aviso(_mensaje(e));
      return;
    }
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  // ------------------------------------------------------------------
  // Datos derivados
  // ------------------------------------------------------------------
  int get _entrada => (_juego!['entrada_actual'] as int?) ?? 1;
  String get _mitad => (_juego!['mitad_actual'] as String?) ?? 'alta';
  int get _outs => (_juego!['outs_actuales'] as int?) ?? 0;

  int _total(String col) =>
      _entradas.fold<int>(0, (a, e) => a + ((e[col] as int?) ?? 0));

  bool get _hayCorredores =>
      ((_corr?['corredores'] as List?) ?? const []).isNotEmpty;

  String? _manoCorta(String? m) {
    if (m == 'derecha') return 'Diestro';
    if (m == 'izquierda') return 'Zurdo';
    if (m == 'ambos') return 'Ambos';
    return null;
  }

  String _avg(int h, int ab) {
    if (ab == 0) return '-';
    final s = (h / ab).toStringAsFixed(3);
    return s.startsWith('0') ? s.substring(1) : s;
  }

  Color _colorRes(String r) {
    if (r == 'bola') return const Color(0xFF8C96A5);
    if (r == 'en_juego' || r == 'golpeado') return _cian;
    return _naranja;
  }

  // ------------------------------------------------------------------
  // Piezas de la pantalla
  // ------------------------------------------------------------------
  Widget _menu() {
    return PopupMenuButton<String>(
      color: _superficie,
      onSelected: (v) {
        if (v == 'cambios') _abrirCambios();
        if (v == 'terminar') _terminar();
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'cambios',
          child: Text('Cambios (lanzador / bateador)', style: TextStyle(color: Colors.white)),
        ),
        PopupMenuItem(
          value: 'terminar',
          child: Text('Terminar juego', style: TextStyle(color: Colors.white)),
        ),
      ],
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _superficie,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _borde),
        ),
        child: const Icon(Icons.menu, size: 20),
      ),
    );
  }

  Widget _celdaLs(
    String t, {
    bool cabecera = false,
    bool actual = false,
    bool naranja = false,
  }) {
    Color color = Colors.white;
    var peso = FontWeight.w500;
    if (cabecera) {
      color = actual ? Colors.black : _textoSuave;
      if (actual) peso = FontWeight.w800;
    } else if (naranja) {
      color = _naranja;
      peso = FontWeight.w800;
    } else if (t == '\u2013') {
      color = _textoSuave;
    }
    return Container(
      height: 26,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      alignment: Alignment.center,
      decoration: (cabecera && actual)
          ? BoxDecoration(color: _cian, borderRadius: BorderRadius.circular(4))
          : null,
      child: Text(t, style: TextStyle(color: color, fontWeight: peso, fontSize: 13)),
    );
  }

  Widget _linescore() {
    final local = ((_juego!['propio_local'] as int?) ?? 0) == 1;
    final cols = _entrada > 9 ? _entrada : 9;

    String valor(bool esPropio, int i) {
      final visitante = esPropio ? !local : local;
      final jugada =
          i < _entrada || (i == _entrada && (visitante || _mitad == 'baja'));
      if (!jugada) return '\u2013';
      for (final e in _entradas) {
        if (e['numero'] == i) {
          return '${(e[esPropio ? 'carreras_propias' : 'carreras_rival'] as int?) ?? 0}';
        }
      }
      return '\u2013';
    }

    Widget extra(String t, {Color color = Colors.white, bool negrita = false}) {
      return SizedBox(
        width: 28,
        child: Center(
          child: Text(
            t,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: negrita ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      );
    }

    Widget fila(String nombre, bool esPropio) {
      final visitante = esPropio ? !local : local;
      final bateaAhora =
          (visitante && _mitad == 'alta') || (!visitante && _mitad == 'baja');
      final h = (_vista[esPropio ? 'h_propio' : 'h_rival'] as int?) ?? 0;
      final e = (_vista[esPropio ? 'e_propio' : 'e_rival'] as int?) ?? 0;
      final r = _total(esPropio ? 'carreras_propias' : 'carreras_rival');
      return Row(
        children: [
          SizedBox(
            width: 38,
            child: Text(
              nombre,
              style: TextStyle(
                color: esPropio ? _cian : Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          for (var i = 1; i <= cols; i++)
            Expanded(
              child: _celdaLs(
                valor(esPropio, i),
                naranja: bateaAhora && i == _entrada,
              ),
            ),
          extra('$r', negrita: true),
          extra('$h'),
          extra('$e'),
        ],
      );
    }

    final filas = local
        ? [fila('RIV', false), fila('NOS', true)]
        : [fila('NOS', true), fila('RIV', false)];

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cian.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 38),
              for (var i = 1; i <= cols; i++)
                Expanded(child: _celdaLs('$i', cabecera: true, actual: i == _entrada)),
              extra('R', color: _cian, negrita: true),
              extra('H', color: _cian, negrita: true),
              extra('E', color: _cian, negrita: true),
            ],
          ),
          const SizedBox(height: 2),
          filas[0],
          const SizedBox(height: 2),
          filas[1],
        ],
      ),
    );
  }

  Widget _tarjetaPersona(String etiqueta, String nombre, String detalle) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            etiqueta,
            style: const TextStyle(color: _textoSuave, fontSize: 11, letterSpacing: 1.5),
          ),
          const SizedBox(height: 4),
          Text(
            nombre,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(detalle, style: const TextStyle(color: _textoSuave, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _tarjetas() {
    final turno = _turno;
    final s = _siguiente;
    final bateaPropio = turno != null ? turno['propio'] == 1 : s?['propio'] == true;

    final lz = _vista['lanzador'] as Map<String, dynamic>?;
    String lzNombre;
    String lzDetalle;
    if (lz != null) {
      final n = lz['numero'];
      lzNombre = '${n != null ? '#$n \u00B7 ' : ''}${lz['nombre']}';
      final outs = (lz['outs'] as int?) ?? 0;
      final er = (lz['er'] as int?) ?? 0;
      final ip = '${outs ~/ 3}.${outs % 3}';
      final era = outs == 0 ? '-' : (er * 27 / outs).toStringAsFixed(2);
      lzDetalle = '${lz['pitches']} lanzamientos \u00B7 $ip IP \u00B7 ERA $era';
    } else {
      lzNombre = 'Sin identificar';
      lzDetalle = bateaPropio ? 'Lanzador rival por elegir' : 'Sin lanzador';
    }

    String btNombre = '-';
    if (turno != null) {
      final n = turno['bateador_numero'];
      btNombre = '${n != null ? '#$n \u00B7 ' : ''}${turno['bateador_nombre'] ?? '?'}';
    } else if (s != null && s['nuevo'] != true) {
      final n = s['numero'];
      btNombre = '${n != null ? '#$n \u00B7 ' : ''}${s['nombre']}';
    } else if (s != null) {
      btNombre = 'Bateador ${s['orden']}';
    }
    final b = _vista['bateador'] as Map<String, dynamic>?;
    var btDetalle = '';
    if (b == null) {
      btDetalle = s?['nuevo'] == true ? 'Por agregar' : '';
    } else {
      final partes = <String>[];
      final mano = _manoCorta(b['mano'] as String?);
      if (mano != null) partes.add(mano);
      partes.add('AVG ${_avg((b['h'] as int?) ?? 0, (b['ab'] as int?) ?? 0)}');
      partes.add('${b['hoy_h']}-${b['hoy_ab']} hoy');
      btDetalle = partes.join(' \u00B7 ');
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _tarjetaPersona('LANZADOR', lzNombre, lzDetalle)),
          const SizedBox(width: 10),
          Expanded(
            child: _tarjetaPersona(
              'BATEADOR (${bateaPropio ? 'NOS' : 'RIV'})',
              btNombre,
              btDetalle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _etiq(String t) {
    return Text(
      t,
      style: const TextStyle(
        color: _textoSuave,
        fontSize: 11,
        letterSpacing: 1.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _numeroGrande(int n, Color color) {
    return Text(
      '$n',
      style: TextStyle(
        color: color,
        fontSize: 36,
        fontWeight: FontWeight.w800,
        height: 1.1,
      ),
    );
  }

  Widget _zonaWidget() {
    final activo = _turno != null;
    final hayMarcas =
        _lanzamientos.any((l) => l['zona_x'] != null && l['zona_y'] != null);
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, c) {
          final s = c.maxWidth;
          Widget marcador(
            double x,
            double y,
            Color color, {
            String? texto,
            bool hueco = false,
          }) {
            return Positioned(
              left: x * s - 11,
              top: y * s - 11,
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hueco ? Colors.transparent : color,
                  border: hueco ? Border.all(color: color, width: 2) : null,
                ),
                child: texto == null
                    ? null
                    : Text(
                        texto,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            );
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: activo
                ? (d) => setState(() {
                      _zona = Offset(
                        (d.localPosition.dx / s).clamp(0.0, 1.0).toDouble(),
                        (d.localPosition.dy / s).clamp(0.0, 1.0).toDouble(),
                      );
                    })
                : null,
            onLongPress: activo ? () => setState(() => _zona = null) : null,
            child: CustomPaint(
              size: Size(s, s),
              painter: _ZonaPainter(),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (!activo || (!hayMarcas && _zona == null))
                    Center(
                      child: Text(
                        activo ? 'Toca para marcar\nla zona (opcional)' : 'Sin turno\nen curso',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: _textoSuave, fontSize: 11),
                      ),
                    ),
                  for (final l in _lanzamientos)
                    if (l['zona_x'] != null && l['zona_y'] != null)
                      marcador(
                        (l['zona_x'] as num).toDouble(),
                        (l['zona_y'] as num).toDouble(),
                        _colorRes(l['resultado'] as String),
                        texto: '${l['numero']}',
                      ),
                  if (_zona != null)
                    marcador(_zona!.dx, _zona!.dy, Colors.white, hueco: true),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _diamante() {
    final ocupadas = <int>{
      for (final c in ((_corr?['corredores'] as List?) ?? const []))
        (c as Map)['base'] as int,
    };

    Widget base(double l, double t, bool o) {
      return Positioned(
        left: l,
        top: t,
        child: Transform.rotate(
          angle: 0.785398,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: o ? _cian : Colors.transparent,
              border: Border.all(color: o ? _cian : _textoSuave, width: 2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      );
    }

    String etiquetaBases;
    if (ocupadas.isEmpty) {
      etiquetaBases = 'Bases vacias';
    } else if (ocupadas.length == 3) {
      etiquetaBases = 'Bases llenas';
    } else {
      etiquetaBases = (ocupadas.toList()..sort()).map((b) => '$b\u00AA').join(' y ');
    }

    final mano = (_vista['bateador'] as Map<String, dynamic>?)?['mano'] as String?;
    String? bate;
    if (mano == 'derecha') bate = 'Bate diestro';
    if (mano == 'izquierda') bate = 'Bate zurdo';
    if (mano == 'ambos') bate = 'Bate ambos';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 76,
          height: 76,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              base(29, 0, ocupadas.contains(2)),
              base(0, 29, ocupadas.contains(3)),
              base(58, 29, ocupadas.contains(1)),
              base(29, 58, false),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          etiquetaBases,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _textoSuave, fontSize: 11),
        ),
        if (bate != null)
          Text(bate, style: const TextStyle(color: _textoSuave, fontSize: 11)),
      ],
    );
  }

  Widget _filaCentral() {
    final t = _turno;
    final bolas = t != null ? ((t['bolas'] as int?) ?? 0) : 0;
    final strikes = t != null ? ((t['strikes'] as int?) ?? 0) : 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 62,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _etiq('BOLAS'),
              _numeroGrande(bolas, Colors.white),
              const SizedBox(height: 10),
              _etiq('STRIKES'),
              _numeroGrande(strikes, _naranja),
              const SizedBox(height: 10),
              _etiq('OUTS'),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _outs ? _cian : Colors.transparent,
                        border: Border.all(color: _cian, width: 1.5),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: _zonaWidget(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 78, child: _diamante()),
      ],
    );
  }

  Widget _selectorTipo() {
    if (_tipos.isEmpty) {
      final nombre = (_vista['lanzador'] as Map<String, dynamic>?)?['nombre'];
      return Text(
        _filtrado && nombre != null
            ? '$nombre no tiene tipos de pitcheo registrados. Agregaselos en su perfil. Los lanzamientos se guardan sin tipo.'
            : 'No hay tipos de pitcheo registrados. Los lanzamientos se guardan sin tipo.',
        style: const TextStyle(color: _textoSuave, fontSize: 12),
      );
    }
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _tipos.length,
        separatorBuilder: (context, i) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final t = _tipos[i];
          final id = t['tipo_lanzamiento_id'] as int;
          final sel = _tipoId == id;
          return InkWell(
            borderRadius: BorderRadius.circular(21),
            onTap: () => setState(() => _tipoId = sel ? null : id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel ? _cian : _superficie,
                borderRadius: BorderRadius.circular(21),
                border: Border.all(color: sel ? _cian : _borde),
              ),
              child: Text(
                t['nombre'] as String,
                style: TextStyle(
                  color: sel ? Colors.black : Colors.white,
                  fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                  fontSize: 15,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _filaTurno() {
    return Row(
      children: [
        _etiq('TURNO'),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 32,
            child: _lanzamientos.isEmpty
                ? const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Sin lanzamientos todavia',
                      style: TextStyle(color: _textoSuave, fontSize: 12),
                    ),
                  )
                : ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final l in _lanzamientos)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _borde),
                          ),
                          child: Text(
                            '${l['numero']} ${(l['tipo'] as String?) ?? 'Sin tipo'} \u00B7 ${_cortoRes[l['resultado']] ?? l['resultado']}',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _botonRes(
    String id,
    String texto, {
    Color? acento,
    bool habilitado = true,
  }) {
    final sel = _sel == id;
    final c = acento ?? _cian;
    final forma = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: sel ? c : (acento != null ? c.withValues(alpha: 0.8) : _borde),
        width: sel ? 2 : 1.2,
      ),
    );
    return Opacity(
      opacity: habilitado ? 1 : 0.4,
      child: SizedBox(
        height: 52,
        child: Material(
          color: sel ? c.withValues(alpha: 0.18) : _superficie,
          shape: forma,
          child: InkWell(
            customBorder: forma,
            onTap: (habilitado && !_ocupado)
                ? () => setState(() => _sel = sel ? null : id)
                : null,
            child: Center(
              child: Text(
                texto,
                style: TextStyle(
                  color: (sel || acento != null) ? c : Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fila4(List<Widget> hijos) {
    return Row(
      children: [
        for (var i = 0; i < hijos.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: hijos[i]),
        ],
      ],
    );
  }

  Widget _subOpciones() {
    List<MapEntry<String, String>> ops;
    String actual;
    if (_sel == 'strike') {
      ops = const [
        MapEntry('strike_cantado', 'Cantado'),
        MapEntry('strike_swing', 'Swing'),
      ];
      actual = _subStrike;
    } else if (_sel == 'out') {
      ops = const [
        MapEntry('out_roletazo', 'Roletazo'),
        MapEntry('out_elevado', 'Elevado'),
        MapEntry('out_linea', 'Linea'),
      ];
      actual = _subOut;
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        children: [
          for (final o in ops)
            ChoiceChip(
              label: Text(o.value),
              selected: actual == o.key,
              selectedColor: _cian,
              backgroundColor: _superficie,
              labelStyle: TextStyle(color: actual == o.key ? Colors.black : Colors.white),
              onSelected: (_) => setState(() {
                if (_sel == 'out') {
                  _subOut = o.key;
                } else {
                  _subStrike = o.key;
                }
              }),
            ),
        ],
      ),
    );
  }

  Widget _botonSec(String texto, VoidCallback? onTap, {IconData? icono}) {
    final activo = onTap != null;
    final forma = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: _borde),
    );
    return SizedBox(
      height: 52,
      child: Material(
        color: _superficie,
        shape: forma,
        child: InkWell(
          customBorder: forma,
          onTap: onTap,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icono != null) ...[
                  Icon(icono, size: 16, color: activo ? _textoSuave : _borde),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    texto,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: activo ? Colors.white : _textoSuave,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filaAcciones() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _botonSec(
            'Jugada de corredores',
            (_hayCorredores && !_ocupado) ? _jugadaCorredores : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: _botonSec(
            'Deshacer',
            _ocupado ? null : _deshacer,
            icono: Icons.undo,
          ),
        ),
      ],
    );
  }

  List<Widget> _extrasJugada() {
    if (_ultimaJugada == null) return const [];
    return [
      TextButton.icon(
        onPressed: _ocupado ? null : _deshacerJugada,
        icon: const Icon(Icons.undo, size: 16),
        label: Text(
          'DESHACER JUGADA (${_etiquetasJugada[_ultimaJugada!['tipo']] ?? ''})',
        ),
      ),
    ];
  }

  Widget _botonPrincipal() {
    final puede = _sel != null && !_ocupado;
    return SizedBox(
      height: 60,
      child: ElevatedButton(
        onPressed: puede ? _enviar : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _cian,
          foregroundColor: Colors.black,
          disabledBackgroundColor: const Color(0xFF2A303A),
          disabledForegroundColor: _textoSuave,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: const Text(
          'REGISTRAR LANZAMIENTO',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5, fontSize: 16),
        ),
      ),
    );
  }

  Widget _botonGrande(String texto, VoidCallback onPressed) {
    return SizedBox(
      height: 60,
      child: ElevatedButton(
        onPressed: _ocupado ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _cian,
          foregroundColor: Colors.black,
          disabledBackgroundColor: const Color(0xFF2A303A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(
          texto,
          style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 15),
        ),
      ),
    );
  }

  List<Widget> _panelLanzamiento() {
    return [
      _selectorTipo(),
      const SizedBox(height: 12),
      _filaTurno(),
      const SizedBox(height: 14),
      _fila4([
        _botonRes('bola', 'Bola'),
        _botonRes('strike', 'Strike', acento: _naranja),
        _botonRes('foul', 'Foul'),
        _botonRes('hit', 'Hit', acento: _cian),
      ]),
      const SizedBox(height: 8),
      _fila4([
        _botonRes('h2', '2B', acento: _cian),
        _botonRes('h3', '3B', acento: _cian),
        _botonRes('hr', 'HR', acento: _cian),
        _botonRes('error', 'Error'),
      ]),
      const SizedBox(height: 8),
      _fila4([
        _botonRes('out', 'Out'),
        _botonRes('dp', 'Doble play', habilitado: _hayCorredores && _outs <= 1),
      ]),
      _subOpciones(),
      const SizedBox(height: 12),
      _filaAcciones(),
      ..._extrasJugada(),
      const SizedBox(height: 12),
      _botonPrincipal(),
    ];
  }

  List<Widget> _panelSinTurno() {
    final nuevoRival = _siguiente?['nuevo'] == true;
    return [
      if (_pendiente != null)
        _botonGrande('ANOTAR CORREDORES', () {
          _ignorarPendiente = false;
          _resolverPendiente();
        })
      else if (_siguiente != null)
        _botonGrande(
          nuevoRival ? 'AGREGAR BATEADOR RIVAL' : 'INICIAR TURNO',
          nuevoRival ? _agregarRival : _iniciarTurno,
        ),
      if (_siguiente?['propio'] == true)
        TextButton(
          onPressed: _ocupado
              ? null
              : () {
                  _elegirLanzadorRival();
                },
          child: Text(
            _lanzadorRival == null ? 'ELEGIR LANZADOR RIVAL' : 'CAMBIAR LANZADOR RIVAL',
          ),
        ),
      const SizedBox(height: 10),
      _filaAcciones(),
      ..._extrasJugada(),
    ];
  }

  Widget _cuerpo() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      children: [
        _linescore(),
        const SizedBox(height: 10),
        _tarjetas(),
        const SizedBox(height: 14),
        _filaCentral(),
        const SizedBox(height: 14),
        if (_turno != null) ..._panelLanzamiento() else ..._panelSinTurno(),
        const SizedBox(height: 14),
        const Text(
          'Los robos, wild pitches, passed balls y balks se anotan con Jugada de corredores.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _textoSuave, fontSize: 12),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cargado = !_cargando && _juego != null;
    return Scaffold(
      backgroundColor: _fondo,
      appBar: AppBar(
        backgroundColor: _fondo,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: cargado
            ? Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: _naranja,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'EN VIVO \u00B7 ${_mitad == 'alta' ? '\u25B2' : '\u25BC'} $_entrada',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      fontSize: 20,
                    ),
                  ),
                ],
              )
            : const Text('TURNO AL BATE'),
        actions: [if (cargado) _menu()],
      ),
      body: cargado
          ? _cuerpo()
          : const Center(child: CircularProgressIndicator()),
    );
  }
}

class _ZonaPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final borde = Paint()
      ..color = const Color(0x889AA4B2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)),
      );
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 5), borde);
        d += 9;
      }
    }
    final z = Rect.fromLTWH(
      size.width * 0.16,
      size.height * 0.16,
      size.width * 0.68,
      size.height * 0.68,
    );
    final grid = Paint()
      ..color = const Color(0x559AA4B2)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = z.left + z.width * i / 3;
      canvas.drawLine(Offset(x, z.top), Offset(x, z.bottom), grid);
      final y = z.top + z.height * i / 3;
      canvas.drawLine(Offset(z.left, y), Offset(z.right, y), grid);
    }
    canvas.drawRect(
      z,
      Paint()
        ..color = _cian
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DialogoRival extends StatefulWidget {
  final int orden;

  const _DialogoRival({required this.orden});

  @override
  State<_DialogoRival> createState() => _DialogoRivalState();
}

class _DialogoRivalState extends State<_DialogoRival> {
  final TextEditingController _nombre = TextEditingController();
  final TextEditingController _numero = TextEditingController();

  @override
  void dispose() {
    _nombre.dispose();
    _numero.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Bateador ${widget.orden} del rival'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nombre,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nombre (opcional)'),
          ),
          TextField(
            controller: _numero,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Numero (opcional)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),
        TextButton(
          onPressed: () {
            final n = _nombre.text.trim();
            Navigator.pop(context, {
              'nombre': n.isEmpty ? 'Bateador ${widget.orden}' : n,
              'numero': int.tryParse(_numero.text.trim()),
            });
          },
          child: const Text('AGREGAR'),
        ),
      ],
    );
  }
}

class _DialogoLanzadorRival extends StatefulWidget {
  final List<Map<String, dynamic>> existentes;
  final List<Map<String, dynamic>> tipos;

  const _DialogoLanzadorRival({required this.existentes, required this.tipos});

  @override
  State<_DialogoLanzadorRival> createState() => _DialogoLanzadorRivalState();
}

class _DialogoLanzadorRivalState extends State<_DialogoLanzadorRival> {
  final TextEditingController _nombre = TextEditingController();
  final TextEditingController _numero = TextEditingController();
  int? _sel;
  String? _mano;
  final Set<int> _tiposSel = {};

  @override
  void dispose() {
    _nombre.dispose();
    _numero.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nuevo = _sel == null;
    return AlertDialog(
      title: const Text('Lanzador del rival'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.existentes.isNotEmpty)
              DropdownButton<int?>(
                isExpanded: true,
                value: _sel,
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Nuevo lanzador'),
                  ),
                  for (final e in widget.existentes)
                    DropdownMenuItem<int?>(
                      value: e['jugador_id'] as int,
                      child: Text(
                        '${e['numero'] != null ? '#${e['numero']} ' : ''}${e['nombre']}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _sel = v),
              ),
            if (nuevo) ...[
              TextField(
                controller: _nombre,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nombre (opcional)'),
              ),
              TextField(
                controller: _numero,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Numero (opcional)'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final m in const ['derecho', 'zurdo'])
                    ChoiceChip(
                      label: Text(m == 'derecho' ? 'Derecho' : 'Zurdo'),
                      selected: _mano == m,
                      onSelected: (s) => setState(() => _mano = s ? m : null),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Tipos de pitcheo que tira'),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final t in widget.tipos)
                    FilterChip(
                      label: Text(t['nombre'] as String),
                      selected: _tiposSel.contains(t['tipo_lanzamiento_id']),
                      onSelected: (s) => setState(() {
                        final id = t['tipo_lanzamiento_id'] as int;
                        if (s) {
                          _tiposSel.add(id);
                        } else {
                          _tiposSel.remove(id);
                        }
                      }),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),
        TextButton(
          onPressed: () {
            if (!nuevo) {
              Navigator.pop(context, {'id': _sel});
              return;
            }
            final n = _nombre.text.trim();
            Navigator.pop(context, {
              'id': null,
              'nombre': n.isEmpty ? 'Lanzador rival' : n,
              'numero': int.tryParse(_numero.text.trim()),
              'mano': _mano,
              'tipos': _tiposSel.toList(),
            });
          },
          child: const Text('ACEPTAR'),
        ),
      ],
    );
  }
}

class _DialogoCorredores extends StatefulWidget {
  final Map<String, dynamic> pendiente;
  final bool dobleJugada;

  const _DialogoCorredores({required this.pendiente, this.dobleJugada = false});

  @override
  State<_DialogoCorredores> createState() => _DialogoCorredoresState();
}

class _DialogoCorredoresState extends State<_DialogoCorredores> {
  static const Set<String> _outsBateador = {
    'ponche',
    'out_roletazo',
    'out_elevado',
    'out_linea',
  };

  late final String _resultado;
  late final List<Map<String, dynamic>> _corredores;
  final Map<int, String> _destinos = {};

  @override
  void initState() {
    super.initState();
    _resultado = widget.pendiente['resultado'] as String;
    _corredores =
        (widget.pendiente['corredores'] as List).cast<Map<String, dynamic>>();
    _destinos[0] = _bateadorPorDefecto();
    final ocupadas = {for (final c in _corredores) c['base'] as int};
    final f1 = ocupadas.contains(1);
    final f2 = f1 && ocupadas.contains(2);
    final f3 = f2 && ocupadas.contains(3);
    final menor = _corredores.isEmpty
        ? 0
        : _corredores
            .map((c) => c['base'] as int)
            .reduce((a, b) => a < b ? a : b);
    for (final c in _corredores) {
      final b = c['base'] as int;
      if (widget.dobleJugada && b == menor) {
        _destinos[b] = 'out';
      } else if (widget.dobleJugada) {
        final forzado = b == 1 ? f1 : (b == 2 ? f2 : f3);
        _destinos[b] = forzado ? _avanzar(b, 1) : 'queda';
      } else {
        _destinos[b] = _corredorPorDefecto(b, f1, f2, f3);
      }
    }
  }

  String _bateadorPorDefecto() {
    switch (_resultado) {
      case 'doble':
        return '2';
      case 'triple':
        return '3';
      case 'home_run':
        return 'anota';
      case 'sencillo':
      case 'boleto':
      case 'golpeado':
      case 'error':
        return '1';
      default:
        return 'out';
    }
  }

  String _avanzar(int base, int n) {
    final d = base + n;
    return d >= 4 ? 'anota' : '$d';
  }

  String _corredorPorDefecto(int b, bool f1, bool f2, bool f3) {
    switch (_resultado) {
      case 'home_run':
        return 'anota';
      case 'sencillo':
        return _avanzar(b, 1);
      case 'doble':
        return _avanzar(b, 2);
      case 'triple':
        return _avanzar(b, 3);
      case 'boleto':
      case 'golpeado':
      case 'error':
        {
          final forzado = b == 1 ? f1 : (b == 2 ? f2 : f3);
          return forzado ? _avanzar(b, 1) : 'queda';
        }
      default:
        return 'queda';
    }
  }

  List<MapEntry<String, String>> _opciones(int origen) {
    if (origen == 0) {
      return const [
        MapEntry('1', '1B'),
        MapEntry('2', '2B'),
        MapEntry('3', '3B'),
        MapEntry('anota', 'Anota'),
      ];
    }
    return [
      const MapEntry('queda', 'Se queda'),
      for (var d = origen + 1; d <= 3; d++) MapEntry('$d', '${d}B'),
      const MapEntry('anota', 'Anota'),
      const MapEntry('out', 'Out'),
    ];
  }

  String? _conflicto() {
    final ocupadas = <int, int>{};
    for (final e in _destinos.entries) {
      int? base;
      if (e.value == 'queda') {
        base = e.key;
      } else if (e.value == '1' || e.value == '2' || e.value == '3') {
        base = int.parse(e.value);
      }
      if (base == null || base == 0) continue;
      ocupadas[base] = (ocupadas[base] ?? 0) + 1;
    }
    if (ocupadas.values.any((n) => n > 1)) {
      return 'Dos jugadores quedaron en la misma base.';
    }
    return null;
  }

  Widget _bloque(int origen, String titulo) {
    final fijo = origen == 0 && _outsBateador.contains(_resultado);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
          if (fijo)
            const Text('Out')
          else
            Wrap(
              spacing: 8,
              children: [
                for (final o in _opciones(origen))
                  ChoiceChip(
                    label: Text(o.value),
                    selected: _destinos[origen] == o.key,
                    onSelected: (_) => setState(() => _destinos[origen] = o.key),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  String _nombre(Object? numero, Object? nombre) =>
      '${numero != null ? '#$numero ' : ''}$nombre';

  @override
  Widget build(BuildContext context) {
    final conflicto = _conflicto();
    final carreras = _destinos.values.where((d) => d == 'anota').length;
    final outsExtra =
        _corredores.where((c) => _destinos[c['base'] as int] == 'out').length;
    final outs = (widget.pendiente['outs'] as int?) ?? 0;
    final termina = outsExtra > 0 && outs + outsExtra >= 3;
    return AlertDialog(
      title: Text(
        'Corredores: ${widget.dobleJugada ? 'Doble play' : (_etiquetas[_resultado] ?? _resultado)}',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _bloque(
              0,
              'Bateador: ${_nombre(widget.pendiente['bateador_numero'], widget.pendiente['bateador_nombre'])}',
            ),
            for (final c in _corredores)
              _bloque(
                c['base'] as int,
                '${c['base']}B: ${_nombre(c['numero'], c['nombre'])}',
              ),
            const SizedBox(height: 4),
            Text('Carreras en la jugada: $carreras'),
            if (termina)
              const Text('Con estos outs termina la mitad de la entrada.'),
            if (conflicto != null)
              Text(conflicto, style: const TextStyle(color: _rojo)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),
        TextButton(
          onPressed: conflicto != null
              ? null
              : () {
                  final res = <Map<String, dynamic>>[
                    for (final e in _destinos.entries)
                      {'origen': e.key, 'destino': e.value},
                  ];
                  Navigator.pop(context, res);
                },
          child: const Text('ACEPTAR'),
        ),
      ],
    );
  }
}

class _DialogoJugada extends StatefulWidget {
  final List<Map<String, dynamic>> corredores;
  final int outs;

  const _DialogoJugada({required this.corredores, required this.outs});

  @override
  State<_DialogoJugada> createState() => _DialogoJugadaState();
}

class _DialogoJugadaState extends State<_DialogoJugada> {
  String _tipo = 'robo';
  final Map<int, String> _destinos = {};

  @override
  void initState() {
    super.initState();
    _defecto();
  }

  Set<int> get _bases => {for (final c in widget.corredores) c['base'] as int};

  void _defecto() {
    _destinos.clear();
    final bases = _bases;
    for (final b in bases) {
      _destinos[b] = 'queda';
    }
    if (_tipo == 'wild_pitch' || _tipo == 'passed_ball' || _tipo == 'balk') {
      for (final b in bases) {
        _destinos[b] = b >= 3 ? 'anota' : '${b + 1}';
      }
      return;
    }
    final menor = bases.reduce((a, b) => a < b ? a : b);
    if (_tipo == 'robo_frustrado') {
      _destinos[menor] = 'out';
    } else if (menor >= 3) {
      _destinos[menor] = 'anota';
    } else if (!bases.contains(menor + 1)) {
      _destinos[menor] = '${menor + 1}';
    }
  }

  List<MapEntry<String, String>> _opciones(int origen) {
    return [
      const MapEntry('queda', 'Se queda'),
      for (var d = origen + 1; d <= 3; d++) MapEntry('$d', '${d}B'),
      const MapEntry('anota', 'Anota'),
      const MapEntry('out', 'Out'),
    ];
  }

  String? _conflicto() {
    final ocupadas = <int, int>{};
    for (final e in _destinos.entries) {
      int? base;
      if (e.value == 'queda') {
        base = e.key;
      } else if (e.value == '2' || e.value == '3') {
        base = int.parse(e.value);
      }
      if (base == null) continue;
      ocupadas[base] = (ocupadas[base] ?? 0) + 1;
    }
    if (ocupadas.values.any((n) => n > 1)) {
      return 'Dos jugadores quedaron en la misma base.';
    }
    return null;
  }

  Widget _bloque(Map<String, dynamic> c) {
    final base = c['base'] as int;
    final numero = c['numero'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${base}B: ${numero != null ? '#$numero ' : ''}${c['nombre']}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final o in _opciones(base))
                ChoiceChip(
                  label: Text(o.value),
                  selected: _destinos[base] == o.key,
                  onSelected: (_) => setState(() => _destinos[base] = o.key),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final conflicto = _conflicto();
    final hayCambio = _destinos.values.any((d) => d != 'queda');
    final carreras = _destinos.values.where((d) => d == 'anota').length;
    final outsN = _destinos.values.where((d) => d == 'out').length;
    final termina = outsN > 0 && widget.outs + outsN >= 3;
    return AlertDialog(
      title: const Text('Jugada de corredores'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final e in _etiquetasJugada.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _tipo == e.key,
                    onSelected: (_) => setState(() {
                      _tipo = e.key;
                      _defecto();
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            for (final c in widget.corredores) _bloque(c),
            Text('Carreras: $carreras  -  Outs: $outsN'),
            if (termina)
              const Text('Con estos outs termina la mitad de la entrada.'),
            if (conflicto != null)
              Text(conflicto, style: const TextStyle(color: _rojo)),
            if (conflicto == null && !hayCambio)
              const Text('Elige que paso con algun corredor.'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),
        TextButton(
          onPressed: (conflicto != null || !hayCambio)
              ? null
              : () => Navigator.pop(context, {
                    'tipo': _tipo,
                    'movs': [
                      for (final e in _destinos.entries)
                        {'origen': e.key, 'destino': e.value},
                    ],
                  }),
          child: const Text('ACEPTAR'),
        ),
      ],
    );
  }
}