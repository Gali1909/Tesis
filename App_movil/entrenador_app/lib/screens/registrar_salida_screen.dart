import 'package:flutter/material.dart';
import '../models/equipo.dart';
import '../models/lanzador_perfil.dart';
import '../models/lanzador_tipo_picheo.dart';
import '../services/database_helper.dart';
import 'resultado_juego_seccion.dart' show ResultadoJuegoController;

// Colores tomados de la maqueta "Registrar salida" (mismos del perfil).
const Color _fondo = Color(0xFFF4F6FA);
const Color _tinta = Color(0xFF0F172A);
const Color _azul = Color(0xFF1D4ED8);
const Color _azulOscuro = Color(0xFF1E3A8A);
const Color _azulCaja = Color(0xFFE3ECFF);
const Color _naranja = Color(0xFFFF7A1A);
const Color _grisTexto = Color(0xFF64748B);
const Color _grisBoton = Color(0xFF334155);
const Color _bordeClaro = Color(0xFFE2E8F0);
const Color _bordeCampo = Color(0xFFCBD5E1);
const Color _bordeBoton = Color(0xFF94A3B8);

TextStyle _estilo(double tamano, Color color,
    {FontWeight peso = FontWeight.w400}) {
  return TextStyle(fontSize: tamano, color: color, fontWeight: peso);
}

/// Convierte "6", "6.1" o "6.2" a outs (19 para 6.1). Devuelve null si es invalido.
int? outsDesdeInnings(String texto) {
  final t = texto.trim().replaceAll(',', '.');
  final m = RegExp(r'^(\d+)(?:\.([0-2]))?$').firstMatch(t);
  if (m == null) return null;
  return int.parse(m.group(1)!) * 3 + int.parse(m.group(2) ?? '0');
}

String _inningsDeOuts(int outs) => '${outs ~/ 3}.${outs % 3}';

class RegistrarSalidaScreen extends StatefulWidget {
  final int lanzadorId;
  final String nombreLanzador;

  const RegistrarSalidaScreen({
    super.key,
    required this.lanzadorId,
    required this.nombreLanzador,
  });

  @override
  State<RegistrarSalidaScreen> createState() => _RegistrarSalidaScreenState();
}

