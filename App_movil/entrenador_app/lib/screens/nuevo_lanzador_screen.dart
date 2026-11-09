import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/jugador.dart';
import '../models/lanzador_perfil.dart';
import '../models/lanzador_rol.dart';
import '../services/database_helper.dart';

const Color _fondo = Color(0xFFF4F6FA);
const Color _tinta = Color(0xFF0F172A);
const Color _gris = Color(0xFF64748B);
const Color _azul = Color(0xFF1D4ED8);
const Color _azulClaro = Color(0xFFE3ECFF);
const Color _naranja = Color(0xFFFF7A1A);
const Color _borde = Color(0xFFE2E8F0);
const Color _bordeCampo = Color(0xFFCBD5E1);
const Color _textoChip = Color(0xFF334155);

/// Lanzamientos que se ofrecen como botones: nombre en pantalla -> nombre en la base de datos.
const List<List<String>> _lanzamientosBase = [
  ['Recta 4 costuras', 'Four-Seam Fastball'],
  ['Recta 2 costuras', 'Two-Seam Fastball'],
  ['Slider', 'Slider'],
  ['Cambio', 'Changeup'],
  ['Curva', 'Curveball'],
  ['Cutter', 'Cutter'],
];

/// Formulario para agregar un lanzador nuevo al equipo.
class NuevoLanzadorScreen extends StatefulWidget {
  final int equipoId;

  const NuevoLanzadorScreen({super.key, required this.equipoId});

  @override
  State<NuevoLanzadorScreen> createState() => _NuevoLanzadorScreenState();
}

class _NuevoLanzadorScreenState extends State<NuevoLanzadorScreen> {
  final _nombreCtrl = TextEditingController();
  final _numeroCtrl = TextEditingController();
  final _ganadosCtrl = TextEditingController();
  final _perdidosCtrl = TextEditingController();
  final _juegosCtrl = TextEditingController();
  final _inningsCtrl = TextEditingController();
  final _efectividadCtrl = TextEditingController();

  final List<String> _roles = []; // 'abridor', 'relevista', 'cerrador'
  String? _mano; // 'derecho' o 'zurdo' (como lo guarda la app)
  String? _fotoPath;

  /// Lanzamientos disponibles como botones: [etiqueta, nombre en la base].
  final List<List<String>> _opciones = [..._lanzamientosBase];
  final List<String> _seleccionados = []; // nombres de la base, en orden de seleccion
  final Map<String, TextEditingController> _velocidades = {};

  bool _guardando = false;

