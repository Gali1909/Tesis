import 'package:flutter/material.dart';
import '../models/lanzador_perfil.dart';
import '../models/lanzador_perfil_historico.dart';
import '../services/database_helper.dart';
import 'registrar_salida_screen.dart' show outsDesdeInnings;

// Colores tomados de la maqueta "Editar estadisticas" (mismos del perfil).
const Color _fondo = Color(0xFFF4F6FA);
const Color _tinta = Color(0xFF0F172A);
const Color _azul = Color(0xFF1D4ED8);
const Color _naranja = Color(0xFFFF7A1A);
const Color _naranjaSuave = Color(0xFFFFF1E6);
const Color _grisTexto = Color(0xFF64748B);
const Color _grisBoton = Color(0xFF334155);
const Color _bordeClaro = Color(0xFFE2E8F0);

const Color _bordeBoton = Color(0xFF94A3B8);
const Color _segmentoFondo = Color(0xFFE8EDF5);
const Color _avisoFondo = Color(0xFFFFF7E6);
const Color _avisoBorde = Color(0xFFF5C77E);
const Color _avisoIcono = Color(0xFFB45309);
const Color _avisoTexto = Color(0xFF7C4A03);

TextStyle _estilo(double tamano, Color color,
    {FontWeight peso = FontWeight.w400}) {
  return TextStyle(fontSize: tamano, color: color, fontWeight: peso);
}

const List<String> _claves = [
  'ganados',
  'perdidos',
  'aperturas',
  'salvados',
  'lanzados',
  'innings',
  'hits',
  'limpias',
  'boletos',
  'ponches',
];

const Map<String, String> _etiquetas = {
  'ganados': 'Juegos ganados',
  'perdidos': 'Juegos perdidos',
  'aperturas': 'Aperturas',
  'salvados': 'Salvados',
  'lanzados': 'Juegos lanzados',
  'innings': 'Innings lanzados',
  'hits': 'Hits',
  'limpias': 'Carreras limpias',
  'boletos': 'Boletos',
  'ponches': 'Ponches',
};

/// Innings reales (tercios) -> notacion de beisbol: 112.333 -> "112.1".
String _inningsTexto(double innings) {
  final outs = (innings * 3).round();
  return '${outs ~/ 3}.${outs % 3}';
}

/// Controladores y valores originales de una pestana (temporada o carrera).
class _Campos {
  final Map<String, TextEditingController> ctrl = {
    for (final k in _claves) k: TextEditingController(text: '0'),
  };
  final Map<String, String> orig = {for (final k in _claves) k: '0'};

  void poner(Map<String, String> valores) {
    for (final k in _claves) {
      final v = valores[k] ?? '0';
      ctrl[k]!.text = v;
      orig[k] = v;
    }
  }

  void ponerCeros() {
    for (final k in _claves) {
      ctrl[k]!.text = '0';
    }
  }

  bool cambiado(String k) => ctrl[k]!.text.trim() != orig[k];
  bool get hayCambios => _claves.any(cambiado);

  int? entero(String k) {
    final n = int.tryParse(ctrl[k]!.text.trim());
    return (n == null || n < 0) ? null : n;
  }

  int? outs() => outsDesdeInnings(ctrl['innings']!.text);

  /// Clave del primer campo invalido, o null si todo esta bien.
  String? campoInvalido() {
    for (final k in _claves) {
      if (k == 'innings') {
        if (outs() == null) return k;
      } else if (entero(k) == null) {
        return k;
      }
    }
    return null;
  }

  void dispose() {
    for (final c in ctrl.values) {
      c.dispose();
    }
  }
}

class EditarEstadisticasLanzadorScreen extends StatefulWidget {
  final int lanzadorId;
  final String nombreLanzador;
  final int? temporadaInicial;
  final bool abrirCarrera;

  const EditarEstadisticasLanzadorScreen({
    super.key,
    required this.lanzadorId,
    required this.nombreLanzador,
    this.temporadaInicial,
    this.abrirCarrera = false,
  });

  @override
  State<EditarEstadisticasLanzadorScreen> createState() =>
      _EditarEstadisticasLanzadorScreenState();
}

