import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../widgets/barra_inferior_app.dart';
import 'registrar_salida_screen.dart'
    show outsDesdeInnings, RegistrarSalidaScreen;

// Colores tomados de la maqueta "Historial de salidas" (mismos del perfil).
const Color _fondo = Color(0xFFF4F6FA);
const Color _tinta = Color(0xFF0F172A);
const Color _azul = Color(0xFF1D4ED8);
const Color _azulOscuro = Color(0xFF1E3A8A);
const Color _azulSuave = Color(0xFF3B5BB5);
const Color _azulCaja = Color(0xFFE3ECFF);
const Color _naranja = Color(0xFFFF7A1A);
const Color _grisTexto = Color(0xFF64748B);
const Color _grisBoton = Color(0xFF334155);
const Color _grisBarra = Color(0xFF94A3B8);
const Color _bordeClaro = Color(0xFFE2E8F0);
const Color _bordeChip = Color(0xFFCBD5E1);
const Color _verde = Color(0xFF16A34A);
const Color _rojo = Color(0xFFDC2626);

TextStyle _estilo(double tamano, Color color,
    {FontWeight peso = FontWeight.w400}) {
  return TextStyle(fontSize: tamano, color: color, fontWeight: peso);
}

enum _Resultado { ganado, perdido, otro }

class HistorialSalidasScreen extends StatefulWidget {
  final int lanzadorId;
  final String nombreLanzador;

  const HistorialSalidasScreen({
    super.key,
    required this.lanzadorId,
    required this.nombreLanzador,
  });

  @override
  State<HistorialSalidasScreen> createState() => _HistorialSalidasScreenState();
}

