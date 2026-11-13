import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/jugador.dart';
import '../models/lanzador_perfil.dart';
import '../models/lanzador_tipo_picheo.dart';
import '../services/database_helper.dart';
import 'cargar_lanzador_perfil_screen.dart';
import 'cargar_tipo_picheo_screen.dart';

// Colores tomados del diseno "editar lanzador".
const Color _fondo = Color(0xFFF4F6FA);
const Color _tinta = Color(0xFF0F172A);
const Color _azul = Color(0xFF1D4ED8);
const Color _naranja = Color(0xFFFF7A1A);
const Color _grisTexto = Color(0xFF64748B);
const Color _bordeCampo = Color(0xFFCBD5E1);
const Color _bordeClaro = Color(0xFFE2E8F0);
const Color _rojo = Color(0xFFB91C1C);

TextStyle _estilo(double tamano, Color color,
    {FontWeight peso = FontWeight.w400}) {
  return TextStyle(fontSize: tamano, color: color, fontWeight: peso);
}

/// Pantalla para editar el perfil de un jugador (lanzador).
///
/// Al cerrarse devuelve 'eliminado' si el jugador fue eliminado; en cualquier
/// otro caso devuelve null.
class EditarJugadorScreen extends StatefulWidget {
  final Jugador jugador;

  const EditarJugadorScreen({super.key, required this.jugador});

  @override
  State<EditarJugadorScreen> createState() => _EditarJugadorScreenState();
}

