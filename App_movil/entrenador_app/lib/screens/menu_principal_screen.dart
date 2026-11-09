import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/equipo.dart';
import '../services/cambios_db.dart';
import '../services/database_helper.dart';
import '../services/pantalla_ble.dart';
import 'analisis_screen.dart';
import 'debug_tablas_screen.dart';
import 'enviar_pantalla_screen.dart';
import 'equipos_screen.dart';
import 'juego_vivo_inicio_screen.dart';
import 'jugadores_libres_screen.dart';
import 'lineups_screen.dart';
import 'record_juegos_screen.dart';
import 'roster_screen.dart';

// Colores tomados del diseno "menu mosaico con barra".
const Color _fondo = Color(0xFFF4F6FA);
const Color _tinta = Color(0xFF0F172A);
const Color _azul = Color(0xFF1D4ED8);
const Color _azulSuave = Color(0xFFBFDBFE);
const Color _naranja = Color(0xFFFF7A1A);
const Color _grisTexto = Color(0xFF64748B);
const Color _bordeClaro = Color(0xFFE2E8F0);
const Color _barra = Color(0xFF07182F);
const Color _barraActivo = Color(0xFFE0B04A);
const Color _barraInactivo = Color(0xFF6FA0E8);

TextStyle _estilo(double tamano, Color color,
    {FontWeight peso = FontWeight.w500}) {
  return TextStyle(fontSize: tamano, color: color, fontWeight: peso);
}

class _LanzadorEra {
  final String nombre;
  final double? era;

  const _LanzadorEra(this.nombre, this.era);
}

/// "Juan Perez" -> "J. Perez"
String _abreviar(String nombre) {
  final partes = nombre.trim().split(RegExp(r'\s+'));
  if (partes.length < 2 || partes.first.isEmpty) return nombre.trim();
  return '${partes.first[0].toUpperCase()}. ${partes.sublist(1).join(' ')}';
}

class MenuPrincipalScreen extends StatefulWidget {
  final int equipoId;
  final String nombreEquipo;
  final ValueChanged<String>? onNombreCambiado;

  const MenuPrincipalScreen({
    super.key,
    required this.equipoId,
    required this.nombreEquipo,
    this.onNombreCambiado,
  });

  @override
  State<MenuPrincipalScreen> createState() => _MenuPrincipalScreenState();
}

class _MenuPrincipalScreenState extends State<MenuPrincipalScreen> {
  List<_LanzadorEra> _lanzadores = const [];
  Map<String, int>? _record;
  int _jugadas = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  /// Carga los datos que se muestran en las tarjetas (record, jugadas y ERA).
  Future<void> _cargar() async {
    final dbh = DatabaseHelper.instance;
    Map<String, int>? record;
    var jugadas = 0;
    final lista = <_LanzadorEra>[];

    try {
      record = await dbh.recordEquipo(anio: DateTime.now().year);
    } catch (e) {
      debugPrint('Menu: no se pudo leer el record: $e');
    }

    try {
      final db = await dbh.database;
      final r = await db.rawQuery('SELECT COUNT(*) AS n FROM jugada_estrategica');
      jugadas = (r.first['n'] as num).toInt();
    } catch (e) {
      debugPrint('Menu: no se pudo contar las jugadas: $e');
    }

    try {
      final propios = await dbh.obtenerLanzadoresPropios();
      for (final l in propios) {
        final id = l['jugador_id'] as int;
        double? era;
        final temporadas = await dbh.obtenerTemporadasLanzadorTotal(id);
        if (temporadas.isNotEmpty) {
          final perfil = await dbh.obtenerLanzadorPerfilTotal(id, temporadas.first);
          era = perfil?.efectividad;
        }
        lista.add(_LanzadorEra((l['nombre'] ?? '').toString(), era));
      }
      lista.sort((a, b) {
        if (a.era == null && b.era == null) return a.nombre.compareTo(b.nombre);
        if (a.era == null) return 1;
        if (b.era == null) return -1;
        return a.era!.compareTo(b.era!);
      });
    } catch (e) {
      debugPrint('Menu: no se pudo leer los lanzadores: $e');
    }

    if (!mounted) return;
    setState(() {
      _record = record;
      _jugadas = jugadas;
      _lanzadores = lista;
    });
  }

