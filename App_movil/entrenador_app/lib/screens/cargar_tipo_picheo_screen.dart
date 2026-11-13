import 'package:flutter/material.dart';
import '../models/lanzador_tipo_picheo.dart';
import '../services/database_helper.dart';

// Colores tomados del diseno "agregar lanzamiento".
const Color _tinta = Color(0xFF0F172A);
const Color _azul = Color(0xFF1D4ED8);
const Color _naranja = Color(0xFFFF7A1A);
const Color _grisTexto = Color(0xFF64748B);
const Color _grisClaro = Color(0xFF94A3B8);
const Color _bordeCampo = Color(0xFFCBD5E1);
const Color _bordeClaro = Color(0xFFE2E8F0);
const Color _rojo = Color(0xFFB91C1C);

const double _velocidadMinima = 60;
const double _velocidadMaxima = 105;
const double _velocidadInicial = 90;

TextStyle _estilo(double tamano, Color color,
    {FontWeight peso = FontWeight.w400}) {
  return TextStyle(fontSize: tamano, color: color, fontWeight: peso);
}

/// Hoja inferior para agregar (o editar) un lanzamiento del repertorio.
///
/// Se abre con [CargarTipoPicheoScreen.mostrar] y devuelve true si se guardo
/// o se quito un lanzamiento, o null si se cancelo.
class CargarTipoPicheoScreen extends StatefulWidget {
  final int lanzadorId;
  final LanzadorTipoPicheo? existente;

  const CargarTipoPicheoScreen({
    super.key,
    required this.lanzadorId,
    this.existente,
  });

  static Future<bool?> mostrar(
    BuildContext context, {
    required int lanzadorId,
    LanzadorTipoPicheo? existente,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x8C0F172A),
      builder: (_) => CargarTipoPicheoScreen(
        lanzadorId: lanzadorId,
        existente: existente,
      ),
    );
  }

  @override
  State<CargarTipoPicheoScreen> createState() => _CargarTipoPicheoScreenState();
}

class _CargarTipoPicheoScreenState extends State<CargarTipoPicheoScreen> {
  static const _valorNuevo = -1;

  final _formKey = GlobalKey<FormState>();
  final _nombreNuevoCtrl = TextEditingController();
  final _frecuenciaCtrl = TextEditingController();
  final _velocidadMaxCtrl = TextEditingController();

  List<Map<String, dynamic>> _catalogo = [];
  Set<int> _yaAgregados = {};
  int? _tipoSeleccionado;
  double? _velocidad;
  String? _errorTipo;
  bool _cargando = true;
  bool _guardando = false;