  @override
  void dispose() {
    for (final c in [
      _nombreCtrl,
      _numeroCtrl,
      _ganadosCtrl,
      _perdidosCtrl,
      _juegosCtrl,
      _inningsCtrl,
      _efectividadCtrl,
      ..._velocidades.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _iniciales() {
    final partes =
        _nombreCtrl.text.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first[0].toUpperCase();
    return '${partes[0][0]}${partes[1][0]}'.toUpperCase();
  }

  Future<void> _elegirFoto() async {
    final imagen = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (imagen != null && mounted) setState(() => _fotoPath = imagen.path);
  }

  void _alternarRol(String rol) {
    setState(() {
      if (!_roles.remove(rol)) _roles.add(rol);
    });
  }

  void _alternarLanzamiento(String nombreBd) {
    setState(() {
      if (_seleccionados.remove(nombreBd)) return;
      _seleccionados.add(nombreBd);
      _velocidades.putIfAbsent(nombreBd, () => TextEditingController());
    });
  }

  Future<void> _agregarOtro() async {
    final ctrl = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Otro lanzamiento'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Nombre del lanzamiento'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (nombre == null || nombre.isEmpty || !mounted) return;
    setState(() {
      if (!_opciones.any((o) => o[1].toLowerCase() == nombre.toLowerCase())) {
        _opciones.add([nombre, nombre]);
      }
      final existente =
          _opciones.firstWhere((o) => o[1].toLowerCase() == nombre.toLowerCase())[1];
      if (!_seleccionados.contains(existente)) {
        _seleccionados.add(existente);
        _velocidades.putIfAbsent(existente, () => TextEditingController());
      }
    });
  }

  String _etiquetaDe(String nombreBd) {
    for (final o in _opciones) {
      if (o[1] == nombreBd) return o[0];
    }
    return nombreBd;
  }

  double? _numero(String texto) => double.tryParse(texto.trim().replaceAll(',', '.'));

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe el nombre del lanzador')),
      );
      return;
    }
    setState(() => _guardando = true);

    try {
      final db = DatabaseHelper.instance;
      final id = await db.crearJugador(
        Jugador(
          equipoId: widget.equipoId,
          nombre: nombre,
          rol: 'lanzador',
          manoLanzamiento: _mano,
          numero: int.tryParse(_numeroCtrl.text.trim()),
          foto: _fotoPath,
        ),
      );

      for (final rol in _roles) {
        await db.agregarRolLanzador(LanzadorRol(lanzadorId: id, rolLanzador: rol));
      }

      for (final nombreBd in _seleccionados) {
        final tipoId = await db.obtenerOCrearTipoLanzamiento(nombreBd);
        await db.guardarLanzadorTipoPicheo(
          lanzadorId: id,
          tipoLanzamientoId: tipoId,
          velocidadPromedio: _numero(_velocidades[nombreBd]?.text ?? ''),
        );
      }

      final ganados = int.tryParse(_ganadosCtrl.text.trim());
      final perdidos = int.tryParse(_perdidosCtrl.text.trim());
      final juegos = int.tryParse(_juegosCtrl.text.trim());
      final innings = _numero(_inningsCtrl.text);
      final era = _numero(_efectividadCtrl.text);

      if (ganados != null || perdidos != null || juegos != null || innings != null || era != null) {
        // La app guarda carreras limpias, no la efectividad: se calcula a partir de ella.
        var carrerasLimpias = 0;
        if (era != null && innings != null && innings > 0) {
          final entero = innings.floor();
          final tercio = ((innings - entero) * 10).round();
          final outs = (tercio >= 0 && tercio <= 2) ? entero * 3 + tercio : (innings * 3).round();
          carrerasLimpias = (era * outs / 27).round();
        }
        await db.guardarLanzadorPerfil(
          LanzadorPerfil(
            lanzadorId: id,
            temporada: DateTime.now().year,
            juegosGanados: ganados ?? 0,
            juegosPerdidos: perdidos ?? 0,
            juegosLanzados: juegos ?? 0,
            inningsLanzados: innings ?? 0,
            carrerasLimpias: carrerasLimpias,
          ),
        );
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    }
  }

  // ---------------------------------------------------------------------
  // Piezas de dibujo
  // ---------------------------------------------------------------------

  Widget _titulo(String texto, {String? opcional}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: texto,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _azul),
            ),
            if (opcional != null)
              TextSpan(
                text: ' $opcional',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: _gris),
              ),
          ],
        ),
      ),
    );
  }

  Widget _etiqueta(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text(texto, style: const TextStyle(fontSize: 11, color: _gris)),
    );
  }

  InputDecoration _decoracionCampo({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _bordeCampo, width: 0.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _azul, width: 1),
      ),
    );
  }

  Widget _campo(
    String etiqueta,
    TextEditingController ctrl, {
    TextInputType teclado = TextInputType.text,
    ValueChanged<String>? alCambiar,
    TextCapitalization mayusculas = TextCapitalization.none,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiqueta(etiqueta),
        TextField(
          controller: ctrl,
          keyboardType: teclado,
          textCapitalization: mayusculas,
          onChanged: alCambiar,
          style: const TextStyle(fontSize: 13, color: _tinta),
          decoration: _decoracionCampo(),
        ),
      ],
    );
  }

  Widget _chip(
    String texto,
    bool seleccionado,
    VoidCallback alTocar, {
    double horizontal = 12,
    bool conCheck = false,
    bool punteado = false,
  }) {
    final fondo = seleccionado ? _azul : Colors.white;
    final letra = seleccionado ? Colors.white : (punteado ? _gris : _textoChip);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: alTocar,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: 6),
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(16),
          border: seleccionado
              ? null
              : Border.all(
                  color: punteado ? const Color(0xFF94A3B8) : _bordeCampo,
                  width: punteado ? 1 : 0.5,
                ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (conCheck && seleccionado) ...[
              const Icon(Icons.check, size: 14, color: Colors.white),
              const SizedBox(width: 4),
            ],
            if (punteado) ...[
              const Icon(Icons.add, size: 14, color: _gris),
              const SizedBox(width: 4),
            ],
            Text(texto, style: TextStyle(fontSize: 12, color: letra)),
          ],
        ),
      ),
    );
  }

  Widget _avatar() {
    final tieneFoto = _fotoPath != null && _fotoPath!.isNotEmpty && File(_fotoPath!).existsSync();
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: _azulClaro,
              backgroundImage: tieneFoto ? FileImage(File(_fotoPath!)) : null,
              child: tieneFoto
                  ? null
                  : Text(
                      _iniciales(),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500, color: _azul),
                    ),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _elegirFoto,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: _naranja,
                    shape: BoxShape.circle,
                    border: Border.all(color: _fondo, width: 2),
                  ),
                  child: const Icon(Icons.photo_camera_outlined, size: 14, color: _tinta),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filaVelocidad(String nombreBd, bool conBorde) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: conBorde ? const Border(top: BorderSide(color: _borde, width: 0.5)) : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(_etiquetaDe(nombreBd), style: const TextStyle(fontSize: 13, color: _tinta)),
          ),
          SizedBox(
            width: 96,
            child: TextField(
              controller: _velocidades[nombreBd],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: _tinta),
              decoration: InputDecoration(
                hintText: '--',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                suffixText: 'mph',
                suffixStyle: const TextStyle(fontSize: 13, color: _tinta),
                isDense: true,
                filled: true,
                fillColor: _fondo,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cuadriculaStats() {
    final campos = [
      _campo('Ganados', _ganadosCtrl, teclado: TextInputType.number),
      _campo('Perdidos', _perdidosCtrl, teclado: TextInputType.number),
      _campo('Juegos', _juegosCtrl, teclado: TextInputType.number),
      _campo('Innings', _inningsCtrl,
          teclado: const TextInputType.numberWithOptions(decimal: true)),
      _campo('Efectividad', _efectividadCtrl,
          teclado: const TextInputType.numberWithOptions(decimal: true)),
    ];
    final filas = <Widget>[];
    for (int i = 0; i < campos.length; i += 3) {
      if (i > 0) filas.add(const SizedBox(height: 8));
      filas.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int k = 0; k < 3; k++) ...[
              if (k > 0) const SizedBox(width: 8),
              Expanded(child: i + k < campos.length ? campos[i + k] : const SizedBox.shrink()),
            ],
          ],
        ),
      );
    }
    return Column(children: filas);
  }

  Widget _botonesInferiores() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _borde, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                flex: 1,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _textoChip,
                    side: const BorderSide(color: Color(0xFF94A3B8), width: 0.5),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _guardando ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar', style: TextStyle(fontSize: 14)),
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
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _guardando ? null : _guardar,
                  child: _guardando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: _tinta),
                        )
                      : const Text('Guardar lanzador',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fondo,
      appBar: AppBar(
        backgroundColor: _fondo,
        foregroundColor: _tinta,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          tooltip: 'Cerrar',
          icon: const Icon(Icons.close, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Nuevo lanzador',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          _avatar(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _titulo('Datos básicos'),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _campo(
                        'Nombre',
                        _nombreCtrl,
                        alCambiar: (_) => setState(() {}),
                        mayusculas: TextCapitalization.words,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: _campo('Número', _numeroCtrl, teclado: TextInputType.number),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _etiqueta('Rol'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _chip('Abridor', _roles.contains('abridor'), () => _alternarRol('abridor')),
                    _chip('Relevista', _roles.contains('relevista'), () => _alternarRol('relevista')),
                    _chip('Cerrador', _roles.contains('cerrador'), () => _alternarRol('cerrador')),
                  ],
                ),
                const SizedBox(height: 8),
                _etiqueta('Lanza con'),
                Wrap(
                  spacing: 6,
                  children: [
                    _chip('Derecha', _mano == 'derecho',
                        () => setState(() => _mano = _mano == 'derecho' ? null : 'derecho'),
                        horizontal: 14),
                    _chip('Izquierda', _mano == 'zurdo',
                        () => setState(() => _mano = _mano == 'zurdo' ? null : 'zurdo'),
                        horizontal: 14),
                  ],
                ),
                const SizedBox(height: 14),
                _titulo('Lanzamientos que domina'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final o in _opciones)
                      _chip(o[0], _seleccionados.contains(o[1]), () => _alternarLanzamiento(o[1]),
                          horizontal: 10, conCheck: true),
                    _chip('Otro', false, _agregarOtro, horizontal: 10, punteado: true),
                  ],
                ),
                if (_seleccionados.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _borde, width: 0.5),
                    ),
                    child: Column(
                      children: [
                        for (int i = 0; i < _seleccionados.length; i++)
                          _filaVelocidad(_seleccionados[i], i > 0),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                _titulo('Estadísticas iniciales', opcional: '(opcional)'),
                _cuadriculaStats(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _botonesInferiores(),
    );
  }
}
