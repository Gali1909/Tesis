# Fase 3 - Marcador por entradas
# Ejecutar desde la raiz del proyecto (C:\Tesis\App_movil\entrenador_app)

$dbFile     = "lib\services\database_helper.dart"
$recordFile = "lib\screens\record_juegos_screen.dart"
$marcadorFile = "lib\screens\marcador_juego_screen.dart"

function Reemplazar($texto, $viejo, $nuevo) {
  $i = $texto.IndexOf($viejo)
  if ($i -lt 0 -or $i -ne $texto.LastIndexOf($viejo)) { throw "No se encontro exactamente una vez: $viejo" }
  return $texto.Substring(0, $i) + $nuevo + $texto.Substring($i + $viejo.Length)
}

function Leer($ruta) {
  return (Get-Content $ruta -Raw -Encoding UTF8) -replace "`r`n", "`n"
}

# ---------- Pantalla del marcador ----------
$codigoMarcador = @'
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/equipo.dart';
import '../services/database_helper.dart';

const Color _colorFondoOscuro = Color(0xFF14171C);
const Color _colorAcento = Color(0xFF0ABDCF);
const Color _colorNaranja = Color(0xFFE36F10);

class MarcadorJuegoScreen extends StatefulWidget {
  /// Fila del juego tal como la entrega obtenerJuegosEquipo.
  final Map<String, dynamic> juego;

  const MarcadorJuegoScreen({super.key, required this.juego});

  @override
  State<MarcadorJuegoScreen> createState() => _MarcadorJuegoScreenState();
}

class _MarcadorJuegoScreenState extends State<MarcadorJuegoScreen> {
  static const int _entradasBase = 9;
  static const int _entradasMax = 20;

  final List<TextEditingController> _entradasPropias = [];
  final List<TextEditingController> _entradasRival = [];
  final TextEditingController _hitsPropios = TextEditingController();
  final TextEditingController _hitsRival = TextEditingController();
  final TextEditingController _erroresPropios = TextEditingController();
  final TextEditingController _erroresRival = TextEditingController();

  List<Equipo> _rivales = [];
  int? _rivalId;
  bool _cargando = true;
  bool _guardando = false;
  bool _tieneEntradas = false;
  String? _error;

