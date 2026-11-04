import 'package:flutter/material.dart';
import '../models/equipo.dart';
import '../services/database_helper.dart';
import 'marcador_juego_screen.dart';

const Color _colorFondoOscuro = Color(0xFF14171C);
const Color _colorAcento = Color(0xFF0ABDCF);

class RecordJuegosScreen extends StatefulWidget {
  const RecordJuegosScreen({super.key});

  @override
  State<RecordJuegosScreen> createState() => _RecordJuegosScreenState();
}

class _RecordJuegosScreenState extends State<RecordJuegosScreen> {
  List<int> _anios = [];
  int _anio = 0; // 0 = todas las temporadas
  Map<String, int> _record = {'g': 0, 'p': 0, 'e': 0};
  List<Map<String, dynamic>> _juegos = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar(primera: true);
  }

  Future<void> _cargar({bool primera = false}) async {
    final anios = await DatabaseHelper.instance.obtenerAniosJuegos();
    if (primera || (_anio != 0 && !anios.contains(_anio))) {
      _anio = anios.isNotEmpty ? anios.first : 0;
    }
    final filtro = _anio == 0 ? null : _anio;
    final record = await DatabaseHelper.instance.recordEquipo(anio: filtro);
    final juegos = await DatabaseHelper.instance.obtenerJuegosEquipo(anio: filtro);
    if (!mounted) return;
    setState(() {
      _anios = anios;
      _record = record;
      _juegos = juegos;
      _cargando = false;
    });
  }

  String _fechaVista(String iso) {
    final p = iso.split('-');
    if (p.length != 3) return iso;
    return '${p[2]}/${p[1]}/${p[0]}';
  }

  String _porcentaje() {
    final g = _record['g']!;
    final p = _record['p']!;
    if (g + p == 0) return '--';
    final s = (g / (g + p)).toStringAsFixed(3);
    return s.startsWith('0') ? s.substring(1) : s;
  }

  Future<void> _editar(Map<String, dynamic> j) async {
    final rivales = await DatabaseHelper.instance.obtenerEquiposRivales();
    if (!mounted) return;
    final r = await showDialog<_ResultadoEditado>(
      context: context,
      builder: (ctx) => _EditarResultadoDialog(
        titulo: 'Juego del ${_fechaVista(j['fecha'] as String)}',
        rivales: rivales,
        rivalId: j['equipo_rival_id'] as int?,
        propias: j['carreras_propias'] as int?,
        rival: j['carreras_rival'] as int?,
      ),
    );
    if (r == null) return;
    await DatabaseHelper.instance.actualizarResultadoJuego(
      j['juego_id'] as int,
      rivalId: r.rivalId,
      propias: r.propias,
      rival: r.rival,
    );
    await _cargar();
  }

  Future<void> _abrirMarcador(Map<String, dynamic> j) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MarcadorJuegoScreen(juegoId: j['juego_id'] as int),
      ),
    );
    await _cargar();
  }

  Widget _tarjetaRecord() {
    final g = _record['g']!;
    final p = _record['p']!;
    final e = _record['e']!;
    final sinResultado = _juegos
        .where((j) => j['carreras_propias'] == null || j['carreras_rival'] == null)
        .length;

    return Card(
      color: _colorFondoOscuro,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('RECORD DEL EQUIPO', style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1)),
            const SizedBox(height: 8),
            Text(
              e > 0 ? '$g - $p - $e' : '$g - $p',
              style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Porcentaje de victorias: ${_porcentaje()}',
              style: const TextStyle(color: _colorAcento, fontWeight: FontWeight.w600),
            ),
            if (sinResultado > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '$sinResultado juego(s) sin resultado (no cuentan)',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _selectorAnio() {
    return Row(
      children: [
        const Text('Temporada', style: TextStyle(color: Colors.black54, fontSize: 12)),
        const SizedBox(width: 12),
        DropdownButton<int>(
          value: _anio,
          underline: const SizedBox.shrink(),
          style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
          items: [
            const DropdownMenuItem(value: 0, child: Text('Todas')),
            for (final a in _anios) DropdownMenuItem(value: a, child: Text(a.toString())),
          ],
          onChanged: (v) async {
            if (v == null) return;
            setState(() => _anio = v);
            await _cargar();
          },
        ),
      ],
    );
  }

  Widget _filaJuego(Map<String, dynamic> j) {
    final cp = j['carreras_propias'] as int?;
    final cr = j['carreras_rival'] as int?;
    final rival = j['rival_nombre'] as String?;

    String letra = '-';
    Color color = Colors.orange.shade700;
    if (cp != null && cr != null) {
      if (cp > cr) {
        letra = 'G';
        color = Colors.green.shade700;
      } else if (cp < cr) {
        letra = 'P';
        color = Colors.red.shade700;
      } else {
        letra = 'E';
        color = Colors.grey.shade600;
      }
    }

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color,
          foregroundColor: Colors.white,
          child: Text(letra, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        title: Text(
          '${_fechaVista(j['fecha'] as String)}   ${rival == null ? 'Sin rival' : 'vs $rival'}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          cp != null && cr != null ? 'Marcador: $cp - $cr' : 'Sin resultado. Toca para completarlo.',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.scoreboard_outlined, color: _colorAcento),
          tooltip: 'Marcador por entradas',
          onPressed: () => _abrirMarcador(j),
        ),
        onTap: () {
          if (((j['num_entradas'] as int?) ?? 0) > 0) {
            _abrirMarcador(j);
          } else {
            _editar(j);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      appBar: AppBar(
        backgroundColor: _colorFondoOscuro,
        foregroundColor: Colors.white,
        title: const Text('RECORD Y JUEGOS'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _tarjetaRecord(),
                const SizedBox(height: 8),
                _selectorAnio(),
                const SizedBox(height: 4),
                if (_juegos.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'Sin juegos registrados todavia.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                  )
                else
                  for (final j in _juegos) _filaJuego(j),
              ],
            ),
    );
  }
}

class _ResultadoEditado {
  final int? rivalId;
  final int? propias;
  final int? rival;

  const _ResultadoEditado({this.rivalId, this.propias, this.rival});
}

class _EditarResultadoDialog extends StatefulWidget {
  final String titulo;
  final List<Equipo> rivales;
  final int? rivalId;
  final int? propias;
  final int? rival;

  const _EditarResultadoDialog({
    required this.titulo,
    required this.rivales,
    required this.rivalId,
    required this.propias,
    required this.rival,
  });

  @override
  State<_EditarResultadoDialog> createState() => _EditarResultadoDialogState();
}

class _EditarResultadoDialogState extends State<_EditarResultadoDialog> {
  late int? _rivalId = widget.rivales.any((e) => e.equipoId == widget.rivalId)
      ? widget.rivalId
      : null;
  late final TextEditingController _propias =
      TextEditingController(text: widget.propias?.toString() ?? '');
  late final TextEditingController _rival =
      TextEditingController(text: widget.rival?.toString() ?? '');
  String? _error;

  @override
  void dispose() {
    _propias.dispose();
    _rival.dispose();
    super.dispose();
  }

  void _guardar() {
    final a = _propias.text.trim();
    final b = _rival.text.trim();
    int? x;
    int? y;
    if (a.isNotEmpty || b.isNotEmpty) {
      if (a.isEmpty || b.isEmpty) {
        setState(() => _error = 'Completa las carreras de ambos equipos o deja las dos vacias.');
        return;
      }
      x = int.tryParse(a);
      y = int.tryParse(b);
      if (x == null || y == null || x < 0 || y < 0) {
        setState(() => _error = 'El marcador debe tener enteros mayores o iguales a 0.');
        return;
      }
    }
    Navigator.pop(context, _ResultadoEditado(rivalId: _rivalId, propias: x, rival: y));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButton<int?>(
              isExpanded: true,
              value: _rivalId,
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Sin rival')),
                for (final e in widget.rivales)
                  DropdownMenuItem<int?>(value: e.equipoId, child: Text(e.nombre)),
              ],
              onChanged: (v) => setState(() => _rivalId = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _propias,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Carreras propias',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _rival,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Carreras del rival',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
        TextButton(onPressed: _guardar, child: const Text('GUARDAR')),
      ],
    );
  }
}
