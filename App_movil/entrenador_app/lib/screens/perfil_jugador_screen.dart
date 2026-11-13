import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/jugador.dart';
import '../models/equipo.dart';
import '../models/lanzador_perfil.dart';
import '../models/lanzador_perfil_historico.dart';
import '../models/lanzador_tipo_picheo.dart';
import '../models/lanzador_rol.dart';
import '../services/database_helper.dart';
import '../widgets/boton_enviar_perfil_pantalla.dart';
import 'agregar_jugador_screen.dart';
import 'analisis_jugador_card.dart';
import 'analisis_screen.dart';


import 'cargar_tipo_picheo_screen.dart';
import 'editar_jugador_screen.dart';
import 'equipos_anteriores_card.dart';
import 'historial_salidas_screen.dart';
import 'perfil_bateador_screen.dart';
import 'registrar_salida_screen.dart';
import 'editar_estadisticas_lanzador_screen.dart';

// Colores tomados del diseno "perfil de lanzador".
const Color _fondo = Color(0xFFF4F6FA);
const Color _tinta = Color(0xFF0F172A);
const Color _azul = Color(0xFF1D4ED8);
const Color _azulOscuro = Color(0xFF1E3A8A);
const Color _azulSuave = Color(0xFF3B5BB5);
const Color _naranja = Color(0xFFFF7A1A);
const Color _grisTexto = Color(0xFF64748B);
const Color _bordeClaro = Color(0xFFE2E8F0);
const Color _bordeChip = Color(0xFFCBD5E1);
const Color _barra = Color(0xFF07182F);
const Color _barraActivo = Color(0xFFE0B04A);
const Color _barraInactivo = Color(0xFF6FA0E8);

TextStyle _estilo(double tamano, Color color,
    {FontWeight peso = FontWeight.w400}) {
  return TextStyle(fontSize: tamano, color: color, fontWeight: peso);
}

class _Stat {
  final String valor;
  final String etiqueta;

  const _Stat(this.valor, this.etiqueta);
}