  int get _juegoId => widget.juego['juego_id'] as int;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final c in [..._entradasPropias, ..._entradasRival]) {
      c.dispose();
    }
    _hitsPropios.dispose();
    _hitsRival.dispose();
    _erroresPropios.dispose();
    _erroresRival.dispose();
    super.dispose();
  }

  void _agregarControladores() {
    _entradasPropias.add(TextEditingController());
    _entradasRival.add(TextEditingController());
  }

  Future<void> _cargar() async {
    final db = DatabaseHelper.instance;
    final rivales = await db.obtenerEquiposRivales();
    final entradas = await db.entradasJuego(_juegoId);
    final he = await db.hitsErroresJuego(_juegoId);

    var total = _entradasBase;
    for (final e in entradas) {
      final n = e['entrada'] as int;
      if (n > total) total = n;
    }
    for (var i = 0; i < total; i++) {
      _agregarControladores();
    }
    for (final e in entradas) {
      final i = (e['entrada'] as int) - 1;
      _entradasPropias[i].text = e['carreras_propias']?.toString() ?? '';
      _entradasRival[i].text = e['carreras_rival']?.toString() ?? '';
    }
    _hitsPropios.text = he['hits_propios']?.toString() ?? '';
    _hitsRival.text = he['hits_rival']?.toString() ?? '';
    _erroresPropios.text = he['errores_propios']?.toString() ?? '';
    _erroresRival.text = he['errores_rival']?.toString() ?? '';

    final rid = widget.juego['equipo_rival_id'] as int?;
    if (!mounted) return;
    setState(() {
      _rivales = rivales;
      _rivalId = rivales.any((e) => e.equipoId == rid) ? rid : null;
      _tieneEntradas = entradas.isNotEmpty;
      _cargando = false;
    });
  }

  String _fechaVista(String iso) {
    final p = iso.split('-');
    if (p.length != 3) return iso;
    return '${p[2]}/${p[1]}/${p[0]}';
  }

  String _nombreRival() {
    for (final e in _rivales) {
      if (e.equipoId == _rivalId) return e.nombre;
    }
    return 'Rival';
  }

  int? _numero(TextEditingController c) => int.tryParse(c.text.trim());

  int _suma(List<TextEditingController> cs) =>
      cs.fold(0, (total, c) => total + (_numero(c) ?? 0));

  void _agregarEntrada() {
    if (_entradasPropias.length >= _entradasMax) return;
    setState(_agregarControladores);
  }

  void _quitarEntrada() {
    if (_entradasPropias.length <= 1) return;
    final ultimaP = _entradasPropias.last;
    final ultimaR = _entradasRival.last;
    if (ultimaP.text.trim().isNotEmpty || ultimaR.text.trim().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La ultima entrada tiene datos. Borralos primero.')),
      );
      return;
    }
    setState(() {
      _entradasPropias.removeLast().dispose();
      _entradasRival.removeLast().dispose();
    });
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await DatabaseHelper.instance.guardarMarcadorJuego(
        juegoId: _juegoId,
        rivalId: _rivalId,
        propias: _entradasPropias.map(_numero).toList(),
        rival: _entradasRival.map(_numero).toList(),
        hitsPropios: _numero(_hitsPropios),
        hitsRival: _numero(_hitsRival),
        erroresPropios: _numero(_erroresPropios),
        erroresRival: _numero(_erroresRival),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo guardar: $e';
        _guardando = false;
      });
    }
  }

  Widget _celda(TextEditingController c, {Color? borde}) {
    final colorBorde = borde ?? Colors.black26;
    return SizedBox(
      width: 44,
      height: 40,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: TextField(
          controller: c,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(2),
          ],
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.zero,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: colorBorde),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: _colorAcento, width: 2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _titulo(String texto) {
    return SizedBox(
      width: 44,
      height: 28,
      child: Center(
        child: Text(
          texto,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
        ),
      ),
    );
  }

  Widget _total(int valor) {
    return SizedBox(
      width: 44,
      height: 40,
      child: Center(
        child: Text(
          '$valor',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _colorNaranja),
        ),
      ),
    );
  }

  Widget _filaEquipo(
    String nombre,
    List<TextEditingController> entradas,
    TextEditingController hits,
    TextEditingController errores,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            nombre,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        for (final c in entradas) _celda(c),
        _total(_suma(entradas)),
        _celda(hits, borde: _colorAcento),
        _celda(errores, borde: _colorAcento),
      ],
    );
  }

  Widget _tarjetaJuego() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Juego del ${_fechaVista(widget.juego['fecha'] as String)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            DropdownButton<int?>(
              isExpanded: true,
              value: _rivalId,
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Sin rival')),
                for (final e in _rivales)
                  DropdownMenuItem<int?>(value: e.equipoId, child: Text(e.nombre)),
              ],
              onChanged: (v) => setState(() => _rivalId = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaLinescore() {
    final n = _entradasPropias.length;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _colorAcento, width: 1.5),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: 92),
                for (var i = 1; i <= n; i++) _titulo('$i'),
                _titulo('R'),
                _titulo('H'),
                _titulo('E'),
              ],
            ),
            _filaEquipo('Mi equipo', _entradasPropias, _hitsPropios, _erroresPropios),
            _filaEquipo(_nombreRival(), _entradasRival, _hitsRival, _erroresRival),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cp = widget.juego['carreras_propias'] as int?;
    final cr = widget.juego['carreras_rival'] as int?;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      appBar: AppBar(
        backgroundColor: _colorFondoOscuro,
        foregroundColor: Colors.white,
        title: const Text('MARCADOR'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _tarjetaJuego(),
                const SizedBox(height: 12),
                _tarjetaLinescore(),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _agregarEntrada,
                      icon: const Icon(Icons.add),
                      label: const Text('Entrada'),
                    ),
                    TextButton.icon(
                      onPressed: _quitarEntrada,
                      icon: const Icon(Icons.remove),
                      label: const Text('Entrada'),
                    ),
                  ],
                ),
                if (!_tieneEntradas && cp != null && cr != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Este juego tiene marcador final $cp - $cr sin entradas. '
                      'Si cargas las entradas, el marcador final sera su suma.',
                      style: const TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ),
                ElevatedButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: const Icon(Icons.save),
                  label: const Text('GUARDAR MARCADOR'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _colorFondoOscuro,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ),
    );
  }
}
'@

