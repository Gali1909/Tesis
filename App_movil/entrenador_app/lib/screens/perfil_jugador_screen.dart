import 'equipos_anteriores_card.dart';
import 'analisis_jugador_card.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/jugador.dart';
import '../models/equipo.dart';
import '../models/lanzador_perfil.dart';
import '../models/lanzador_perfil_historico.dart';
import '../models/bateador_perfil.dart';
import '../models/lanzador_tipo_picheo.dart';
import '../models/bateador_vulnerabilidad.dart';
import '../models/lanzador_rol.dart';
import '../models/jugador_posicion.dart';
import '../services/database_helper.dart';
import 'perfil_bateador_screen.dart';
import 'cargar_lanzador_perfil_screen.dart';
import 'cargar_lanzador_perfil_historico_screen.dart';
import 'registrar_salida_screen.dart';
import 'historial_salidas_screen.dart';
import 'editar_jugador_screen.dart';
import 'cargar_tipo_picheo_screen.dart';
import '../widgets/barra_inferior_app.dart';
import '../widgets/boton_enviar_perfil_pantalla.dart';

const Color _colorAcento = Color(0xFF1D4ED8);
const Color _colorNaranja = Color(0xFFFF7A1A);
const Color _colorFondoPantalla = Color(0xFFF4F6FA);
const Color _colorTinta = Color(0xFF0F172A);
const Color _colorGris = Color(0xFF64748B);
const Color _colorBorde = Color(0xFFE2E8F0);
const Color _colorAzulClaro = Color(0xFFE3ECFF);
const Color _colorAzulTexto = Color(0xFF1E3A8A);
const Color _colorAzulEtiqueta = Color(0xFF3B5BB5);

class PerfilJugadorScreen extends StatefulWidget {
  final Jugador jugador;

  const PerfilJugadorScreen({super.key, required this.jugador});

  @override
  State<PerfilJugadorScreen> createState() => _PerfilJugadorScreenState();
}

class _PerfilJugadorScreenState extends State<PerfilJugadorScreen> {
  late Jugador _jugadorActual;
  Equipo? _equipo;
  LanzadorPerfil? _lanzadorPerfil;
  LanzadorPerfilHistorico? _lanzadorPerfilHistorico;
  List<int> _temporadasDisponibles = [];
  int? _temporadaSeleccionada;
  BateadorPerfil? _bateadorPerfil;
  List<LanzadorTipoPicheo> _tiposPicheo = [];
  List<BateadorVulnerabilidad> _vulnerabilidades = [];
  List<LanzadorRol> _rolesLanzador = [];
  int _vistaSalidas = 0; // 0 = temporada, 5/10/15 = ultimas salidas
  Map<String, dynamic>? _statsUltimas;
  List<JugadorPosicion> _posiciones = [];
  bool _cargando = true;
  bool _mostrarDetalles = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _jugadorActual = widget.jugador;
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final id = widget.jugador.jugadorId!;