  bool get _editando => widget.existente != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existente;
    if (e != null) {
      _frecuenciaCtrl.text = e.frecuencia?.toString() ?? '';
      _velocidadMaxCtrl.text = e.velocidadMax?.toString() ?? '';
      _velocidad = e.velocidadPromedio;
      _tipoSeleccionado = e.tipoLanzamientoId;
    }
    _cargarCatalogo();
  }

  @override
  void dispose() {
    _nombreNuevoCtrl.dispose();
    _frecuenciaCtrl.dispose();
    _velocidadMaxCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarCatalogo() async {
    try {
      final catalogo =
          await DatabaseHelper.instance.obtenerCatalogoTiposLanzamiento();
      final actuales =
          await DatabaseHelper.instance.obtenerTiposPicheo(widget.lanzadorId);
      if (!mounted) return;
      setState(() {
        _catalogo = catalogo;
        _yaAgregados = actuales
            .where((t) => t.id != widget.existente?.id)
            .map((t) => t.tipoLanzamientoId)
            .toSet();
        _cargando = false;
      });
    } catch (e) {
      debugPrint('Agregar lanzamiento: no se pudo leer el catalogo: $e');
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  void _ajustarVelocidad(double delta) {
    setState(() {
      final base = _velocidad ?? _velocidadInicial;
      _velocidad =
          (base + delta).clamp(_velocidadMinima, _velocidadMaxima).toDouble();
    });
  }

  String _textoVelocidad() {
    final v = _velocidad;
    if (v == null) return '--';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  }

  String? _validarDecimalOpcional(String? valor) {
    if (valor == null || valor.trim().isEmpty) return null;
    if (double.tryParse(valor.trim().replaceAll(',', '.')) == null) {
      return 'Debe ser un número';
    }
    return null;
  }

  double? _leerDecimal(TextEditingController ctrl) {
    final texto = ctrl.text.trim().replaceAll(',', '.');
    return texto.isEmpty ? null : double.tryParse(texto);
  }

  Future<void> _guardar() async {
    setState(() => _errorTipo = null);
    final formularioOk = _formKey.currentState!.validate();
    if (_tipoSeleccionado == null) {
      setState(() => _errorTipo = 'Selecciona un tipo de lanzamiento');
      return;
    }
    if (!formularioOk) return;

    setState(() => _guardando = true);

    try {
      int tipoLanzamientoId;
      if (_tipoSeleccionado == _valorNuevo) {
        tipoLanzamientoId = await DatabaseHelper.instance
            .obtenerOCrearTipoLanzamiento(_nombreNuevoCtrl.text.trim());
      } else {
        tipoLanzamientoId = _tipoSeleccionado!;
      }

      if (_yaAgregados.contains(tipoLanzamientoId)) {
        if (!mounted) return;
        setState(() {
          _guardando = false;
          _errorTipo = 'Ese lanzamiento ya está en el repertorio';
        });
        return;
      }

      await DatabaseHelper.instance.guardarLanzadorTipoPicheo(
        id: widget.existente?.id,
        lanzadorId: widget.lanzadorId,
        tipoLanzamientoId: tipoLanzamientoId,
        frecuencia: _leerDecimal(_frecuenciaCtrl),
        velocidadPromedio: _velocidad,
        velocidadMax: _leerDecimal(_velocidadMaxCtrl),
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _errorTipo = 'No se pudo guardar: $e';
      });
    }
  }

  Future<void> _quitar() async {
    final id = widget.existente?.id;
    if (id == null) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar lanzamiento'),
        content: const Text('¿Quitar este lanzamiento del repertorio?'),
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
    await DatabaseHelper.instance.borrarLanzadorTipoPicheo(id);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  // ---------------------------------------------------------------------
  // Piezas de dibujo
  // ---------------------------------------------------------------------

  Widget _etiqueta(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(texto, style: _estilo(11, _grisTexto)),
    );
  }

  Widget _chipTipo({
    required String texto,
    required bool seleccionado,
    required bool deshabilitado,
    required VoidCallback onTap,
  }) {
    final forma = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: (seleccionado || deshabilitado)
          ? BorderSide.none
          : const BorderSide(color: _bordeCampo, width: 0.5),
    );
    final colorFondo = seleccionado
        ? _azul
        : deshabilitado
            ? const Color(0xFFF1F5F9)
            : Colors.white;
    final colorTexto = seleccionado
        ? Colors.white
        : deshabilitado
            ? _grisClaro
            : const Color(0xFF334155);
    return Material(
      color: colorFondo,
      shape: forma,
      child: InkWell(
        customBorder: forma,
        onTap: deshabilitado ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (seleccionado) ...[
                const Icon(Icons.check, size: 14, color: Colors.white),
                const SizedBox(width: 4),
              ],
              Text(texto, style: _estilo(12, colorTexto)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipOtro() {
    final seleccionado = _tipoSeleccionado == _valorNuevo;
    if (seleccionado) {
      return _chipTipo(
        texto: 'Otro',
        seleccionado: true,
        deshabilitado: false,
        onTap: () {},
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() {
        _tipoSeleccionado = _valorNuevo;
        _errorTipo = null;
      }),
      child: CustomPaint(
        painter: _BordeDiscontinuo(color: _grisClaro, radio: 16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add, size: 14, color: _grisTexto),
              const SizedBox(width: 4),
              Text('Otro', style: _estilo(12, _grisTexto)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectorTipo() {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in _catalogo)
              Builder(builder: (context) {
                final id = t['tipo_lanzamiento_id'] as int;
                final nombre = t['nombre'] as String;
                final repetido = _yaAgregados.contains(id);
                return _chipTipo(
                  texto: repetido ? '$nombre · ya agregado' : nombre,
                  seleccionado: _tipoSeleccionado == id,
                  deshabilitado: repetido,
                  onTap: () => setState(() {
                    _tipoSeleccionado = id;
                    _errorTipo = null;
                  }),
                );
              }),
            _chipOtro(),
          ],
        ),
        if (_tipoSeleccionado == _valorNuevo) ...[
          const SizedBox(height: 10),
          TextFormField(
            controller: _nombreNuevoCtrl,
            autofocus: true,
            style: _estilo(13, _tinta),
            textCapitalization: TextCapitalization.sentences,
            decoration: _decoracion('Nombre del nuevo lanzamiento'),
            validator: (v) {
              if (_tipoSeleccionado != _valorNuevo) return null;
              if (v == null || v.trim().isEmpty) return 'Requerido';
              return null;
            },
          ),
        ],
        if (_errorTipo != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_errorTipo!, style: _estilo(11, _rojo)),
          ),
      ],
    );
  }

  InputDecoration _decoracion(String? sugerencia) {
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
      hintText: sugerencia,
      hintStyle: _estilo(13, _grisClaro),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: borde(_bordeCampo),
      enabledBorder: borde(_bordeCampo),
      focusedBorder: borde(_azul, 1.2),
      errorBorder: borde(_rojo),
      focusedErrorBorder: borde(_rojo, 1.2),
    );
  }

  Widget _botonRedondo(IconData icono, String tooltip, VoidCallback onTap) {
    return Material(
      color: const Color(0xFFF1F5F9),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(icono, size: 18, color: const Color(0xFF334155)),
          ),
        ),
      ),
    );
  }

  Widget _velocidadPromedio() {
    final valorSlider = (_velocidad ?? _velocidadMinima)
        .clamp(_velocidadMinima, _velocidadMaxima)
        .toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiqueta('Velocidad promedio'),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _botonRedondo(
                Icons.remove, 'Bajar velocidad', () => _ajustarVelocidad(-1)),
            const SizedBox(width: 18),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: _textoVelocidad(),
                    style: _estilo(26, _tinta, peso: FontWeight.w500),
                  ),
                  TextSpan(
                    text: ' mph',
                    style: _estilo(13, _grisTexto),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            _botonRedondo(
                Icons.add, 'Subir velocidad', () => _ajustarVelocidad(1)),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            activeTrackColor: _azul,
            inactiveTrackColor: _bordeClaro,
            thumbColor: _naranja,
            overlayColor: const Color(0x33FF7A1A),
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 10,
              elevation: 0,
              pressedElevation: 0,
            ),
          ),
          child: Slider(
            min: _velocidadMinima,
            max: _velocidadMaxima,
            value: valorSlider,
            onChanged: (v) => setState(() => _velocidad = v.roundToDouble()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${_velocidadMinima.toStringAsFixed(0)} mph',
                  style: _estilo(11, _grisClaro)),
              Text('${_velocidadMaxima.toStringAsFixed(0)} mph',
                  style: _estilo(11, _grisClaro)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _camposNumericos() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('Frecuencia de uso (%)',
                    style: _estilo(11, _grisTexto)),
              ),
              TextFormField(
                controller: _frecuenciaCtrl,
                style: _estilo(13, _tinta),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: _decoracion('Opcional'),
                validator: _validarDecimalOpcional,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('Velocidad máxima (mph)',
                    style: _estilo(11, _grisTexto)),
              ),
              TextFormField(
                controller: _velocidadMaxCtrl,
                style: _estilo(13, _tinta),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: _decoracion('Opcional'),
                validator: _validarDecimalOpcional,
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.of(context).viewInsets.bottom;
    final altoMaximo = MediaQuery.of(context).size.height * 0.92;
    return Padding(
      padding: EdgeInsets.only(bottom: teclado),
      child: Container(
        constraints: BoxConstraints(maxHeight: altoMaximo),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: _bordeCampo,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _editando ? 'Editar lanzamiento' : 'Agregar lanzamiento',
                        style: _estilo(17, _tinta, peso: FontWeight.w500),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close,
                            size: 20, color: _grisTexto),
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _etiqueta('Tipo de lanzamiento'),
                  _selectorTipo(),
                  const SizedBox(height: 14),
                  _velocidadPromedio(),
                  const SizedBox(height: 14),
                  _camposNumericos(),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _naranja,
                        foregroundColor: _tinta,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _guardando ? null : _guardar,
                      child: _guardando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: _tinta),
                            )
                          : Text(
                              _editando
                                  ? 'Guardar cambios'
                                  : 'Agregar al repertorio',
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton(
                      onPressed:
                          _guardando ? null : () => Navigator.pop(context),
                      child: Text('Cancelar', style: _estilo(13, _grisTexto)),
                    ),
                  ),
                  if (_editando)
                    Center(
                      child: TextButton(
                        onPressed: _guardando ? null : _quitar,
                        child: Text('Quitar del repertorio',
                            style: _estilo(13, _rojo)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Borde punteado redondeado para el chip "Otro".
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
        canvas.drawPath(tramo.extractPath(distancia, distancia + 4), pincel);
        distancia += 7;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BordeDiscontinuo viejo) =>
      viejo.color != color || viejo.radio != radio;
}