class _RegistrarSalidaScreenState extends State<RegistrarSalidaScreen> {
  static const List<String> _meses = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];

  DateTime _fecha = DateTime.now();
  bool _guardando = false;
  final _resultado = ResultadoJuegoController();

  List<Equipo> _rivales = [];
  List<LanzadorTipoPicheo> _tipos = [];
  LanzadorPerfil? _perfilActual; // totales de la temporada de la fecha elegida

  // Rendimiento
  int _outs = 0; // innings en outs (19 = 6.1)
  int _hits = 0;
  int _carreras = 0;
  int _limpias = 0;
  int _boletos = 0;
  int _ponches = 0;

  // Lanzamientos usados: por tipo del repertorio, o un total si no hay repertorio.
  final Map<int, int> _conteo = {};
  int _picheosManual = 0;

  int get _picheosTotal => _tipos.isEmpty
      ? _picheosManual
      : _conteo.values.fold<int>(0, (a, b) => a + b);

  @override
  void initState() {
    super.initState();
    _cargarRivales();
    _cargarTipos();
    _cargarPerfil();
  }

  @override
  void dispose() {
    _resultado.dispose();
    super.dispose();
  }

  Future<void> _cargarRivales() async {
    final lista = await DatabaseHelper.instance.obtenerEquiposRivales();
    if (!mounted) return;
    setState(() => _rivales = lista);
  }

  Future<void> _cargarTipos() async {
    final lista =
        await DatabaseHelper.instance.obtenerTiposPicheo(widget.lanzadorId);
    if (!mounted) return;
    setState(() {
      _tipos = lista;
      for (final t in lista) {
        _conteo.putIfAbsent(t.tipoLanzamientoId, () => 0);
      }
    });
  }

  Future<void> _cargarPerfil() async {
    final anio = _fecha.year;
    final p = await DatabaseHelper.instance
        .obtenerLanzadorPerfilTotal(widget.lanzadorId, anio);
    if (!mounted || anio != _fecha.year) return;
    setState(() => _perfilActual = p);
  }

  String _fechaIso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fechaVista(DateTime d) {
    final base = '${d.day} ${_meses[d.month - 1]}';
    return d.year == DateTime.now().year ? base : '$base ${d.year}';
  }

  Future<void> _elegirFecha() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (elegida != null) {
      setState(() {
        _fecha = elegida;
        _perfilActual = null;
      });
      await _cargarPerfil();
    }
  }

  void _mensaje(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  // ---------------------------------------------------------------------
  // Edicion de valores
  // ---------------------------------------------------------------------

  Future<String?> _pedirValor(String titulo, String inicial,
      {required bool decimal}) {
    final c = TextEditingController(text: inicial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
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
  }

  Future<void> _editarEntero(
      String titulo, int actual, void Function(int) alAceptar) async {
    final txt = await _pedirValor(titulo, actual.toString(), decimal: false);
    if (txt == null || !mounted) return;
    final n = int.tryParse(txt.trim());
    if (n == null || n < 0) {
      _mensaje('Escribe un numero entero mayor o igual a 0.');
      return;
    }
    setState(() => alAceptar(n));
  }

  Future<void> _editarInnings() async {
    final txt =
        await _pedirValor('Innings (ej. 6.1)', _inningsDeOuts(_outs), decimal: true);
    if (txt == null || !mounted) return;
    final outs = outsDesdeInnings(txt);
    if (outs == null) {
      _mensaje('Innings invalidos. Usa 6, 6.1 o 6.2 (solo .1 y .2 como fraccion).');
      return;
    }
    setState(() => _outs = outs);
  }

  // ---------------------------------------------------------------------
  // Guardar
  // ---------------------------------------------------------------------

  Future<void> _guardar() async {
    final picheos = _picheosTotal;

    if (_outs == 0 && picheos == 0) {
      _mensaje('Ingresa los innings o los picheos lanzados.');
      return;
    }
    if (_limpias > _carreras) {
      _mensaje('Las carreras limpias no pueden superar las carreras permitidas.');
      return;
    }

    final errorResultado = _resultado.validar();
    if (errorResultado != null) {
      _mensaje(errorResultado);
      return;
    }

    setState(() => _guardando = true);
    try {
      await DatabaseHelper.instance.registrarSalidaLanzador(
        lanzadorId: widget.lanzadorId,
        fecha: _fechaIso(_fecha),
        equipoRivalId: _resultado.rivalId,
        carrerasPropias: _resultado.carrerasPropias,
        carrerasRival: _resultado.carrerasRival,
        outs: _outs,
        picheos: picheos,
        carrerasPermitidas: _carreras,
        carrerasLimpias: _limpias,
        hitsPermitidos: _hits,
        ponches: _ponches,
        basesPorBolas: _boletos,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _mensaje(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _mensaje('No se pudo guardar la salida: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Piezas de interfaz
  // ---------------------------------------------------------------------

  Widget _titulo(String texto) =>
      Text(texto, style: _estilo(12, _azul, peso: FontWeight.w500));

  Widget _etiqueta(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Text(texto, style: _estilo(11, _grisTexto)),
      );

  Widget _caja({required Widget child, VoidCallback? onTap}) {
    final contenido = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _bordeCampo, width: 0.5),
      ),
      child: child,
    );
    if (onTap == null) return contenido;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: contenido,
    );
  }

  Widget _encabezado() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
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
                Text('Registrar salida',
                    style: _estilo(18, _tinta, peso: FontWeight.w500)),
                Text(widget.nombreLanzador,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _estilo(11, _grisTexto)),
              ],
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _seccionJuego() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _titulo('Juego'),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _etiqueta('Fecha'),
                  _caja(
                    onTap: _elegirFecha,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_fechaVista(_fecha), style: _estilo(13, _tinta)),
                        const Icon(Icons.calendar_today_outlined,
                            size: 16, color: _grisTexto),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _etiqueta('Rival'),
                  _caja(child: _selectorRival()),
                ],
              ),
            ),
          ],
        ),
        if (_rivales.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text('No hay equipos rivales cargados todavía.',
                style: _estilo(11, _grisTexto)),
          ),
        const SizedBox(height: 8),
        _etiqueta('Marcador (opcional)'),
        Row(
          children: [
            Expanded(child: _campoMarcador(_resultado.propias, 'Carreras propias')),
            const SizedBox(width: 8),
            Expanded(child: _campoMarcador(_resultado.rival, 'Carreras del rival')),
          ],
        ),
      ],
    );
  }

  Widget _selectorRival() {
    return SizedBox(
      height: 18,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          isExpanded: true,
          isDense: true,
          value: _resultado.rivalId,
          icon: const Icon(Icons.keyboard_arrow_down,
              size: 16, color: _grisTexto),
          style: _estilo(13, _tinta),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('Sin rival')),
            for (final e in _rivales)
              DropdownMenuItem<int?>(
                value: e.equipoId,
                child: Text(e.nombre, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() => _resultado.rivalId = v),
        ),
      ),
    );
  }

  Widget _campoMarcador(TextEditingController c, String pista) {
    OutlineInputBorder borde(Color color, double ancho) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: ancho),
        );
    return TextField(
      controller: c,
      keyboardType: TextInputType.number,
      style: _estilo(13, _tinta),
      decoration: InputDecoration(
        isDense: true,
        hintText: pista,
        hintStyle: _estilo(13, _grisTexto),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        enabledBorder: borde(_bordeCampo, 0.5),
        focusedBorder: borde(_azul, 1),
        border: borde(_bordeCampo, 0.5),
      ),
    );
  }

  Widget _paso(IconData icono, String etiqueta, VoidCallback onTap) {
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icono, size: 18, color: _grisTexto, semanticLabel: etiqueta),
      ),
    );
  }

  Widget _tarjetaStat({
    required String etiqueta,
    required String valor,
    required VoidCallback restar,
    required VoidCallback sumar,
    required VoidCallback editar,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _bordeClaro, width: 0.5),
      ),
      child: Column(
        children: [
          Text(etiqueta, style: _estilo(11, _grisTexto)),
          InkWell(
            onTap: editar,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Text(valor,
                  style: _estilo(20, _tinta, peso: FontWeight.w500)),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _paso(Icons.remove, 'Restar', restar),
              const SizedBox(width: 4),
              _paso(Icons.add, 'Sumar', sumar),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tarjetaContador(String etiqueta, int valor, void Function(int) poner) {
    return _tarjetaStat(
      etiqueta: etiqueta,
      valor: valor.toString(),
      restar: () => setState(() {
        if (valor > 0) poner(valor - 1);
      }),
      sumar: () => setState(() => poner(valor + 1)),
      editar: () => _editarEntero(etiqueta, valor, poner),
    );
  }

  Widget _seccionRendimiento() {
    final tarjetas = <Widget>[
      _tarjetaStat(
        etiqueta: 'Innings',
        valor: _inningsDeOuts(_outs),
        restar: () => setState(() {
          if (_outs > 0) _outs--;
        }),
        sumar: () => setState(() => _outs++),
        editar: _editarInnings,
      ),
      _tarjetaContador('Hits', _hits, (n) => _hits = n),
      _tarjetaContador('Carreras', _carreras, (n) => _carreras = n),
      _tarjetaContador('Limpias', _limpias, (n) => _limpias = n),
      _tarjetaContador('Boletos', _boletos, (n) => _boletos = n),
      _tarjetaContador('Ponches', _ponches, (n) => _ponches = n),
    ];

    final filas = <Widget>[];
    for (var i = 0; i < tarjetas.length; i += 3) {
      if (i > 0) filas.add(const SizedBox(height: 8));
      filas.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var j = 0; j < 3; j++) ...[
              if (j > 0) const SizedBox(width: 8),
              Expanded(child: tarjetas[i + j]),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _titulo('Rendimiento'),
        const SizedBox(height: 8),
        ...filas,
      ],
    );
  }

  Widget _filaLanzamiento(String nombre, int valor, void Function(int) poner,
      {required bool primera}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        border: primera
            ? null
            : const Border(top: BorderSide(color: _bordeClaro, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(nombre,
                overflow: TextOverflow.ellipsis,
                style: _estilo(13, _tinta)),
          ),
          _paso(Icons.remove, 'Restar', () {
            if (valor > 0) setState(() => poner(valor - 1));
          }),
          InkWell(
            onTap: () => _editarEntero(nombre, valor, poner),
            child: SizedBox(
              width: 34,
              child: Text(valor.toString(),
                  textAlign: TextAlign.center,
                  style: _estilo(14, _tinta, peso: FontWeight.w500)),
            ),
          ),
          _paso(Icons.add, 'Sumar', () => setState(() => poner(valor + 1))),
        ],
      ),
    );
  }

  Widget _seccionLanzamientos() {
    final filas = <Widget>[];
    if (_tipos.isEmpty) {
      filas.add(_filaLanzamiento(
        'Picheos lanzados',
        _picheosManual,
        (n) => _picheosManual = n,
        primera: true,
      ));
    } else {
      for (var i = 0; i < _tipos.length; i++) {
        final t = _tipos[i];
        filas.add(_filaLanzamiento(
          t.nombreTipo,
          _conteo[t.tipoLanzamientoId] ?? 0,
          (n) => _conteo[t.tipoLanzamientoId] = n,
          primera: i == 0,
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _titulo('Lanzamientos usados'),
            Text('Total: $_picheosTotal', style: _estilo(11, _grisTexto)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _bordeClaro, width: 0.5),
          ),
          child: Column(children: filas),
        ),
        if (_tipos.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text('Este lanzador aún no tiene repertorio cargado.',
                style: _estilo(11, _grisTexto)),
          ),
      ],
    );
  }

  Widget _filaVistaPrevia(String etiqueta, String antes, String despues) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta, style: _estilo(12, _azulOscuro)),
          Text.rich(
            TextSpan(
              style: _estilo(12, _azulOscuro),
              children: [
                TextSpan(text: '$antes → '),
                TextSpan(
                  text: despues,
                  style: _estilo(12, _azulOscuro, peso: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _vistaPrevia() {
    final p = _perfilActual;
    final outsBase = p == null ? 0 : (p.inningsLanzados * 3).round();
    final limpiasBase = p?.carrerasLimpias ?? 0;
    final outsNuevo = outsBase + _outs;
    final limpiasNuevo = limpiasBase + _limpias;

    String era(int outs, int limpias) =>
        outs == 0 ? '--' : (limpias * 27 / outs).toStringAsFixed(2);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _azulCaja,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Así cambiará su perfil',
              style: _estilo(12, _azulOscuro, peso: FontWeight.w500)),
          const SizedBox(height: 6),
          _filaVistaPrevia(
            'Efectividad',
            era(outsBase, limpiasBase),
            era(outsNuevo, limpiasNuevo),
          ),
          _filaVistaPrevia(
            'Innings',
            _inningsDeOuts(outsBase),
            _inningsDeOuts(outsNuevo),
          ),
        ],
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
                child: Text('Cancelar', style: _estilo(14, _grisBoton)),
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
                    : Text('Guardar salida',
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
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  _seccionJuego(),
                  const SizedBox(height: 16),
                  _seccionRendimiento(),
                  const SizedBox(height: 16),
                  _seccionLanzamientos(),
                  const SizedBox(height: 14),
                  _vistaPrevia(),
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