/// "Juan Perez" -> "J. Perez"
String _abreviar(String nombre) {
  final partes = nombre.trim().split(RegExp(r'\s+'));
  if (partes.length < 2 || partes.first.isEmpty) return nombre.trim();
  return '${partes.first[0].toUpperCase()}. ${partes.sublist(1).join(' ')}';
}

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
  List<LanzadorTipoPicheo> _tiposPicheo = [];
  List<LanzadorRol> _rolesLanzador = [];
  List<Jugador> _companeros = []; // lanzadores del mismo equipo
  int _vistaSalidas = 0; // 0 = temporada, 5/10/15 = ultimas salidas
  Map<String, dynamic>? _statsUltimas;
  bool _cargando = true;
  bool _mostrarDetalles = false;
  String? _error;

  int get _id => _jugadorActual.jugadorId!;

  @override
  void initState() {
    super.initState();
    _jugadorActual = widget.jugador;
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final id = _id;

    try {
      final equipo = _jugadorActual.equipoId == null
          ? null
          : await DatabaseHelper.instance
              .obtenerEquipoPorId(_jugadorActual.equipoId!);

      final temporadas =
          await DatabaseHelper.instance.obtenerTemporadasLanzadorTotal(id);
      final historico =
          await DatabaseHelper.instance.obtenerLanzadorPerfilHistorico(id);
      final tipos = await DatabaseHelper.instance.obtenerTiposPicheo(id);
      final roles = await DatabaseHelper.instance.obtenerRolesLanzador(id);

      var companeros = <Jugador>[];
      final equipoId = _jugadorActual.equipoId;
      if (equipoId != null) {
        final todos =
            await DatabaseHelper.instance.obtenerJugadoresPorEquipo(equipoId);
        companeros = todos.where((j) => j.rol == 'lanzador').toList()
          ..sort((a, b) =>
              a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
      }

      LanzadorPerfil? perfilTemporada;
      int? temporadaInicial;
      if (temporadas.isNotEmpty) {
        temporadaInicial = (_temporadaSeleccionada != null &&
                temporadas.contains(_temporadaSeleccionada))
            ? _temporadaSeleccionada!
            : temporadas.first;
        perfilTemporada = await DatabaseHelper.instance
            .obtenerLanzadorPerfilTotal(id, temporadaInicial);
      }

      if (!mounted) return;
      setState(() {
        _equipo = equipo;
        _temporadasDisponibles = temporadas;
        _temporadaSeleccionada = temporadaInicial;
        _lanzadorPerfil = perfilTemporada;
        _lanzadorPerfilHistorico = historico;
        _tiposPicheo = tipos;
        _rolesLanzador = roles;
        _companeros = companeros;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  Future<void> _cambiarLanzador(Jugador j) async {
    if (j.jugadorId == _jugadorActual.jugadorId) return;
    setState(() {
      _jugadorActual = j;
      _cargando = true;
      _error = null;
      _vistaSalidas = 0;
      _statsUltimas = null;
      _temporadaSeleccionada = null;
      _lanzadorPerfil = null;
      _lanzadorPerfilHistorico = null;
      _tiposPicheo = [];
      _rolesLanzador = [];
      _mostrarDetalles = false;
    });
    await _cargarDatos();
  }

  Future<void> _agregarLanzador() async {
    final equipoId = _jugadorActual.equipoId;
    if (equipoId == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AgregarJugadorScreen(equipoId: equipoId),
      ),
    );
    await _cargarDatos();
  }

  Future<void> _abrirRegistrarSalida() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => RegistrarSalidaScreen(
          lanzadorId: _id,
          nombreLanzador: _jugadorActual.nombre,
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
          lanzadorId: _id,
          nombreLanzador: _jugadorActual.nombre,
        ),
      ),
    );
    await _cargarDatos();
    await _recargarUltimas();
  }

  Future<void> _recargarUltimas() async {
    if (_vistaSalidas == 0) return;
    final s = await DatabaseHelper.instance
        .ultimasSalidasLanzador(_id, _vistaSalidas);
    if (!mounted) return;
    setState(() => _statsUltimas = s);
  }

  Future<void> _cambiarVistaSalidas(int nueva) async {
    if (nueva == _vistaSalidas) return;
    final s = nueva == 0
        ? null
        : await DatabaseHelper.instance.ultimasSalidasLanzador(_id, nueva);
    if (!mounted) return;
    setState(() {
      _vistaSalidas = nueva;
      _statsUltimas = s;
    });
  }

  Future<void> _cambiarTemporada(int? nuevaTemporada) async {
    if (nuevaTemporada == null || nuevaTemporada == _temporadaSeleccionada) {
      return;
    }
    final perfil = await DatabaseHelper.instance
        .obtenerLanzadorPerfilTotal(_id, nuevaTemporada);
    if (!mounted) return;
    setState(() {
      _temporadaSeleccionada = nuevaTemporada;
      _lanzadorPerfil = perfil;
    });
  }

  Future<void> _abrirFormularioCarga() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditarEstadisticasLanzadorScreen(
          nombreLanzador: _jugadorActual.nombre,
          lanzadorId: _id,
          temporadaInicial: _temporadaSeleccionada,
        ),
      ),
    );
    await _cargarDatos();
  }

  Future<void> _abrirFormularioHistorico() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditarEstadisticasLanzadorScreen(
          lanzadorId: _id,
          nombreLanzador: _jugadorActual.nombre,
          temporadaInicial: _temporadaSeleccionada,
          abrirCarrera: true,
        ),
      ),
    );
    await _cargarDatos();
  }

  Future<void> _abrirFormularioEditarPerfil() async {
    final resultado = await Navigator.push<String>(
      context,
      MaterialPageRoute<String>(
        builder: (context) => EditarJugadorScreen(jugador: _jugadorActual),
      ),
    );
    if (!mounted) return;
    if (resultado == 'eliminado') {
      Navigator.pop(context);
      return;
    }
    final actualizado = await DatabaseHelper.instance.obtenerJugadorPorId(_id);
    if (actualizado != null && mounted) {
      setState(() => _jugadorActual = actualizado);
    }
    await _cargarDatos();
  }

  Future<void> _abrirFormularioTipoPicheo({LanzadorTipoPicheo? existente}) async {
    await CargarTipoPicheoScreen.mostrar(
      context,
      lanzadorId: _id,
      existente: existente,
    );
    await _cargarDatos();
  }

  Future<void> _elegirTemporada() async {
    final elegida = await showModalBottomSheet<int>(
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
            for (final t in _temporadasDisponibles)
              ListTile(
                title: Text('Temporada $t'),
                trailing: t == _temporadaSeleccionada
                    ? const Icon(Icons.check, color: _azul)
                    : null,
                onTap: () => Navigator.pop(ctx, t),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    await _cambiarTemporada(elegida);
  }

  void _abrirAjustes() {
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
              title: const Text('Editar perfil'),
              onTap: () {
                Navigator.pop(ctx);
                _abrirFormularioEditarPerfil();
              },
            ),
            ListTile(
              leading: const Icon(Icons.fact_check_outlined, color: _tinta),
              title: const Text('Editar estadísticas de la temporada'),
              onTap: () {
                Navigator.pop(ctx);
                _abrirFormularioCarga();
              },
            ),
            ListTile(
              leading: const Icon(Icons.all_inclusive, color: _tinta),
              title: const Text('Editar estadísticas de por vida'),
              onTap: () {
                Navigator.pop(ctx);
                _abrirFormularioHistorico();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.jugador.rol != 'lanzador') {
      return PerfilBateadorScreen(jugador: widget.jugador);
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: _barra,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _fondo,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _encabezado(),
              Expanded(
                child: _cargando
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text('Error cargando datos: $_error'),
                            ),
                          )
                        : _cuerpo(),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _barraInferior(),
      ),
    );
  }

  Widget _pad(Widget hijo, {double abajo = 10}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, abajo),
      child: hijo,
    );
  }

  Widget _cuerpo() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        _filaLanzadores(),
        const SizedBox(height: 10),
        _pad(_tarjetaPerfil()),
        _filaVistas(),
        const SizedBox(height: 10),
        _pad(_seccionStats(), abajo: 12),
        _pad(_encabezadoRepertorio(), abajo: 6),
        _pad(_tarjetaRepertorio(), abajo: 12),
        _pad(_acciones(), abajo: 12),
        _pad(
          AnalisisJugadorCard(
            key: ValueKey('analisis_$_id'),
            jugadorId: _id,
            esLanzador: true,
          ),
          abajo: 0,
        ),
        _pad(
          EquiposAnterioresCard(
            key: ValueKey('equipos_$_id'),
            jugadorId: _id,
          ),
          abajo: 0,
        ),
        if (_mostrarDetalles) _pad(_detallesCompletos(), abajo: 0),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Encabezado y selector de lanzadores
  // ---------------------------------------------------------------------

  Widget _encabezado() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: _tinta),
            tooltip: 'Volver',
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text('Lanzadores',
                style: _estilo(18, _tinta, peso: FontWeight.w500)),
          ),
          IconButton(
            icon: const Icon(Icons.history, color: _tinta),
            tooltip: 'Historial de salidas',
            onPressed: _abrirHistorialSalidas,
          ),
        ],
      ),
    );
  }

  Widget _pastilla(
    String texto, {
    required bool activa,
    required VoidCallback onTap,
    IconData? icono,
  }) {
    final forma = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: activa
          ? BorderSide.none
          : const BorderSide(color: _bordeChip, width: 0.5),
    );
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: activa ? _azul : Colors.white,
        shape: forma,
        child: InkWell(
          customBorder: forma,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: icono == null ? 12 : 10, vertical: 6),
            child: icono != null
                ? Icon(icono, size: 16, color: const Color(0xFF334155))
                : Text(
                    texto,
                    style: _estilo(
                      12,
                      activa ? Colors.white : const Color(0xFF334155),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _filaLanzadores() {
    final lista = _companeros.isEmpty ? [_jugadorActual] : _companeros;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final j in lista)
            _pastilla(
              _abreviar(j.nombre),
              activa: j.jugadorId == _jugadorActual.jugadorId,
              onTap: () => _cambiarLanzador(j),
            ),
          if (_jugadorActual.equipoId != null)
            _pastilla('', icono: Icons.add, activa: false, onTap: _agregarLanzador),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Tarjeta de perfil
  // ---------------------------------------------------------------------

  String _iniciales() {
    final partes = _jugadorActual.nombre.trim().split(RegExp(r'\s+'));
    final letras = partes
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    return letras.isEmpty ? '?' : letras;
  }

  String _subtitulo() {
    final partes = <String>[];
    if (_equipo != null) partes.add(_equipo!.nombre);
    final mano = _jugadorActual.manoLanzamiento?.toLowerCase();
    if (mano == 'derecho') partes.add('Lanza con derecha');
    if (mano == 'zurdo') partes.add('Lanza con zurda');
    if (_rolesLanzador.isNotEmpty) {
      partes.add(_rolesLanzador
          .map((r) => r.rolLanzador.isEmpty
              ? r.rolLanzador
              : r.rolLanzador[0].toUpperCase() + r.rolLanzador.substring(1))
          .join(', '));
    }
    return partes.join(' · ');
  }

  Widget _tarjetaPerfil() {
    final fotoPath = _jugadorActual.foto;
    final tieneFoto =
        fotoPath != null && fotoPath.isNotEmpty && File(fotoPath).existsSync();
    final subtitulo = _subtitulo();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _bordeClaro, width: 0.5),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFFE3ECFF),
            backgroundImage: tieneFoto ? FileImage(File(fotoPath)) : null,
            child: tieneFoto
                ? null
                : Text(_iniciales(),
                    style: _estilo(16, _azul, peso: FontWeight.w500)),
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
                        style: _estilo(16, _tinta, peso: FontWeight.w500),
                      ),
                      if (_jugadorActual.numero != null)
                        TextSpan(
                          text: ' #${_jugadorActual.numero}',
                          style: _estilo(16, _naranja, peso: FontWeight.w500),
                        ),
                    ],
                  ),
                ),
                if (subtitulo.isNotEmpty)
                  Text(subtitulo, style: _estilo(12, _grisTexto)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20, color: _grisTexto),
            tooltip: 'Editar perfil',
            onPressed: _abrirFormularioEditarPerfil,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Estadisticas (temporada / ultimas salidas)
  // ---------------------------------------------------------------------

  Widget _filaVistas() {
    final etiquetaTemporada = _temporadaSeleccionada == null
        ? 'Temporada'
        : 'Temporada $_temporadaSeleccionada';
    return Padding(
      padding: const EdgeInsets.only(top: 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _pastilla(
              etiquetaTemporada,
              activa: _vistaSalidas == 0,
              onTap: () {
                if (_vistaSalidas == 0 && _temporadasDisponibles.length > 1) {
                  _elegirTemporada();
                } else {
                  _cambiarVistaSalidas(0);
                }
              },
            ),
            for (final n in const [5, 10, 15])
              _pastilla(
                'Últimas $n',
                activa: _vistaSalidas == n,
                onTap: () => _cambiarVistaSalidas(n),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tileStat(_Stat s, {required bool grande}) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: grande ? 10 : 8, horizontal: 6),
      decoration: BoxDecoration(
        color: grande ? const Color(0xFFE3ECFF) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: grande ? null : Border.all(color: _bordeClaro, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              s.valor,
              style: _estilo(grande ? 18 : 15, grande ? _azulOscuro : _tinta,
                  peso: FontWeight.w500),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              s.etiqueta,
              maxLines: 1,
              style: _estilo(11, grande ? _azulSuave : _grisTexto),
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(List<_Stat> stats, {required bool grande}) {
    final filas = <Widget>[];
    for (var i = 0; i < stats.length; i += 4) {
      final tramo = stats.skip(i).take(4).toList();
      filas.add(
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
          child: Row(
            children: [
              for (var j = 0; j < 4; j++) ...[
                if (j > 0) const SizedBox(width: 8),
                Expanded(
                  child: j < tramo.length
                      ? _tileStat(tramo[j], grande: grande)
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Column(children: filas);
  }

  Widget _nota(String texto) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(texto, style: _estilo(11, _grisTexto)),
    );
  }

  Widget _seccionStats() {
    if (_vistaSalidas == 0) {
      final p = _lanzadorPerfil;
      final grandesT = [
        _Stat(p?.efectividad?.toStringAsFixed(2) ?? '--', 'Efectividad'),
        _Stat(p == null ? '--' : '${p.juegosGanados}-${p.juegosPerdidos}',
            'Gan.-perd.'),
        _Stat(p?.inningsFormato ?? '--', 'Innings'),
        _Stat(p?.juegosLanzados.toString() ?? '--', 'Juegos'),
      ];
      final extrasT = [
        _Stat(p?.whip?.toStringAsFixed(2) ?? '--', 'WHIP'),
        _Stat(p?.ponches.toString() ?? '--', 'Ponches'),
        _Stat(p?.basesPorBolas.toString() ?? '--', 'Bases x bolas'),
        _Stat(p?.hitsPermitidos.toString() ?? '--', 'Hits'),
        _Stat(p?.carrerasLimpias.toString() ?? '--', 'Carr. limpias'),
        _Stat(p?.aperturas.toString() ?? '--', 'Aperturas'),
        _Stat(p?.salvados.toString() ?? '--', 'Salvados'),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _grid(grandesT, grande: true),
          const SizedBox(height: 8),
          _grid(extrasT, grande: false),
          if (p == null) _nota('Sin estadísticas cargadas para esta temporada'),
        ],
      );
    }

    final s = _statsUltimas;
    if (s == null || (s['salidas'] as int) == 0) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _bordeClaro, width: 0.5),
        ),
        child: Text(
          'Sin salidas registradas todavía. Usa "Registrar salida".',
          style: _estilo(12, _grisTexto),
        ),
      );
    }
    final salidas = s['salidas'] as int;
    final grandes = [
      _Stat((s['era'] as double).toStringAsFixed(2), 'Efectividad'),
      _Stat((s['whip'] as double).toStringAsFixed(2), 'WHIP'),
      _Stat(s['ip'].toString(), 'Innings'),
      _Stat(salidas.toString(), 'Salidas'),
    ];
    final extras = [
      _Stat((s['k9'] as double).toStringAsFixed(1), 'K/9'),
      _Stat(s['k'].toString(), 'Ponches'),
      _Stat(s['bb'].toString(), 'Bases x bolas'),
      _Stat(s['h'].toString(), 'Hits'),
      _Stat(s['cl'].toString(), 'Carr. limpias'),
      _Stat(s['picheos'].toString(), 'Picheos'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _grid(grandes, grande: true),
        const SizedBox(height: 8),
        _grid(extras, grande: false),
        _nota(salidas < _vistaSalidas
            ? 'Solo hay $salidas salida(s) registrada(s)'
            : 'Últimas $salidas salidas registradas'),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Repertorio
  // ---------------------------------------------------------------------

  Widget _encabezadoRepertorio() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('Repertorio', style: _estilo(15, _tinta, peso: FontWeight.w500)),
        Text('Uso · velocidad · máxima', style: _estilo(11, _grisTexto)),
      ],
    );
  }

  String _porcentaje(double? v) {
    if (v == null) return '--';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  }

  Widget _filaPitch(LanzadorTipoPicheo t, {required bool primero}) {
    final uso = ((t.frecuencia ?? 0) / 100).clamp(0.0, 1.0);
    final velocidad = t.velocidadPromedio == null
        ? '--'
        : '${t.velocidadPromedio!.toStringAsFixed(0)} mph';
    return InkWell(
      onTap: () => _abrirFormularioTipoPicheo(existente: t),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: primero
              ? null
              : const Border(top: BorderSide(color: _bordeClaro, width: 0.5)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.nombreTipo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _estilo(13, _tinta, peso: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: uso.toDouble(),
                            minHeight: 6,
                            backgroundColor: _bordeClaro,
                            valueColor: const AlwaysStoppedAnimation(_azul),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 34,
                        child: Text('${_porcentaje(t.frecuencia)}%',
                            style: _estilo(11, _grisTexto)),
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
                Text(velocidad,
                    style: _estilo(13, _tinta, peso: FontWeight.w500)),
                if (t.velocidadMax != null)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Máx ${t.velocidadMax!.toStringAsFixed(0)}',
                      style: _estilo(11, const Color(0xFF166534)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaRepertorio() {
    final ordenados = [..._tiposPicheo]
      ..sort((a, b) => (b.frecuencia ?? 0).compareTo(a.frecuencia ?? 0));
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _bordeClaro, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (ordenados.isEmpty)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Sin tipos de lanzamiento cargados todavía',
                    style: _estilo(12, _grisTexto)),
              ),
            )
          else
            for (var i = 0; i < ordenados.length; i++)
              _filaPitch(ordenados[i], primero: i == 0),
          InkWell(
            onTap: () => _abrirFormularioTipoPicheo(),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _bordeClaro, width: 0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add, size: 16, color: _azul),
                  const SizedBox(width: 4),
                  Text('Agregar lanzamiento',
                      style: _estilo(13, _azul, peso: FontWeight.w500)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Acciones
  // ---------------------------------------------------------------------

  Widget _acciones() {
    final forma = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _azul,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: forma,
            ),
            onPressed: _abrirRegistrarSalida,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Registrar salida',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF334155),
                  side: const BorderSide(color: Color(0xFF94A3B8), width: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: forma,
                ),
                onPressed: _abrirFormularioCarga,
                child: const Text('Editar estadísticas',
                    style: TextStyle(fontSize: 13)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF334155),
                  side: const BorderSide(color: Color(0xFF94A3B8), width: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: forma,
                ),
                onPressed: _abrirHistorialSalidas,
                child: const Text('Historial de salidas',
                    style: TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        BotonEnviarPerfilPantalla(
          key: ValueKey('envio_$_id'),
          lanzadorId: _id,
        ),
        TextButton(
          onPressed: () => setState(() => _mostrarDetalles = !_mostrarDetalles),
          child: Text(
            _mostrarDetalles
                ? 'Ocultar estadísticas completas'
                : 'Ver estadísticas completas',
            style: _estilo(12, _azul, peso: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Detalle completo (temporada, por vida, tipos)
  // ---------------------------------------------------------------------

  Widget _detallesCompletos() {
    final titulo = _estilo(14, _tinta, peso: FontWeight.w500);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _bordeClaro, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Temporada', style: titulo),
          const SizedBox(height: 4),
          _selectorTemporada(),
          const SizedBox(height: 12),
          Text('Estadísticas de la temporada', style: titulo),
          const SizedBox(height: 6),
          _lanzadorPerfil == null
              ? const Text('Sin estadísticas cargadas para esta temporada')
              : _tablaEstadisticasLanzador(_lanzadorPerfil!),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Estadísticas de por vida', style: titulo),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: 'Editar estadísticas de por vida',
                onPressed: _abrirFormularioHistorico,
              ),
            ],
          ),
          _lanzadorPerfilHistorico == null
              ? const Text('Sin estadísticas históricas cargadas todavía')
              : _tablaEstadisticasHistorico(_lanzadorPerfilHistorico!),
          const SizedBox(height: 12),
          Text('Detalle de tipos de lanzamiento', style: titulo),
          const SizedBox(height: 6),
          _tiposPicheo.isEmpty
              ? const Text('Sin tipos de lanzamiento cargados todavía')
              : Column(
                  children: _tiposPicheo.map((t) => _filaTipoPicheo(t)).toList(),
                ),
        ],
      ),
    );
  }

  Widget _selectorTemporada() {
    if (_temporadasDisponibles.isEmpty) {
      return const Text('Sin temporadas cargadas todavía');
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

  // ---------------------------------------------------------------------
  // Barra inferior
  // ---------------------------------------------------------------------

  Widget _itemBarra(
      IconData icono, String texto, Color color, VoidCallback? onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 26, color: color),
            const SizedBox(height: 2),
            Text(texto, style: _estilo(13, color)),
          ],
        ),
      ),
    );
  }

  Widget _barraInferior() {
    return Material(
      color: _barra,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _itemBarra(
                Icons.home_outlined,
                'Inicio',
                _barraInactivo,
                () => Navigator.of(context).popUntil((r) => r.isFirst),
              ),
              _itemBarra(Icons.groups_outlined, 'Equipo', _barraActivo, null),
              _itemBarra(
                Icons.bar_chart,
                'Análisis',
                _barraInactivo,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AnalisisScreen()),
                ),
              ),
              _itemBarra(
                Icons.settings_outlined,
                'Ajustes',
                _barraInactivo,
                _abrirAjustes,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