# ---------- Metodos y migracion de la base de datos ----------
$metodosDb = @'
  /// Fase 3: marcador por entradas. juego_entrada guarda las carreras de cada
  /// entrada; hits y errores van como columnas opcionales de juego.
  Future<void> _prepararMarcador(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS juego_entrada (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        juego_id INTEGER NOT NULL,
        entrada INTEGER NOT NULL,
        carreras_propias INTEGER,
        carreras_rival INTEGER,
        FOREIGN KEY (juego_id) REFERENCES juego (juego_id) ON DELETE CASCADE,
        UNIQUE (juego_id, entrada)
      )
    ''');
    final columnas = await db.rawQuery('PRAGMA table_info(juego)');
    for (final c in [
      'hits_propios',
      'hits_rival',
      'errores_propios',
      'errores_rival',
    ]) {
      if (!columnas.any((x) => x['name'] == c)) {
        await db.execute('ALTER TABLE juego ADD COLUMN $c INTEGER');
      }
    }
  }

  Future<List<Map<String, dynamic>>> entradasJuego(int juegoId) async {
    final db = await database;
    return db.query(
      'juego_entrada',
      where: 'juego_id = ?',
      whereArgs: [juegoId],
      orderBy: 'entrada ASC',
    );
  }

  Future<bool> juegoTieneEntradas(int juegoId) async {
    final db = await database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM juego_entrada WHERE juego_id = ?',
      [juegoId],
    );
    return ((r.first['n'] as int?) ?? 0) > 0;
  }

  Future<Map<String, dynamic>> hitsErroresJuego(int juegoId) async {
    final db = await database;
    final r = await db.query(
      'juego',
      columns: ['hits_propios', 'hits_rival', 'errores_propios', 'errores_rival'],
      where: 'juego_id = ?',
      whereArgs: [juegoId],
    );
    return r.isEmpty ? <String, dynamic>{} : r.first;
  }

  /// Guarda el marcador por entradas. Si hay al menos una entrada con datos,
  /// las carreras totales del juego pasan a ser la suma de las entradas.
  Future<void> guardarMarcadorJuego({
    required int juegoId,
    required int? rivalId,
    required List<int?> propias,
    required List<int?> rival,
    int? hitsPropios,
    int? hitsRival,
    int? erroresPropios,
    int? erroresRival,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('juego_entrada', where: 'juego_id = ?', whereArgs: [juegoId]);
      var hayEntradas = false;
      var sumaPropias = 0;
      var sumaRival = 0;
      for (var i = 0; i < propias.length; i++) {
        final p = propias[i];
        final r = rival[i];
        if (p == null && r == null) continue;
        hayEntradas = true;
        sumaPropias += p ?? 0;
        sumaRival += r ?? 0;
        await txn.insert('juego_entrada', {
          'juego_id': juegoId,
          'entrada': i + 1,
          'carreras_propias': p,
          'carreras_rival': r,
        });
      }
      final cambios = <String, Object?>{
        'equipo_rival_id': rivalId,
        'hits_propios': hitsPropios,
        'hits_rival': hitsRival,
        'errores_propios': erroresPropios,
        'errores_rival': erroresRival,
      };
      if (hayEntradas) {
        cambios['carreras_propias'] = sumaPropias;
        cambios['carreras_rival'] = sumaRival;
      }
      await txn.update('juego', cambios, where: 'juego_id = ?', whereArgs: [juegoId]);
    });
  }

'@

# ---------- Cambios en Record y juegos ----------
$metodoRecord = @'
Future<void> _abrirMarcador(Map<String, dynamic> j) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => MarcadorJuegoScreen(juego: j)),
    );
    if (ok == true) await _cargar();
  }

  Future<void> _editar(Map<String, dynamic> j) async {
    // Los juegos con entradas se editan en el marcador para no descuadrar las carreras.
    if (await DatabaseHelper.instance.juegoTieneEntradas(j['juego_id'] as int)) {
      await _abrirMarcador(j);
      return;
    }
'@

$trailingNuevo = @'
trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Marcador por entradas',
              icon: const Icon(Icons.table_chart_outlined, color: _colorAcento),
              onPressed: () => _abrirMarcador(j),
            ),
            const Icon(Icons.edit, color: _colorAcento),
          ],
        ),
'@

try {
  if (Test-Path $marcadorFile) { throw "Este paso ya se aplico. No se modifico nada." }

  $d = Leer $dbFile
  $r = Leer $recordFile

  # Base de datos
  $d = Reemplazar $d "await _migrarEquipoOpcional(db);" "await _migrarEquipoOpcional(db);`n    await _prepararMarcador(db);"
  $ancla = "  /// Historial de pertenencia de jugadores a equipos (fase 1.4)."
  $d = Reemplazar $d $ancla (($metodosDb -replace "`r`n", "`n") + $ancla)

  # Record y juegos
  $r = Reemplazar $r "import '../services/database_helper.dart';" "import '../services/database_helper.dart';`nimport 'marcador_juego_screen.dart';"
  $r = Reemplazar $r "Future<void> _editar(Map<String, dynamic> j) async {" (($metodoRecord -replace "`r`n", "`n").TrimEnd("`n"))
  $r = Reemplazar $r "trailing: const Icon(Icons.edit, color: _colorAcento)," (($trailingNuevo -replace "`r`n", "`n").TrimEnd("`n"))

  Copy-Item $dbFile "$dbFile.bak_fase3" -Force
  Copy-Item $recordFile "$recordFile.bak_fase3" -Force
  Set-Content -Path $dbFile -Value ($d -replace "`n", "`r`n") -Encoding UTF8 -NoNewline
  Set-Content -Path $recordFile -Value ($r -replace "`n", "`r`n") -Encoding UTF8 -NoNewline
  Set-Content -Path $marcadorFile -Value (($codigoMarcador -replace "`r`n", "`n") -replace "`n", "`r`n") -Encoding UTF8
  Write-Host "OK: Fase 3 - marcador por entradas aplicado" -ForegroundColor Green
}
catch {
  Write-Host "ERROR, no se modifico nada: $_" -ForegroundColor Red
}

flutter analyze