class _EditarEstadisticasLanzadorScreenState
    extends State<EditarEstadisticasLanzadorScreen> {
  final _t = _Campos(); // temporada
  final _c = _Campos(); // carrera
  late bool _carrera;
  late int _temporada;
  bool _cargando = true;
  bool _guardando = false;

  // Lo que aportan las salidas registradas a la temporada (no se edita aqui).
  int _extraOuts = 0;
  int _extraHits = 0;
  int _extraLimpias = 0;
  int _extraPonches = 0;
  int _extraBoletos = 0;

  _Campos get _activo => _carrera ? _c : _t;

  @override
  void initState() {
    super.initState();
    _carrera = widget.abrirCarrera;
    _temporada = widget.temporadaInicial ?? DateTime.now().year;
    for (final campos in [_t, _c]) {
      for (final ctl in campos.ctrl.values) {
        ctl.addListener(_refrescar);
      }
    }
    _cargarTodo();
  }

  @override
  void dispose() {
    _t.dispose();
    _c.dispose();
    super.dispose();
  }

  void _refrescar() {
    if (mounted) setState(() {});
  }

  void _mensaje(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  // ---------------------------------------------------------------------
  // Carga
  // ---------------------------------------------------------------------

  Future<void> _cargarTodo() async {
    await _cargarTemporada();
    await _cargarCarrera();
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _cargarTemporada() async {
    final base = await DatabaseHelper.instance
        .obtenerLanzadorPerfil(widget.lanzadorId, _temporada);
    final total = await DatabaseHelper.instance
        .obtenerLanzadorPerfilTotal(widget.lanzadorId, _temporada);
    if (!mounted) return;

    if (base == null) {
      _t.poner({});
    } else {
      _t.poner({
        'ganados': base.juegosGanados.toString(),
        'perdidos': base.juegosPerdidos.toString(),
        'aperturas': base.aperturas.toString(),
        'salvados': base.salvados.toString(),
        'lanzados': base.juegosLanzados.toString(),
        'innings': _inningsTexto(base.inningsLanzados),
        'hits': base.hitsPermitidos.toString(),
        'limpias': base.carrerasLimpias.toString(),
        'boletos': base.basesPorBolas.toString(),
        'ponches': base.ponches.toString(),
      });
    }

    final outsTotal = total == null ? 0 : (total.inningsLanzados * 3).round();
    final outsBase = base == null ? 0 : (base.inningsLanzados * 3).round();
    setState(() {
      _extraOuts = outsTotal - outsBase;
      _extraHits = (total?.hitsPermitidos ?? 0) - (base?.hitsPermitidos ?? 0);
      _extraLimpias =
          (total?.carrerasLimpias ?? 0) - (base?.carrerasLimpias ?? 0);
      _extraPonches = (total?.ponches ?? 0) - (base?.ponches ?? 0);
      _extraBoletos =
          (total?.basesPorBolas ?? 0) - (base?.basesPorBolas ?? 0);
    });
  }

  Future<void> _cargarCarrera() async {
    final h = await DatabaseHelper.instance
        .obtenerLanzadorPerfilHistorico(widget.lanzadorId);
    if (!mounted) return;
    if (h == null) {
      _c.poner({});
    } else {
      _c.poner({
        'ganados': h.juegosGanados.toString(),
        'perdidos': h.juegosPerdidos.toString(),
        'aperturas': h.aperturas.toString(),
        'salvados': h.salvados.toString(),
        'lanzados': h.juegosLanzados.toString(),
        'innings': _inningsTexto(h.inningsLanzados),
        'hits': h.hitsPermitidos.toString(),
        'limpias': h.carrerasLimpias.toString(),
        'boletos': h.basesPorBolas.toString(),
        'ponches': h.ponches.toString(),
      });
    }
  }

  // ---------------------------------------------------------------------
  // Acciones
  // ---------------------------------------------------------------------

  Future<void> _tocarTemporada() async {
    if (_carrera) {
      setState(() => _carrera = false);
      return;
    }
    // Ya esta en Temporada: tocar de nuevo permite cambiar el anio.
    final c = TextEditingController(text: _temporada.toString());
    final txt = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Temporada (año)'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
    if (txt == null || !mounted) return;
    final anio = int.tryParse(txt.trim());
    if (anio == null || anio < 1900 || anio > 2200) {
      _mensaje('Escribe un año válido.');
      return;
    }
    if (anio == _temporada) return;
    setState(() {
      _temporada = anio;
      _cargando = true;
    });
    await _cargarTemporada();
    if (mounted) setState(() => _cargando = false);
  }

  void _restablecer() {
    _activo.ponerCeros();
  }

  String _errorDe(String pestana, String clave) {
    final extra = clave == 'innings' ? ' (usa 6, 6.1 o 6.2)' : '';
    return '$pestana: "${_etiquetas[clave]}" no es válido$extra.';
  }

  Future<void> _guardar() async {
    final guardarT = _t.hayCambios;
    final guardarC = _c.hayCambios;
    if (!guardarT && !guardarC) {
      Navigator.pop(context);
      return;
    }

    if (guardarT) {
      final k = _t.campoInvalido();
      if (k != null) {
        _mensaje(_errorDe('Temporada', k));
        return;
      }
    }
    if (guardarC) {
      final k = _c.campoInvalido();
      if (k != null) {
        _mensaje(_errorDe('Carrera', k));
        return;
      }
    }

    setState(() => _guardando = true);
    try {
      if (guardarT) {
        await DatabaseHelper.instance.guardarLanzadorPerfil(
          LanzadorPerfil(
            lanzadorId: widget.lanzadorId,
            temporada: _temporada,
            juegosGanados: _t.entero('ganados')!,
            juegosPerdidos: _t.entero('perdidos')!,
            aperturas: _t.entero('aperturas')!,
            salvados: _t.entero('salvados')!,
            juegosLanzados: _t.entero('lanzados')!,
            inningsLanzados: _t.outs()! / 3.0,
            ponches: _t.entero('ponches')!,
            basesPorBolas: _t.entero('boletos')!,
            hitsPermitidos: _t.entero('hits')!,
            carrerasLimpias: _t.entero('limpias')!,
          ),
        );
      }
      if (guardarC) {
        await DatabaseHelper.instance.guardarLanzadorPerfilHistorico(
          LanzadorPerfilHistorico(
            lanzadorId: widget.lanzadorId,
            juegosGanados: _c.entero('ganados')!,
            juegosPerdidos: _c.entero('perdidos')!,
            aperturas: _c.entero('aperturas')!,
            salvados: _c.entero('salvados')!,
            juegosLanzados: _c.entero('lanzados')!,
            inningsLanzados: _c.outs()! / 3.0,
            ponches: _c.entero('ponches')!,
            basesPorBolas: _c.entero('boletos')!,
            hitsPermitidos: _c.entero('hits')!,
            carrerasLimpias: _c.entero('limpias')!,
          ),
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _mensaje('No se pudo guardar: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Piezas de interfaz
  // ---------------------------------------------------------------------

  Widget _titulo(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(texto, style: _estilo(12, _azul, peso: FontWeight.w500)),
      );

  Widget _encabezado() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Cerrar',
            icon: const Icon(Icons.close, size: 22, color: _tinta),
            onPressed: _guardando ? null : () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              children: [
                Text('Editar estadísticas',
                    style: _estilo(18, _tinta, peso: FontWeight.w500)),
                Text(widget.nombreLanzador,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _estilo(11, _grisTexto)),
              ],
            ),
          ),
          TextButton(
            onPressed: _guardando ? null : _guardar,
            child: Text('Guardar',
                style: _estilo(14, _azul, peso: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _segmento(String texto, bool activo, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: activo ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            texto,
            style: activo
                ? _estilo(13, _tinta, peso: FontWeight.w500)
                : _estilo(13, _grisTexto),
          ),
        ),
      ),
    );
  }

  Widget _pestanas() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _segmentoFondo,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _segmento('Temporada $_temporada', !_carrera, _tocarTemporada),
          _segmento('Carrera', _carrera, () => setState(() => _carrera = true)),
        ],
      ),
    );
  }

  Widget _aviso() {
    final texto = _carrera
        ? 'Editar a mano cambia las cifras de toda la carrera guardadas. Úsalo solo para cargar o corregir datos.'
        : 'Estos valores se suman a las salidas que registres en la app. Úsalo solo para cargar o corregir lo anterior.';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _avisoFondo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _avisoBorde, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 18, color: _avisoIcono),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto, style: _estilo(12, _avisoTexto)),
          ),
        ],
      ),
    );
  }

  Widget _fila(String clave, {required bool primera}) {
    final c = _activo;
    final cambiado = c.cambiado(clave);

    OutlineInputBorder borde(BorderSide lado) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: lado,
        );
    final ladoNormal =
        cambiado ? const BorderSide(color: _naranja, width: 1) : BorderSide.none;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: primera
            ? null
            : const Border(top: BorderSide(color: _bordeClaro, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_etiquetas[clave]!, style: _estilo(13, _tinta)),
                if (cambiado)
                  Text('Antes: ${c.orig[clave]}',
                      style: _estilo(11, _avisoIcono)),
              ],
            ),
          ),
          SizedBox(
            width: 92,
            child: TextField(
              controller: c.ctrl[clave],
              textAlign: TextAlign.center,
              keyboardType:
                  TextInputType.numberWithOptions(decimal: clave == 'innings'),
              style: _estilo(13, _tinta),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: cambiado ? _naranjaSuave : _fondo,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: borde(ladoNormal),
                enabledBorder: borde(ladoNormal),
                focusedBorder: borde(const BorderSide(color: _azul, width: 1)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta(List<String> claves) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _bordeClaro, width: 0.5),
      ),
      child: Column(
        children: [
          for (var i = 0; i < claves.length; i++)
            _fila(claves[i], primera: i == 0),
        ],
      ),
    );
  }

  /// Efectividad, WHIP, K/9 y BB/9. En temporada incluye las salidas registradas.
  List<String> _calculados() {
    final c = _activo;
    final outsForm = c.outs();
    final hits = c.entero('hits');
    final limpias = c.entero('limpias');
    final boletos = c.entero('boletos');
    final ponches = c.entero('ponches');
    if (outsForm == null ||
        hits == null ||
        limpias == null ||
        boletos == null ||
        ponches == null) {
      return ['--', '--', '--', '--'];
    }
    final outs = outsForm + (_carrera ? 0 : _extraOuts);
    final h = hits + (_carrera ? 0 : _extraHits);
    final cl = limpias + (_carrera ? 0 : _extraLimpias);
    final bb = boletos + (_carrera ? 0 : _extraBoletos);
    final k = ponches + (_carrera ? 0 : _extraPonches);
    if (outs == 0) return ['--', '--', '--', '--'];
    return [
      (cl * 27 / outs).toStringAsFixed(2),
      ((bb + h) * 3 / outs).toStringAsFixed(2),
      (k * 27 / outs).toStringAsFixed(1),
      (bb * 27 / outs).toStringAsFixed(1),
    ];
  }

  Widget _tile(String valor, String etiqueta) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: _segmentoFondo,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(valor, style: _estilo(16, _grisBoton, peso: FontWeight.w500)),
          Text(etiqueta, style: _estilo(11, _grisTexto)),
        ],
      ),
    );
  }

  Widget _seccionCalculados() {
    final v = _calculados();
    const nombres = ['Efectiv.', 'WHIP', 'K/9', 'BB/9'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.lock_outline, size: 14, color: _azul),
            const SizedBox(width: 4),
            Text('Se calculan solas',
                style: _estilo(12, _azul, peso: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: _tile(v[i], nombres[i])),
            ],
          ],
        ),
        if (!_carrera)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2),
            child: Text('Incluyen las salidas registradas.',
                style: _estilo(11, _grisTexto)),
          ),
      ],
    );
  }

  Widget _enlaceRestablecer() {
    return Center(
      child: TextButton.icon(
        onPressed: _restablecer,
        icon: const Icon(Icons.restore, size: 16, color: _azul),
        label: Text(
          _carrera ? 'Restablecer a cero' : 'Restablecer a solo salidas registradas',
          style: _estilo(13, _azul),
        ),
      ),
    );
  }

  Widget _barraInferior() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _bordeClaro, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              flex: 1,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _grisBoton,
                  side: const BorderSide(color: _bordeBoton, width: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _guardando ? null : () => Navigator.pop(context),
                child: Text('Descartar', style: _estilo(14, _grisBoton)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _naranja,
                  foregroundColor: _tinta,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _tinta),
                      )
                    : Text('Guardar cambios',
                        style: _estilo(14, _tinta, peso: FontWeight.w500)),
              ),
            ),
          ],
        ),
      ),
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
            _pestanas(),
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        _aviso(),
                        _titulo('Récord y participación'),
                        _tarjeta(const [
                          'ganados',
                          'perdidos',
                          'aperturas',
                          'salvados',
                          'lanzados',
                          'innings',
                        ]),
                        _titulo('Resultados permitidos'),
                        _tarjeta(const [
                          'hits',
                          'limpias',
                          'boletos',
                          'ponches',
                        ]),
                        _seccionCalculados(),
                        const SizedBox(height: 8),
                        _enlaceRestablecer(),
                      ],
                    ),
            ),
            _barraInferior(),
          ],
        ),
      ),
    );
  }
}