  /// Abre una pantalla y, al volver, refresca los datos del menu.
  Future<void> _ir(Widget destino) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => destino),
    );
    if (mounted) _cargar();
  }

  Future<void> _renombrar() async {
    final controller = TextEditingController(text: widget.nombreEquipo);
    final nuevo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nombre del equipo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('GUARDAR'),
          ),
        ],
      ),
    );
    if (nuevo == null || nuevo.isEmpty || nuevo == widget.nombreEquipo) return;
    await DatabaseHelper.instance.actualizarEquipo(
      Equipo(equipoId: widget.equipoId, nombre: nuevo, tipo: 'propio'),
    );
    widget.onNombreCambiado?.call(nuevo);
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
              title: const Text('Nombre del equipo'),
              subtitle: Text(widget.nombreEquipo),
              onTap: () {
                Navigator.pop(ctx);
                _renombrar();
              },
            ),
            ListTile(
              leading: const Icon(Icons.storage_outlined, color: _tinta),
              title: const Text('Tablas de la base de datos'),
              subtitle: const Text('Revisar los datos guardados'),
              onTap: () {
                Navigator.pop(ctx);
                _ir(const DebugTablasScreen());
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Piezas de dibujo
  // ---------------------------------------------------------------------

  Widget _tarjeta({
    required Color color,
    required VoidCallback onTap,
    required Widget child,
    Border? borde,
  }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: borde == null
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: borde,
                ),
          padding: const EdgeInsets.all(14),
          child: child,
        ),
      ),
    );
  }

  Widget _encabezado() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 10),
      child: Row(
        children: [
          Image.asset(
            'assets/images/logo_diamond.png',
            width: 36,
            height: 36,
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Inicio', style: _estilo(20, _tinta)),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _renombrar,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          widget.nombreEquipo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _estilo(12, _grisTexto, peso: FontWeight.w400),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit_outlined,
                          size: 12, color: _grisTexto),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.emoji_events_outlined, color: _tinta),
            tooltip: 'Record y juegos',
            onPressed: () => _ir(const RecordJuegosScreen()),
          ),
          IconButton(
            icon: const Icon(Icons.person_search_outlined, color: _tinta),
            tooltip: 'Jugadores libres',
            onPressed: () => _ir(JugadoresLibresScreen(
              equipoId: widget.equipoId,
              nombreEquipo: widget.nombreEquipo,
            )),
          ),
        ],
      ),
    );
  }

  Widget _dato(IconData icono, String etiqueta, String valor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x24FFFFFF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, size: 12, color: _azulSuave),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  etiqueta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _estilo(11, _azulSuave, peso: FontWeight.w400),
                ),
              ),
            ],
          ),
          Text(
            valor,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _estilo(13, Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaEstado() {
    final ble = PantallaBle.instance;
    final conectado = ble.conectado;
    final r = _record;
    var record = '-- G - -- P';
    if (r != null) {
      final g = r['g'] ?? 0;
      final p = r['p'] ?? 0;
      final e = r['e'] ?? 0;
      record = e > 0 ? '$g G - $p P - $e E' : '$g G - $p P';
    }
    final nombreBle = ble.nombre.isEmpty ? 'Coach' : ble.nombre;
    return _tarjeta(
      color: _azul,
      onTap: () => _ir(const EnviarPantallaScreen()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  conectado ? 'Sistema listo' : 'Pantalla sin conectar',
                  style: _estilo(16, Colors.white),
                ),
              ),
              Icon(
                conectado
                    ? Icons.check_circle_outline
                    : Icons.bluetooth_disabled,
                size: 22,
                color: _azulSuave,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _dato(Icons.bluetooth, 'Bluetooth',
                    conectado ? nombreBle : 'Desconectado'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _dato(Icons.emoji_events_outlined,
                    'Temporada ${DateTime.now().year}', record),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filaEra(_LanzadorEra l) {
    const color = Color(0xFF1E3A8A);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFB7CBF5), width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _abreviar(l.nombre),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _estilo(12, color, peso: FontWeight.w400),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            l.era == null ? '--' : l.era!.toStringAsFixed(2),
            style: _estilo(12, color),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaLanzadores() {
    const titulo = Color(0xFF1E3A8A);
    const sub = Color(0xFF3B5BB5);
    final visibles = _lanzadores.take(2).toList();
    return _tarjeta(
      color: const Color(0xFFE3ECFF),
      onTap: () => _ir(RosterScreen(
        equipoId: widget.equipoId,
        nombreEquipo: widget.nombreEquipo,
      )),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.sports_baseball, size: 26, color: _azul),
              const SizedBox(height: 8),
              Text('Lanzadores', style: _estilo(15, titulo)),
              Text('Perfiles y lanzamientos',
                  style: _estilo(11, sub, peso: FontWeight.w400)),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              if (visibles.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('Aún no hay lanzadores',
                      style: _estilo(12, titulo, peso: FontWeight.w400)),
                )
              else
                for (final l in visibles) _filaEra(l),
              Text('Efectividad (ERA)',
                  style: _estilo(11, sub, peso: FontWeight.w400)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tarjetaBateadores() {
    return _tarjeta(
      color: const Color(0xFFFFE9D6),
      onTap: () => _ir(const EquiposScreen()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.gps_fixed, size: 26, color: Color(0xFFC2410C)),
          const SizedBox(height: 8),
          Text('Bateadores', style: _estilo(15, const Color(0xFF7C2D12))),
          Text('Equipo y rival',
              style: _estilo(11, const Color(0xFF9A3412), peso: FontWeight.w400)),
        ],
      ),
    );
  }

  Widget _barrita(double alto, Color color) {
    return Container(
      width: 8,
      height: alto,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _tarjetaAnalisis() {
    const gris = Color(0xFF94A3B8);
    return _tarjeta(
      color: const Color(0xFFE8EDF5),
      onTap: () => _ir(const AnalisisScreen()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 26,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _barrita(10, gris),
                _barrita(18, _azul),
                _barrita(14, gris),
                _barrita(26, _naranja),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text('Análisis', style: _estilo(15, _tinta)),
          Text('Post-juego',
              style: _estilo(11, const Color(0xFF475569), peso: FontWeight.w400)),
        ],
      ),
    );
  }

  Widget _barraEnvio() {
    final tipos = DatabaseHelper.tiposLanzamientoPredeterminados.length;
    return _tarjeta(
      color: _tinta,
      onTap: () => _ir(const EnviarPantallaScreen()),
      child: Row(
        children: [
          const Icon(Icons.assignment_outlined, size: 26, color: _naranja),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pantalla del coach',
                    style: _estilo(15, Colors.white)),
                Text('$_jugadas jugadas · $tipos tipos',
                    style: _estilo(11, const Color(0xFF94A3B8),
                        peso: FontWeight.w400)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _naranja,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('Enviar', style: _estilo(12, _tinta)),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaBlanca(
      IconData icono, String titulo, String sub, VoidCallback onTap) {
    return _tarjeta(
      color: Colors.white,
      borde: Border.all(color: _bordeClaro, width: 0.5),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 24, color: _tinta),
          const SizedBox(height: 6),
          Text(titulo, style: _estilo(14, _tinta)),
          Text(sub, style: _estilo(11, _grisTexto, peso: FontWeight.w400)),
        ],
      ),
    );
  }

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
            Text(texto, style: _estilo(13, color, peso: FontWeight.w400)),
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
              _itemBarra(Icons.home_outlined, 'Inicio', _barraActivo, null),
              _itemBarra(
                Icons.groups_outlined,
                'Equipo',
                _barraInactivo,
                () => _ir(RosterScreen(
                  equipoId: widget.equipoId,
                  nombreEquipo: widget.nombreEquipo,
                )),
              ),
              _itemBarra(
                Icons.bar_chart,
                'Análisis',
                _barraInactivo,
                () => _ir(const AnalisisScreen()),
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

  @override
  Widget build(BuildContext context) {
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
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              _encabezado(),
              _tarjetaEstado(),
              const SizedBox(height: 10),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _tarjetaLanzadores()),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(child: _tarjetaBateadores()),
                          const SizedBox(height: 10),
                          Expanded(child: _tarjetaAnalisis()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _barraEnvio(),
              const SizedBox(height: 10),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _tarjetaBlanca(
                        Icons.play_circle_outline,
                        'Juego en vivo',
                        'Registra el juego',
                        () => _ir(const JuegoVivoInicioScreen()),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _tarjetaBlanca(
                        Icons.format_list_numbered,
                        'Lineups',
                        'Arma tus alineaciones',
                        () => _ir(const LineupsScreen()),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _barraInferior(),
      ),
    );
  }
}