    try {
      final equipo = widget.jugador.equipoId == null
          ? null
          : await DatabaseHelper.instance.obtenerEquipoPorId(widget.jugador.equipoId!);

      if (widget.jugador.rol == 'lanzador') {
        final temporadas = await DatabaseHelper.instance.obtenerTemporadasLanzadorTotal(id);
        final historico = await DatabaseHelper.instance.obtenerLanzadorPerfilHistorico(id);
        final tipos = await DatabaseHelper.instance.obtenerTiposPicheo(id);
        final roles = await DatabaseHelper.instance.obtenerRolesLanzador(id);

        LanzadorPerfil? perfilTemporada;
        int? temporadaInicial;
        if (temporadas.isNotEmpty) {
          temporadaInicial = (_temporadaSeleccionada != null && temporadas.contains(_temporadaSeleccionada))
              ? _temporadaSeleccionada!
              : temporadas.first;
          perfilTemporada = await DatabaseHelper.instance.obtenerLanzadorPerfilTotal(id, temporadaInicial);
        }

        setState(() {
          _equipo = equipo;
          _temporadasDisponibles = temporadas;
          _temporadaSeleccionada = temporadaInicial;
          _lanzadorPerfil = perfilTemporada;
          _lanzadorPerfilHistorico = historico;
          _tiposPicheo = tipos;
          _rolesLanzador = roles;
          _cargando = false;
        });
      } else {
        final perfil = await DatabaseHelper.instance.obtenerBateadorPerfil(id);
        final vulnerabilidades = await DatabaseHelper.instance.obtenerVulnerabilidades(id);
        final posiciones = await DatabaseHelper.instance.obtenerPosiciones(id);
        setState(() {
          _equipo = equipo;
          _bateadorPerfil = perfil;
          _vulnerabilidades = vulnerabilidades;
          _posiciones = posiciones;
          _cargando = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  Future<void> _abrirRegistrarSalida() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => RegistrarSalidaScreen(
          lanzadorId: widget.jugador.jugadorId!,
          nombreLanzador: widget.jugador.nombre,
        ),
      ),
    );
    if (ok == true) {
      await _cargarDatos();
      await _recargarUltimas();
    }
  }

  Future<void> _abrirHistorialSalidas() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HistorialSalidasScreen(
          lanzadorId: widget.jugador.jugadorId!,
          nombreLanzador: widget.jugador.nombre,
        ),
      ),
    );
    await _cargarDatos();
    await _recargarUltimas();
  }

  Future<void> _recargarUltimas() async {
    if (_vistaSalidas == 0) return;
    final s = await DatabaseHelper.instance
        .ultimasSalidasLanzador(widget.jugador.jugadorId!, _vistaSalidas);
    if (!mounted) return;
    setState(() => _statsUltimas = s);
  }

  Future<void> _cambiarVistaSalidas(int nueva) async {
    if (nueva == _vistaSalidas) return;
    final s = nueva == 0
        ? null
        : await DatabaseHelper.instance
            .ultimasSalidasLanzador(widget.jugador.jugadorId!, nueva);
    if (!mounted) return;
    setState(() {
      _vistaSalidas = nueva;
      _statsUltimas = s;
    });
  }

  Future<void> _cambiarTemporada(int? nuevaTemporada) async {
    if (nuevaTemporada == null || nuevaTemporada == _temporadaSeleccionada) return;
    final id = widget.jugador.jugadorId!;
    final perfil = await DatabaseHelper.instance.obtenerLanzadorPerfilTotal(id, nuevaTemporada);
    setState(() {
      _temporadaSeleccionada = nuevaTemporada;
      _lanzadorPerfil = perfil;
    });
  }

  Future<void> _abrirFormularioCarga() async {
    final id = widget.jugador.jugadorId!;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CargarLanzadorPerfilScreen(
          lanzadorId: id,
          temporadaInicial: _temporadaSeleccionada,
        ),
      ),
    );
    await _cargarDatos();
  }

  Future<void> _abrirFormularioHistorico() async {
    final id = widget.jugador.jugadorId!;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CargarLanzadorPerfilHistoricoScreen(lanzadorId: id),
      ),
    );
    await _cargarDatos();
  }

  Future<void> _abrirFormularioEditarPerfil() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditarJugadorScreen(jugador: _jugadorActual),
      ),
    );
    final actualizado = await DatabaseHelper.instance.obtenerJugadorPorId(widget.jugador.jugadorId!);
    if (actualizado != null && mounted) {
      setState(() => _jugadorActual = actualizado);
    }
    await _cargarDatos();
  }

  Future<void> _abrirFormularioTipoPicheo({LanzadorTipoPicheo? existente}) async {
    final id = widget.jugador.jugadorId!;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CargarTipoPicheoScreen(
          lanzadorId: id,
          existente: existente,
        ),
      ),
    );
    await _cargarDatos();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.jugador.rol != 'lanzador') {
      return PerfilBateadorScreen(jugador: widget.jugador);
    }
    return Scaffold(
      backgroundColor: _colorFondoPantalla,
      appBar: AppBar(
        backgroundColor: _colorFondoPantalla,
        foregroundColor: _colorTinta,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Lanzadores', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
      ),
      bottomNavigationBar: const BarraInferiorApp(activa: SeccionBarra.equipo),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Error cargando datos: $_error'),
                  ),
                )
              : widget.jugador.rol == 'lanzador'
                  ? _vistaLanzador()
                  : _vistaBateador(),
    );
  }

  Widget _vistaLanzador() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _tarjetaPerfilLanzador(),
        const SizedBox(height: 12),
        _selectorVistaSalidas(),
        const SizedBox(height: 12),
        _filaStatsPrincipales(),
        const SizedBox(height: 16),
        _pitchesDestacados(),
        const SizedBox(height: 16),
        _botonesAccion(),
        const SizedBox(height: 16),
        _tarjetaProximamente(
          'Registro de partidos',
          Icons.sports_score,
          'Se llenara con los datos de juegos individuales cuando esa pantalla este lista.',
        ),
        const SizedBox(height: 16),
        _tarjetaProximamente(
          'Performance actual',
          Icons.show_chart,
          'Graficas de velocidad y precision por juego, cuando existan datos juego por juego.',
        ),
        AnalisisJugadorCard(jugadorId: widget.jugador.jugadorId!, esLanzador: widget.jugador.rol == 'lanzador'),
        EquiposAnterioresCard(jugadorId: widget.jugador.jugadorId!),
        if (_mostrarDetalles) ...[
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          const Text('Temporada', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          _selectorTemporada(),
          const SizedBox(height: 16),
          const Text('Estadisticas de la temporada', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          _lanzadorPerfil == null
              ? const Text('Sin estadisticas cargadas para esta temporada')
              : _tablaEstadisticasLanzador(_lanzadorPerfil!),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Estadisticas de por vida', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                tooltip: 'Editar estadisticas de por vida',
                onPressed: _abrirFormularioHistorico,
              ),
            ],
          ),
          _lanzadorPerfilHistorico == null
              ? const Text('Sin estadisticas historicas cargadas todavia')
              : _tablaEstadisticasHistorico(_lanzadorPerfilHistorico!),
          const SizedBox(height: 16),
          const Text('Detalle de tipos de lanzamiento', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          _tiposPicheo.isEmpty
              ? const Text('Sin tipos de lanzamiento cargados todavia')
              : Column(children: _tiposPicheo.map((t) => _filaTipoPicheo(t)).toList()),
        ],
      ],
    );
  }

  Widget _vistaBateador() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _tarjetaInfoBasica(),
        const SizedBox(height: 16),
        if (_posiciones.isNotEmpty) ...[
          const Text('Posiciones', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Wrap(
            spacing: 8,
            children: _posiciones
                .map((p) => Chip(label: Text(p.posicion)))
                .toList(),
          ),
          const SizedBox(height: 16),
        ],
        const Text('Estadisticas generales', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        _bateadorPerfil == null
            ? const Text('Sin estadisticas cargadas todavia')
            : _tablaEstadisticasBateador(_bateadorPerfil!),
        const SizedBox(height: 16),
        const Text('Vulnerabilidades', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        _vulnerabilidades.isEmpty
            ? const Text('Sin vulnerabilidades cargadas todavia')
            : Column(
                children: _vulnerabilidades.map((v) => _filaVulnerabilidad(v)).toList(),
              ),
      ],
    );
  }

  // ---------- Widgets del rediseno (lanzador) ----------

  String? _abreviaturaMano() {
    final mano = _jugadorActual.manoLanzamiento?.toLowerCase();
    if (mano == 'derecho') return 'RHP';
    if (mano == 'zurdo') return 'LHP';
    return null;
  }

  Widget _pildora(String texto, Color fondo, Color letra) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(8)),
      child: Text(texto, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: letra)),
    );
  }

  Widget _tarjetaPerfilLanzador() {
    final rolPrincipal = _rolesLanzador.isNotEmpty ? _rolesLanzador.first.rolLanzador : null;
    final rolesSecundarios = _rolesLanzador.length > 1 ? _rolesLanzador.skip(1).toList() : <LanzadorRol>[];
    final fotoPath = _jugadorActual.foto;
    final tieneFoto = fotoPath != null && fotoPath.isNotEmpty && File(fotoPath).existsSync();
    final mano = _jugadorActual.manoLanzamiento;
    final partes = <String>[
      if (_equipo != null) _equipo!.nombre,
      if (mano != null && mano.isNotEmpty) 'Lanza $mano',
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _colorBorde, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: _colorAzulClaro,
            backgroundImage: tieneFoto ? FileImage(File(fotoPath)) : null,
            child: tieneFoto ? null : const Icon(Icons.person, size: 28, color: _colorAcento),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: _jugadorActual.nombre,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _colorTinta),
                      ),
                      if (_jugadorActual.numero != null)
                        TextSpan(
                          text: '  #${_jugadorActual.numero}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _colorNaranja),
                        ),
                    ],
                  ),
                ),
                if (partes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(partes.join(' · '), style: const TextStyle(fontSize: 12, color: _colorGris)),
                  ),
                if (rolPrincipal != null || _abreviaturaMano() != null || rolesSecundarios.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (rolPrincipal != null)
                          _pildora(rolPrincipal.toUpperCase(), const Color(0xFFFFE9D6), const Color(0xFF9A3412)),
                        if (_abreviaturaMano() != null)
                          _pildora(_abreviaturaMano()!, _colorAzulClaro, _colorAzulTexto),
                        for (final r in rolesSecundarios)
                          _pildora(r.rolLanzador, const Color(0xFFF1F5F9), const Color(0xFF334155)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _abrirFormularioEditarPerfil,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.edit_outlined, size: 20, color: _colorGris),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectorVistaSalidas() {
    const opciones = [
      [0, 'Temporada'],
      [5, 'Ultimas 5'],
      [10, 'Ultimas 10'],
      [15, 'Ultimas 15'],
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final o in opciones)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _cambiarVistaSalidas(o[0] as int),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _vistaSalidas == o[0] ? _colorAcento : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _vistaSalidas == o[0] ? _colorAcento : const Color(0xFFCBD5E1),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    o[1] as String,
                    style: TextStyle(
                      fontSize: 12,
                      color: _vistaSalidas == o[0] ? Colors.white : const Color(0xFF334155),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filaStatsPrincipales() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _vistaSalidas == 0 ? _statsTemporada() : _statsDeUltimasSalidas(),
      ],
    );
  }

  Widget _statsTemporada() {
    final p = _lanzadorPerfil;
    String v(Object? x) => x?.toString() ?? '--';
    return _cuadricula(
      principales: [
        ['Efectividad', p?.efectividad?.toStringAsFixed(2) ?? '--'],
        ['Gan.-perd.', p == null ? '--' : '${p.juegosGanados}-${p.juegosPerdidos}'],
        ['Innings', p?.inningsFormato ?? '--'],
        ['Juegos', v(p?.juegosLanzados)],
      ],
      secundarias: [
        ['WHIP', p?.whip?.toStringAsFixed(2) ?? '--'],
        ['Ponches', v(p?.ponches)],
        ['BB', v(p?.basesPorBolas)],
        ['Hits', v(p?.hitsPermitidos)],
        ['CL', v(p?.carrerasLimpias)],
        ['Aperturas', v(p?.aperturas)],
        ['Salvados', v(p?.salvados)],
      ],
    );
  }

  Widget _statsDeUltimasSalidas() {
    final s = _statsUltimas;
    if (s == null || (s['salidas'] as int) == 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Sin salidas registradas todavia. Usa REGISTRAR SALIDA.',
          style: TextStyle(color: _colorGris, fontSize: 12),
        ),
      );
    }
    final salidas = s['salidas'] as int;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          salidas < _vistaSalidas
              ? 'Solo hay $salidas salida(s) registrada(s)'
              : 'Ultimas $salidas salidas registradas',
          style: const TextStyle(color: _colorGris, fontSize: 12),
        ),
        const SizedBox(height: 8),
        _cuadricula(
          principales: [
            ['Efectividad', (s['era'] as double).toStringAsFixed(2)],
            ['WHIP', (s['whip'] as double).toStringAsFixed(2)],
            ['K/9', (s['k9'] as double).toStringAsFixed(1)],
            ['Innings', s['ip'].toString()],
          ],
          secundarias: [
            ['Hits', s['h'].toString()],
            ['CL', s['cl'].toString()],
            ['Ponches', s['k'].toString()],
            ['BB', s['bb'].toString()],
            ['Picheos', s['picheos'].toString()],
          ],
        ),
      ],
    );
  }

  Widget _cuadricula({required List<List<String>> principales, required List<List<String>> secundarias}) {
    Widget fila(List<List<String>> items, bool grande) {
      return Row(
        children: [
          for (int i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: i < items.length
                  ? _tileMetrica(items[i][0], items[i][1], grande)
                  : const SizedBox.shrink(),
            ),
          ],
        ],
      );
    }

    final filasSecundarias = <Widget>[];
    for (int i = 0; i < secundarias.length; i += 4) {
      final fin = (i + 4 > secundarias.length) ? secundarias.length : i + 4;
      filasSecundarias.add(const SizedBox(height: 8));
      filasSecundarias.add(fila(secundarias.sublist(i, fin), false));
    }
    return Column(children: [fila(principales, true), ...filasSecundarias]);
  }

  Widget _tileMetrica(String etiqueta, String valor, bool grande) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: grande ? 10 : 8, horizontal: 4),
      decoration: BoxDecoration(
        color: grande ? _colorAzulClaro : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: grande ? null : Border.all(color: _colorBorde, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              valor,
              style: TextStyle(
                fontSize: grande ? 18 : 15,
                fontWeight: FontWeight.w600,
                color: grande ? _colorAzulTexto : _colorTinta,
              ),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              etiqueta,
              style: TextStyle(fontSize: 11, color: grande ? _colorAzulEtiqueta : _colorGris),
            ),
          ),
        ],
      ),
    );
  }

  Widget _botonesAccion() {
    final forma = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    const padding = EdgeInsets.symmetric(vertical: 14);
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _colorAcento,
              foregroundColor: Colors.white,
              padding: padding,
              shape: forma,
            ),
            onPressed: _abrirRegistrarSalida,
            icon: const Icon(Icons.add),
            label: const Text('REGISTRAR SALIDA', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _colorTinta,
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  padding: padding,
                  shape: forma,
                ),
                onPressed: _abrirFormularioCarga,
                child: const Text('EDITAR ESTADISTICAS',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.3)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _colorAcento,
                  side: const BorderSide(color: _colorAcento),
                  padding: padding,
                  shape: forma,
                ),
                onPressed: _abrirHistorialSalidas,
                icon: const Icon(Icons.history, size: 18),
                label: const Text('HISTORIAL',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.3)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        BotonEnviarPerfilPantalla(lanzadorId: widget.jugador.jugadorId!),
        TextButton(
          onPressed: () => setState(() => _mostrarDetalles = !_mostrarDetalles),
          child: Text(
            _mostrarDetalles ? 'OCULTAR ESTADISTICAS COMPLETAS' : 'VER ESTADISTICAS COMPLETAS',
            style: const TextStyle(color: _colorAcento, fontWeight: FontWeight.w600, fontSize: 12, letterSpacing: 0.3),
          ),
        ),
      ],
    );
  }

  Widget _pitchesDestacados() {
    final ordenados = [..._tiposPicheo]
      ..sort((a, b) => (b.frecuencia ?? 0).compareTo(a.frecuencia ?? 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('Repertorio', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _colorTinta)),
              Text('Uso · velocidad · max', style: TextStyle(fontSize: 11, color: _colorGris)),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _colorBorde, width: 0.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              if (ordenados.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('Sin tipos de lanzamiento cargados todavia',
                      style: TextStyle(fontSize: 12, color: _colorGris)),
                ),
              for (int i = 0; i < ordenados.length; i++) _filaRepertorio(ordenados[i], i > 0),
              InkWell(
                onTap: () => _abrirFormularioTipoPicheo(),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: _colorBorde, width: 0.5)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add, size: 18, color: _colorAcento),
                      SizedBox(width: 6),
                      Text('Agregar tipo de lanzamiento',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _colorAcento)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filaRepertorio(LanzadorTipoPicheo t, bool conBorde) {
    final frecuencia = t.frecuencia;
    final factor = ((frecuencia ?? 0) / 100).clamp(0.0, 1.0).toDouble();
    return InkWell(
      onTap: () => _abrirFormularioTipoPicheo(existente: t),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: conBorde ? const Border(top: BorderSide(color: _colorBorde, width: 0.5)) : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.nombreTipo,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _colorTinta)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(color: _colorBorde, borderRadius: BorderRadius.circular(3)),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: factor,
                            child: Container(
                              decoration: BoxDecoration(
                                color: _colorAcento,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 34,
                        child: Text(
                          frecuencia != null ? '${frecuencia.toStringAsFixed(0)}%' : '--',
                          style: const TextStyle(fontSize: 11, color: _colorGris),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  t.velocidadPromedio != null ? '${t.velocidadPromedio!.toStringAsFixed(0)} mph' : '--',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _colorTinta),
                ),
                const SizedBox(height: 2),
                _pildora(
                  t.velocidadMax != null ? 'max ${t.velocidadMax!.toStringAsFixed(0)}' : 'max --',
                  const Color(0xFFDCFCE7),
                  const Color(0xFF166534),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaSeccion({required String titulo, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _colorBorde, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo.toUpperCase(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _colorGris, letterSpacing: 0.5),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _tarjetaProximamente(String titulo, IconData icono, String detalle) {
    return _tarjetaSeccion(
      titulo: titulo,
      child: Column(
        children: [
          Icon(icono, color: Colors.grey.shade400, size: 32),
          const SizedBox(height: 8),
          Text(detalle, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
    );
  }

  // ---------- Widgets existentes ----------

  Widget _tarjetaInfoBasica() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Numero: ${_jugadorActual.numero?.toString() ?? 'N/A'}'),
            if (widget.jugador.rol == 'lanzador')
              Text('Mano: ${_jugadorActual.manoLanzamiento ?? 'N/A'}')
            else
              Text('Mano de bateo: ${_jugadorActual.manoBateo ?? 'N/A'}'),
          ],
        ),
      ),
    );
  }

  Widget _selectorTemporada() {
    if (_temporadasDisponibles.isEmpty) {
      return const Text('Sin temporadas cargadas todavia');
    }
    return DropdownButton<int>(
      value: _temporadaSeleccionada,
      items: _temporadasDisponibles
          .map((t) => DropdownMenuItem(value: t, child: Text(t.toString())))
          .toList(),
      onChanged: _cambiarTemporada,
    );
  }

  Widget _tablaEstadisticasLanzador(LanzadorPerfil p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Efectividad: ${p.efectividad?.toStringAsFixed(2) ?? 'N/A'}'),
        Text('WHIP: ${p.whip?.toStringAsFixed(2) ?? 'N/A'}'),
        Text('Juegos ganados: ${p.juegosGanados}'),
        Text('Juegos perdidos: ${p.juegosPerdidos}'),
        Text('Aperturas: ${p.aperturas}'),
        Text('Salvados: ${p.salvados}'),
        Text('Juegos lanzados: ${p.juegosLanzados}'),
        Text('Innings lanzados: ${p.inningsFormato}'),
        Text('Ponches: ${p.ponches}'),
        Text('Bases por bolas: ${p.basesPorBolas}'),
        Text('Hits permitidos: ${p.hitsPermitidos}'),
        Text('Carreras limpias: ${p.carrerasLimpias}'),
      ],
    );
  }

  Widget _tablaEstadisticasHistorico(LanzadorPerfilHistorico p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Efectividad: ${p.efectividad?.toStringAsFixed(2) ?? 'N/A'}'),
        Text('WHIP: ${p.whip?.toStringAsFixed(2) ?? 'N/A'}'),
        Text('Juegos ganados: ${p.juegosGanados}'),
        Text('Juegos perdidos: ${p.juegosPerdidos}'),
        Text('Aperturas: ${p.aperturas}'),
        Text('Salvados: ${p.salvados}'),
        Text('Juegos lanzados: ${p.juegosLanzados}'),
        Text('Innings lanzados: ${p.inningsLanzados}'),
        Text('Ponches: ${p.ponches}'),
        Text('Bases por bolas: ${p.basesPorBolas}'),
        Text('Hits permitidos: ${p.hitsPermitidos}'),
        Text('Carreras limpias: ${p.carrerasLimpias}'),
      ],
    );
  }

  Widget _tablaEstadisticasBateador(BateadorPerfil p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Promedio de bateo: ${p.promedioBateo?.toStringAsFixed(3) ?? 'N/A'}'),
        Text('Carreras impulsadas: ${p.carrerasImpulsadas}'),
        Text('Carreras anotadas: ${p.carrerasAnotadas}'),
        Text('Home runs: ${p.homeRuns}'),
        Text('Dobles: ${p.dobles}'),
        Text('Triples: ${p.triples}'),
        Text('Hits: ${p.hits}'),
      ],
    );
  }

  Widget _filaTipoPicheo(LanzadorTipoPicheo t) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(t.nombreTipo),
      subtitle: Text(
        'Frecuencia: ${t.frecuencia?.toStringAsFixed(1) ?? 'N/A'}% - Velocidad prom: ${t.velocidadPromedio?.toStringAsFixed(1) ?? 'N/A'} mph',
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => _abrirFormularioTipoPicheo(existente: t),
    );
  }

  Widget _filaVulnerabilidad(BateadorVulnerabilidad v) {
    return ListTile(
      title: Text(v.nombreTipo),
      subtitle: Text(
        'Efectividad contra: ${v.nivelEfectividadContra?.toStringAsFixed(3) ?? 'N/A'} (${v.origen})',
      ),
    );
  }
}