class _HistorialSalidasScreenState extends State<HistorialSalidasScreen> {
  static const List<String> _meses = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];
  static const List<String> _filtros = [
    'Todas',
    'Victorias',
    'Derrotas',
    'Sin resultado',
  ];

  List<Map<String, dynamic>> _salidas = [];
  bool _cargando = true;
  int _filtro = 0; // 0 todas, 1 victorias, 2 derrotas, 3 sin resultado

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final lista =
        await DatabaseHelper.instance.historialSalidasLanzador(widget.lanzadorId);
    if (!mounted) return;
    setState(() {
      _salidas = lista;
      _cargando = false;
    });
  }

  // ---------------------------------------------------------------------
  // Utilidades
  // ---------------------------------------------------------------------

  int _n(Map<String, dynamic> m, String k) => (m[k] as num?)?.toInt() ?? 0;

  int _outs(Map<String, dynamic> m) =>
      (((m['innings_lanzados_juego'] as num?) ?? 0) * 3).round();

  String _ip(int outs) => '${outs ~/ 3}.${outs % 3}';

  /// dd/mm/aaaa (para los dialogos).
  String _fechaVista(String iso) {
    final p = iso.split('-');
    if (p.length != 3) return iso;
    return '${p[2]}/${p[1]}/${p[0]}';
  }

  /// "12 nov" (con el anio si no es el actual).
  String _fechaCorta(String iso) {
    final p = iso.split('-');
    if (p.length != 3) return iso;
    final anio = int.tryParse(p[0]);
    final mes = int.tryParse(p[1]);
    final dia = int.tryParse(p[2]);
    if (anio == null || mes == null || dia == null || mes < 1 || mes > 12) {
      return iso;
    }
    final base = '$dia ${_meses[mes - 1]}';
    return anio == DateTime.now().year ? base : '$base $anio';
  }

  _Resultado _resultado(Map<String, dynamic> s) {
    final cp = (s['carreras_propias'] as num?)?.toInt();
    final cr = (s['carreras_rival'] as num?)?.toInt();
    if (cp == null || cr == null) return _Resultado.otro;
    if (cp > cr) return _Resultado.ganado;
    if (cp < cr) return _Resultado.perdido;
    return _Resultado.otro;
  }

  List<Map<String, dynamic>> get _filtradas {
    switch (_filtro) {
      case 1:
        return _salidas
            .where((s) => _resultado(s) == _Resultado.ganado)
            .toList();
      case 2:
        return _salidas
            .where((s) => _resultado(s) == _Resultado.perdido)
            .toList();
      case 3:
        return _salidas.where((s) => _resultado(s) == _Resultado.otro).toList();
      default:
        return _salidas;
    }
  }

  // ---------------------------------------------------------------------
  // Acciones
  // ---------------------------------------------------------------------

  Future<void> _nueva() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RegistrarSalidaScreen(
          lanzadorId: widget.lanzadorId,
          nombreLanzador: widget.nombreLanzador,
        ),
      ),
    );
    if (ok == true) await _cargar();
  }

  Future<void> _borrar(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar salida'),
        content: Text(
            'Se borrara la salida del ${_fechaVista(s['fecha'] as String)}. Esta accion no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCELAR')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('BORRAR')),
        ],
      ),
    );
    if (ok != true) return;
    await DatabaseHelper.instance.eliminarSalidaLanzador(s['id'] as int);
    await _cargar();
  }

  Future<void> _editar(Map<String, dynamic> s) async {
    final v = await showDialog<Map<String, int>>(
      context: context,
      builder: (ctx) => _EditarSalidaDialog(
        titulo: 'Salida del ${_fechaVista(s['fecha'] as String)}',
        inningsInicial: _ip(_outs(s)),
        inicial: {
          'picheos': _n(s, 'picheos_lanzados'),
          'carreras': _n(s, 'carreras_permitidas'),
          'limpias': _n(s, 'carreras_limpias'),
          'hits': _n(s, 'hits_permitidos'),
          'ponches': _n(s, 'ponches'),
          'bb': _n(s, 'bases_por_bolas'),
        },
      ),
    );
    if (v == null) return;
    await DatabaseHelper.instance.actualizarSalidaLanzador(
      s['id'] as int,
      outs: v['outs']!,
      picheos: v['picheos']!,
      carrerasPermitidas: v['carreras']!,
      carrerasLimpias: v['limpias']!,
      hitsPermitidos: v['hits']!,
      ponches: v['ponches']!,
      basesPorBolas: v['bb']!,
    );
    await _cargar();
  }

  void _acciones(Map<String, dynamic> s) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: _tinta),
              title: const Text('Editar salida'),
              onTap: () {
                Navigator.pop(ctx);
                _editar(s);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: _rojo),
              title: const Text('Borrar salida'),
              onTap: () {
                Navigator.pop(ctx);
                _borrar(s);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Piezas de interfaz
  // ---------------------------------------------------------------------

  Widget _encabezado() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Volver',
            icon: const Icon(Icons.arrow_back, size: 22, color: _tinta),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Historial de salidas',
                    style: _estilo(18, _tinta, peso: FontWeight.w500)),
                Text(widget.nombreLanzador,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _estilo(11, _grisTexto)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: _naranja,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _nueva,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add, size: 16, color: _tinta),
                    const SizedBox(width: 2),
                    Text('Nueva',
                        style: _estilo(12, _tinta, peso: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tileResumen(String valor, String etiqueta) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: _azulCaja,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(valor, style: _estilo(18, _azulOscuro, peso: FontWeight.w500)),
          Text(etiqueta,
              textAlign: TextAlign.center,
              style: _estilo(11, _azulSuave)),
        ],
      ),
    );
  }

  Widget _resumen() {
    final n = _salidas.length;
    final totalOuts = _salidas.fold<int>(0, (a, s) => a + _outs(s));
    final ultimas = _salidas.take(5).toList();
    final outs5 = ultimas.fold<int>(0, (a, s) => a + _outs(s));
    final cl5 = ultimas.fold<int>(0, (a, s) => a + _n(s, 'carreras_limpias'));
    final era = outs5 == 0 ? '--' : (cl5 * 27 / outs5).toStringAsFixed(2);
    final porSalida = n == 0 ? '--' : (totalOuts / n / 3).toStringAsFixed(1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _tileResumen(n.toString(), 'Salidas')),
          const SizedBox(width: 8),
          Expanded(child: _tileResumen(porSalida, 'Innings por salida')),
          const SizedBox(width: 8),
          Expanded(
              child: _tileResumen(era, 'Efect. últimas ${ultimas.length}')),
        ],
      ),
    );
  }

  Widget _grafica() {
    // Las 4 mas recientes, de la mas antigua a la mas nueva.
    final barras = _salidas.take(4).toList().reversed.toList();
    var maxK = 0;
    for (final s in barras) {
      final k = _n(s, 'ponches');
      if (k > maxK) maxK = k;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _bordeClaro, width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Ponches por salida',
                  style: _estilo(12, _tinta, peso: FontWeight.w500)),
              Text('Últimas ${barras.length}',
                  style: _estilo(11, _grisTexto)),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 52,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < barras.length; i++)
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: 22,
                        height: maxK == 0
                            ? 4.0
                            : (_n(barras[i], 'ponches') / maxK * 40)
                                .clamp(4.0, 40.0)
                                .toDouble(),
                        decoration: BoxDecoration(
                          color: i == barras.length - 1 ? _azul : _grisBarra,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              for (final s in barras)
                Expanded(
                  child: Text(
                    _fechaCorta(s['fecha'] as String),
                    textAlign: TextAlign.center,
                    style: _estilo(11, _grisTexto),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String texto, bool activo, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: activo ? _azul : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: activo ? null : Border.all(color: _bordeChip, width: 0.5),
        ),
        child: Text(
          texto,
          style: _estilo(12, activo ? Colors.white : _grisBoton),
        ),
      ),
    );
  }

  Widget _filtrosFila() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          for (var i = 0; i < _filtros.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            _chip(_filtros[i], _filtro == i, () => setState(() => _filtro = i)),
          ],
        ],
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> s) {
    final r = _resultado(s);
    final cp = (s['carreras_propias'] as num?)?.toInt();
    final cr = (s['carreras_rival'] as num?)?.toInt();
    final Color acento;
    final Color fondoInsignia;
    final Color textoInsignia;
    final String insignia;
    switch (r) {
      case _Resultado.ganado:
        acento = _verde;
        fondoInsignia = const Color(0xFFDCFCE7);
        textoInsignia = const Color(0xFF166534);
        insignia = 'Victoria';
        break;
      case _Resultado.perdido:
        acento = _rojo;
        fondoInsignia = const Color(0xFFFEE2E2);
        textoInsignia = const Color(0xFF991B1B);
        insignia = 'Derrota';
        break;
      case _Resultado.otro:
        acento = _grisBarra;
        fondoInsignia = _bordeClaro;
        textoInsignia = const Color(0xFF475569);
        insignia = (cp == null || cr == null) ? 'Sin resultado' : 'Empate';
        break;
    }

    final rival = s['rival_nombre'] as String?;
    final titulo = rival == null
        ? _fechaCorta(s['fecha'] as String)
        : '${_fechaCorta(s['fecha'] as String)} · vs $rival';
    final subtitulo =
        (cp != null && cr != null) ? 'Marcador $cp-$cr' : 'Sin marcador';

    final textoStat = _estilo(12, _grisBoton);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _bordeClaro, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _acciones(s),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: acento),
                Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(titulo,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: _estilo(13, _tinta,
                                          peso: FontWeight.w500)),
                                  Text(subtitulo,
                                      style: _estilo(11, _grisTexto)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: fondoInsignia,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(insignia,
                                  style: _estilo(11, textoInsignia)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${_ip(_outs(s))} IP', style: textoStat),
                            Text('${_n(s, 'hits_permitidos')} H',
                                style: textoStat),
                            Text('${_n(s, 'carreras_limpias')} CL',
                                style: textoStat),
                            Text('${_n(s, 'bases_por_bolas')} BB',
                                style: textoStat),
                            Text('${_n(s, 'ponches')} K', style: textoStat),
                            Text('${_n(s, 'picheos_lanzados')} lanz.',
                                style: textoStat),
                          ],
                        ),
                      ],
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

  Widget _cuerpo() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_salidas.isEmpty) {
      return Center(
        child: Text('Sin salidas registradas todavía.',
            style: _estilo(13, _grisTexto)),
      );
    }

    final lista = _filtradas;
    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        _resumen(),
        _grafica(),
        _filtrosFila(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              if (lista.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('No hay salidas con ese filtro.',
                      style: _estilo(12, _grisTexto)),
                )
              else
                for (final s in lista) _tarjeta(s),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Text(
            'IP innings · H hits · CL carreras limpias · BB boletos · K ponches · lanz. picheos.\n'
            'El resultado es el del equipo en ese juego. Toca una salida para editarla o borrarla.',
            style: _estilo(11, _grisTexto),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fondo,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _encabezado(),
            Expanded(child: _cuerpo()),
          ],
        ),
      ),
      bottomNavigationBar:
          const BarraInferiorApp(activa: SeccionBarra.equipo),
    );
  }
}
class _EditarSalidaDialog extends StatefulWidget {
  final String titulo;
  final String inningsInicial;
  final Map<String, int> inicial;