class _EditarJugadorScreenState extends State<EditarJugadorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _numeroCtrl = TextEditingController();

  String? _manoLanzamiento;
  String? _fotoPath;
  Set<String> _rolesSeleccionados = {};
  List<LanzadorTipoPicheo> _tipos = [];
  LanzadorPerfil? _perfil;
  int? _temporada;
  bool _cargando = true;
  bool _guardando = false;

  static const _rolesDisponibles = ['abridor', 'relevista', 'cerrador'];

  bool get _esLanzador => widget.jugador.rol == 'lanzador';

  @override
  void initState() {
    super.initState();
    _nombreCtrl.text = widget.jugador.nombre;
    _numeroCtrl.text = widget.jugador.numero?.toString() ?? '';
    _manoLanzamiento = widget.jugador.manoLanzamiento;
    _fotoPath = widget.jugador.foto;
    _cargarInicial();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _numeroCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarInicial() async {
    try {
      if (_esLanzador) {
        final roles = await DatabaseHelper.instance
            .obtenerRolesLanzador(widget.jugador.jugadorId!);
        _rolesSeleccionados = roles.map((r) => r.rolLanzador).toSet();
        await _cargarRepertorioYStats(actualizarPantalla: false);
      }
    } catch (e) {
      debugPrint('Editar perfil: error cargando datos: $e');
    }
    if (!mounted) return;
    setState(() => _cargando = false);
  }

  Future<void> _cargarRepertorioYStats({bool actualizarPantalla = true}) async {
    final id = widget.jugador.jugadorId!;
    final tipos = [...await DatabaseHelper.instance.obtenerTiposPicheo(id)];
    tipos.sort((a, b) => (b.frecuencia ?? 0).compareTo(a.frecuencia ?? 0));
    final temporadas =
        await DatabaseHelper.instance.obtenerTemporadasLanzadorTotal(id);
    LanzadorPerfil? perfil;
    int? temporada;
    if (temporadas.isNotEmpty) {
      temporada = temporadas.first;
      perfil =
          await DatabaseHelper.instance.obtenerLanzadorPerfilTotal(id, temporada);
    }
    if (!mounted) return;
    if (actualizarPantalla) {
      setState(() {
        _tipos = tipos;
        _temporada = temporada;
        _perfil = perfil;
      });
    } else {
      _tipos = tipos;
      _temporada = temporada;
      _perfil = perfil;
    }
  }

  Future<void> _elegirFoto() async {
    final picker = ImagePicker();
    final imagen =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (imagen != null) {
      setState(() => _fotoPath = imagen.path);
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    final id = widget.jugador.jugadorId!;
    final numero = _numeroCtrl.text.trim().isEmpty
        ? null
        : int.tryParse(_numeroCtrl.text.trim());

    await DatabaseHelper.instance.actualizarDatosBasicosJugador(
      jugadorId: id,
      nombre: _nombreCtrl.text.trim(),
      numero: numero,
      manoLanzamiento: _manoLanzamiento,
      foto: _fotoPath,
    );

    if (_esLanzador) {
      await DatabaseHelper.instance.borrarPosicionesYRoles(id);
      for (final rol in _rolesSeleccionados) {
        await DatabaseHelper.instance.agregarRolLanzadorTexto(id, rol);
      }
    }

    if (!mounted) return;
    setState(() => _guardando = false);
    Navigator.pop(context);
  }

  Future<void> _abrirTipo({LanzadorTipoPicheo? existente}) async {
    await CargarTipoPicheoScreen.mostrar(
      context,
      lanzadorId: widget.jugador.jugadorId!,
      existente: existente,
    );
    await _cargarRepertorioYStats();
  }

  Future<void> _quitarTipo(LanzadorTipoPicheo t) async {
    if (t.id == null) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar lanzamiento'),
        content: Text('¿Quitar "${t.nombreTipo}" del repertorio?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('QUITAR', style: TextStyle(color: _rojo)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    await DatabaseHelper.instance.borrarLanzadorTipoPicheo(t.id!);
    await _cargarRepertorioYStats();
  }

  Future<void> _corregirEstadisticas() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CargarLanzadorPerfilScreen(
          lanzadorId: widget.jugador.jugadorId!,
          temporadaInicial: _temporada,
        ),
      ),
    );
    await _cargarRepertorioYStats();
  }

  Future<void> _eliminar() async {
    final etiqueta = _esLanzador ? 'lanzador' : 'jugador';
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Eliminar $etiqueta'),
        content: Text(
          'Se eliminará a ${widget.jugador.nombre} junto con sus estadísticas, '
          'su repertorio y su historial de salidas. Esta acción no se puede '
          'deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ELIMINAR', style: TextStyle(color: _rojo)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    await DatabaseHelper.instance.borrarJugador(widget.jugador.jugadorId!);
    if (!mounted) return;
    Navigator.pop(context, 'eliminado');
  }

  // ---------------------------------------------------------------------
  // Piezas de dibujo
  // ---------------------------------------------------------------------

  InputDecoration _decoracion() {
    OutlineInputBorder borde(Color color, [double ancho = 0.5]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color, width: ancho),
      );
    }

    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: borde(_bordeCampo),
      enabledBorder: borde(_bordeCampo),
      focusedBorder: borde(_azul, 1.2),
      errorBorder: borde(_rojo),
      focusedErrorBorder: borde(_rojo, 1.2),
    );
  }

  Widget _titulo(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(texto, style: _estilo(12, _azul, peso: FontWeight.w500)),
    );
  }

  Widget _etiqueta(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text(texto, style: _estilo(11, _grisTexto)),
    );
  }

  Widget _pastilla(String texto,
      {required bool activa, required VoidCallback onTap}) {
    final forma = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: activa
          ? BorderSide.none
          : const BorderSide(color: _bordeCampo, width: 0.5),
    );
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: activa ? _azul : Colors.white,
        shape: forma,
        child: InkWell(
          customBorder: forma,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
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

  String _iniciales() {
    final partes = _nombreCtrl.text.trim().split(RegExp(r'\s+'));
    final letras = partes
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    return letras.isEmpty ? '?' : letras;
  }

  Widget _encabezado() {
    final numero = _numeroCtrl.text.trim();
    final subtitulo = numero.isEmpty
        ? _nombreCtrl.text.trim()
        : '${_nombreCtrl.text.trim()} #$numero';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: _tinta),
            tooltip: 'Cerrar',
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              children: [
                Text('Editar perfil',
                    style: _estilo(18, _tinta, peso: FontWeight.w500)),
                Text(
                  subtitulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _estilo(11, _grisTexto),
                ),
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

  Widget _avatar() {
    final tieneFoto = _fotoPath != null &&
        _fotoPath!.isNotEmpty &&
        File(_fotoPath!).existsSync();
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: GestureDetector(
        onTap: _elegirFoto,
        child: Column(
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor: const Color(0xFFE3ECFF),
              backgroundImage: tieneFoto ? FileImage(File(_fotoPath!)) : null,
              child: tieneFoto
                  ? null
                  : Text(_iniciales(),
                      style: _estilo(22, _azul, peso: FontWeight.w500)),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.photo_camera_outlined, size: 14, color: _azul),
                const SizedBox(width: 4),
                Text('Cambiar foto', style: _estilo(12, _azul)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _datosBasicos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _titulo('Datos básicos'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _etiqueta('Nombre'),
                  TextFormField(
                    controller: _nombreCtrl,
                    style: _estilo(13, _tinta),
                    textCapitalization: TextCapitalization.words,
                    decoration: _decoracion(),
                    onChanged: (_) => setState(() {}),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _etiqueta('Número'),
                  TextFormField(
                    controller: _numeroCtrl,
                    style: _estilo(13, _tinta),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _decoracion(),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_esLanzador) ...[
          const SizedBox(height: 10),
          _etiqueta('Mano de lanzamiento'),
          Row(
            children: [
              _pastilla(
                'Derecho',
                activa: _manoLanzamiento == 'derecho',
                onTap: () => setState(() => _manoLanzamiento = 'derecho'),
              ),
              _pastilla(
                'Zurdo',
                activa: _manoLanzamiento == 'zurdo',
                onTap: () => setState(() => _manoLanzamiento = 'zurdo'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _etiqueta('Rol'),
          Wrap(
            runSpacing: 6,
            children: [
              for (final rol in _rolesDisponibles)
                _pastilla(
                  rol[0].toUpperCase() + rol.substring(1),
                  activa: _rolesSeleccionados.contains(rol),
                  onTap: () => setState(() {
                    if (_rolesSeleccionados.contains(rol)) {
                      _rolesSeleccionados.remove(rol);
                    } else {
                      _rolesSeleccionados.add(rol);
                    }
                  }),
                ),
            ],
          ),
        ],
      ],
    );
  }

  String _porcentaje(double? v) {
    if (v == null) return '--';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  }

  Widget _filaTipo(LanzadorTipoPicheo t, {required bool primero, required bool destacado}) {
    final velocidad = t.velocidadPromedio == null
        ? '--'
        : '${t.velocidadPromedio!.toStringAsFixed(0)} mph';
    return Container(
      decoration: BoxDecoration(
        border: primero
            ? null
            : const Border(top: BorderSide(color: _bordeClaro, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _abrirTipo(existente: t),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.nombreTipo,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _estilo(13, _tinta)),
                          Text('Uso ${_porcentaje(t.frecuencia)}%',
                              style: _estilo(11, _grisTexto)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: destacado
                            ? const Color(0xFFFFF1E6)
                            : _fondo,
                        borderRadius: BorderRadius.circular(8),
                        border: destacado
                            ? Border.all(color: _naranja)
                            : null,
                      ),
                      child: Text(velocidad, style: _estilo(13, _tinta)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline,
                size: 18, color: Color(0xFF94A3B8)),
            tooltip: 'Quitar lanzamiento',
            onPressed: () => _quitarTipo(t),
          ),
        ],
      ),
    );
  }

  Widget _repertorio() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('Repertorio',
                style: _estilo(12, _azul, peso: FontWeight.w500)),
            Text('Toca un lanzamiento para editarlo',
                style: _estilo(11, _grisTexto)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.only(left: 12, right: 2, top: 4, bottom: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _bordeClaro, width: 0.5),
          ),
          child: _tipos.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text('Sin lanzamientos cargados todavía',
                      style: _estilo(12, _grisTexto)),
                )
              : Column(
                  children: [
                    for (var i = 0; i < _tipos.length; i++)
                      _filaTipo(_tipos[i],
                          primero: i == 0, destacado: i == 0),
                  ],
                ),
        ),
        const SizedBox(height: 8),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _abrirTipo(),
          child: CustomPaint(
            painter: _BordeDiscontinuo(color: const Color(0xFF94A3B8), radio: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(9),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add, size: 16, color: _grisTexto),
                  const SizedBox(width: 4),
                  Text('Agregar lanzamiento', style: _estilo(13, _grisTexto)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _campoLectura(String etiqueta, String valor) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _corregirEstadisticas,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _etiqueta(etiqueta),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _bordeCampo, width: 0.5),
              ),
              child: Text(valor, style: _estilo(13, _tinta)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _estadisticas() {
    final p = _perfil;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Estadísticas',
                style: _estilo(12, _azul, peso: FontWeight.w500)),
            if (_temporada != null)
              Text('Temporada $_temporada', style: _estilo(11, _grisTexto)),
          ],
        ),
        const SizedBox(height: 2),
        Text('Se actualizan con cada juego. Edítalas solo para corregir.',
            style: _estilo(11, _grisTexto)),
        const SizedBox(height: 8),
        Row(
          children: [
            _campoLectura('Ganados', p?.juegosGanados.toString() ?? '--'),
            const SizedBox(width: 8),
            _campoLectura('Perdidos', p?.juegosPerdidos.toString() ?? '--'),
            const SizedBox(width: 8),
            _campoLectura('Juegos', p?.juegosLanzados.toString() ?? '--'),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _corregirEstadisticas,
            icon: const Icon(Icons.edit_outlined, size: 14),
            label: const Text('Corregir estadísticas'),
            style: TextButton.styleFrom(
              foregroundColor: _azul,
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _botonEliminar() {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _eliminar,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFCA5A5), width: 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.delete_outline, size: 16, color: _rojo),
            const SizedBox(width: 6),
            Text(_esLanzador ? 'Eliminar lanzador' : 'Eliminar jugador',
                style: _estilo(13, _rojo)),
          ],
        ),
      ),
    );
  }

  Widget _barraAcciones() {
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
                  foregroundColor: const Color(0xFF334155),
                  side: const BorderSide(color: Color(0xFF94A3B8), width: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _guardando ? null : () => Navigator.pop(context),
                child: const Text('Descartar', style: TextStyle(fontSize: 14)),
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
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _tinta),
                      )
                    : const Text('Guardar cambios',
                        style:
                            TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: _fondo,
        body: SafeArea(
          bottom: false,
          child: _cargando
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _encabezado(),
                    Expanded(
                      child: Form(
                        key: _formKey,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          children: [
                            Center(child: _avatar()),
                            _datosBasicos(),
                            if (_esLanzador) ...[
                              const SizedBox(height: 16),
                              _repertorio(),
                              const SizedBox(height: 16),
                              _estadisticas(),
                            ],
                            const SizedBox(height: 8),
                            _botonEliminar(),
                          ],
                        ),
                      ),
                    ),
                    _barraAcciones(),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Borde punteado redondeado para el boton "Agregar lanzamiento".
class _BordeDiscontinuo extends CustomPainter {
  final Color color;
  final double radio;

  const _BordeDiscontinuo({required this.color, required this.radio});

  @override
  void paint(Canvas canvas, Size size) {
    final pincel = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final borde = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radio),
    );
    final camino = Path()..addRRect(borde);
    for (final tramo in camino.computeMetrics()) {
      var distancia = 0.0;
      while (distancia < tramo.length) {
        canvas.drawPath(tramo.extractPath(distancia, distancia + 5), pincel);
        distancia += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BordeDiscontinuo viejo) =>
      viejo.color != color || viejo.radio != radio;
}