  const _EditarSalidaDialog({
    required this.titulo,
    required this.inningsInicial,
    required this.inicial,
  });

  @override
  State<_EditarSalidaDialog> createState() => _EditarSalidaDialogState();
}

class _EditarSalidaDialogState extends State<_EditarSalidaDialog> {
  static const List<List<String>> _campos = [
    ['picheos', 'Picheos lanzados'],
    ['carreras', 'Carreras permitidas'],
    ['limpias', 'Carreras limpias'],
    ['hits', 'Hits permitidos'],
    ['ponches', 'Ponches (K)'],
    ['bb', 'Bases por bolas (BB)'],
  ];

  late final TextEditingController _innings =
      TextEditingController(text: widget.inningsInicial);
  late final Map<String, TextEditingController> _ctrl = {
    for (final c in _campos)
      c[0]: TextEditingController(text: (widget.inicial[c[0]] ?? 0).toString()),
  };
  String? _error;

  @override
  void dispose() {
    _innings.dispose();
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _guardar() {
    final outs = outsDesdeInnings(_innings.text);
    if (outs == null) {
      setState(() => _error = 'Innings invalidos. Usa 6, 6.1 o 6.2.');
      return;
    }
    final v = <String, int>{'outs': outs};
    for (final c in _campos) {
      final txt = _ctrl[c[0]]!.text.trim();
      final n = txt.isEmpty ? 0 : int.tryParse(txt);
      if (n == null || n < 0) {
        setState(() => _error = '"${c[1]}" debe ser un entero mayor o igual a 0.');
        return;
      }
      v[c[0]] = n;
    }
    if (v['limpias']! > v['carreras']!) {
      setState(() => _error = 'Las carreras limpias no pueden superar las permitidas.');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: _innings,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Innings (ej. 6.1)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              for (final c in _campos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: _ctrl[c[0]],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: c[1],
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
        TextButton(onPressed: _guardar, child: const Text('GUARDAR')),
      ],
    );
  }
}
