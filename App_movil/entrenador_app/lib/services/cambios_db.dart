import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

/// Agrega juego.lanzador_propio_id y la tabla juego_cambio.
/// Se puede llamar varias veces sin problema.
Future<void> crearTablasCambios(DatabaseExecutor db) async {
  final cols = await db.rawQuery('PRAGMA table_info(juego)');
  final existentes = cols.map((c) => c['name'] as String).toSet();
  if (!existentes.contains('lanzador_propio_id')) {
    await db.execute('ALTER TABLE juego ADD COLUMN lanzador_propio_id INTEGER');
  }
  await db.execute('''
    CREATE TABLE IF NOT EXISTS juego_cambio (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      juego_id INTEGER NOT NULL,
      tipo TEXT NOT NULL,
      orden INTEGER,
      sale_id INTEGER,
      entra_id INTEGER NOT NULL,
      entrada INTEGER NOT NULL,
      mitad TEXT NOT NULL,
      creado_ms INTEGER NOT NULL,
      uuid TEXT,
      FOREIGN KEY (juego_id) REFERENCES juego (juego_id) ON DELETE CASCADE
    )
  ''');
}

/// Valida que el juego siga en curso y que no haya un turno abierto.
/// Devuelve la fila del juego.
Future<Map<String, dynamic>> _validarCambio(
  DatabaseExecutor txn,
  int juegoId,
) async {
  final j = await txn.query(
    'juego',
    columns: [
      'estado',
      'entrada_actual',
      'mitad_actual',
      'lanzador_inicial_id',
      'lanzador_propio_id',
    ],
    where: 'juego_id = ?',
    whereArgs: [juegoId],
    limit: 1,
  );
  if (j.isEmpty) throw StateError('El juego ya no existe.');
  if (j.first['estado'] != 'en_juego') throw StateError('Este juego ya termino.');
  final t = await txn.query(
    'turno_bate',
    columns: ['id'],
    where: 'juego_id = ? AND resultado IS NULL',
    whereArgs: [juegoId],
    limit: 1,
  );
  if (t.isNotEmpty) {
    throw StateError(
      'Hay un turno al bate abierto. Cierralo o deshaz su ultimo lanzamiento antes de hacer un cambio.',
    );
  }
  return j.first;
}

extension CambiosDB on DatabaseHelper {
  /// Lanzador propio vigente (el cambiado, o el abridor si no hubo cambios).
  Future<Map<String, dynamic>?> obtenerLanzadorPropioActual(int juegoId) async {
    final db = await database;
    final r = await db.rawQuery('''
      SELECT p.jugador_id, p.nombre, p.numero
      FROM juego g
      JOIN jugador p
        ON p.jugador_id = COALESCE(g.lanzador_propio_id, g.lanzador_inicial_id)
      WHERE g.juego_id = ?
    ''', [juegoId]);
    return r.isEmpty ? null : r.first;
  }

  /// Lanzadores de tu equipo.
  Future<List<Map<String, dynamic>>> obtenerLanzadoresPropios() async {
    final db = await database;
    return db.rawQuery('''
      SELECT j.jugador_id, j.nombre, j.numero
      FROM jugador j
      JOIN equipo e ON e.equipo_id = j.equipo_id
      WHERE e.tipo = 'propio' AND j.rol = 'lanzador'
      ORDER BY j.nombre COLLATE NOCASE
    ''');
  }

  /// Bateadores de tu equipo que no estan en el lineup del juego.
  Future<List<Map<String, dynamic>>> obtenerBancaBateadores(int juegoId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT j.jugador_id, j.nombre, j.numero
      FROM jugador j
      JOIN equipo e ON e.equipo_id = j.equipo_id
      WHERE e.tipo = 'propio' AND j.rol = 'bateador'
        AND j.jugador_id NOT IN (
          SELECT jugador_id FROM juego_lineup WHERE juego_id = ?
        )
      ORDER BY j.nombre COLLATE NOCASE
    ''', [juegoId]);
  }

  /// Posiciones que juega cada jugador (jugador_posicion).
  Future<Map<int, List<String>>> obtenerPosicionesJugadores() async {
    final db = await database;
    final filas = await db.query('jugador_posicion');
    final m = <int, List<String>>{};
    for (final f in filas) {
      m.putIfAbsent(f['jugador_id'] as int, () => <String>[]).add(f['posicion'] as String);
    }
    return m;
  }

  Future<void> cambiarLanzadorPropio(int juegoId, int nuevoId) async {
    final db = await database;
    await db.transaction((txn) async {
      final j = await _validarCambio(txn, juegoId);
      final actual = (j['lanzador_propio_id'] as int?) ??
          (j['lanzador_inicial_id'] as int?);
      if (actual == nuevoId) {
        throw StateError('Ese lanzador ya esta lanzando.');
      }
      await txn.update(
        'juego',
        {'lanzador_propio_id': nuevoId},
        where: 'juego_id = ?',
        whereArgs: [juegoId],
      );
      await txn.insert('juego_cambio', {
        'juego_id': juegoId,
        'tipo': 'lanzador_propio',
        'sale_id': actual,
        'entra_id': nuevoId,
        'entrada': (j['entrada_actual'] as int?) ?? 1,
        'mitad': (j['mitad_actual'] as String?) ?? 'alta',
        'creado_ms': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  /// El sustituto ocupa el mismo puesto del orden al bate.
  Future<void> sustituirBateadorPropio(
    int juegoId, {
    required int orden,
    required int nuevoId,
    String? posicion,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final j = await _validarCambio(txn, juegoId);
      final actual = await txn.query(
        'juego_lineup',
        where: 'juego_id = ? AND orden = ?',
        whereArgs: [juegoId, orden],
        limit: 1,
      );
      if (actual.isEmpty) throw StateError('Ese puesto no existe en el lineup.');
      final repetido = await txn.query(
        'juego_lineup',
        columns: ['id'],
        where: 'juego_id = ? AND jugador_id = ?',
        whereArgs: [juegoId, nuevoId],
        limit: 1,
      );
      if (repetido.isNotEmpty) throw StateError('Ese jugador ya esta en el lineup.');
      await txn.update(
        'juego_lineup',
        {'jugador_id': nuevoId, 'posicion': posicion},
        where: 'juego_id = ? AND orden = ?',
        whereArgs: [juegoId, orden],
      );
      await txn.insert('juego_cambio', {
        'juego_id': juegoId,
        'tipo': 'bateador_propio',
        'orden': orden,
        'sale_id': actual.first['jugador_id'],
        'entra_id': nuevoId,
        'entrada': (j['entrada_actual'] as int?) ?? 1,
        'mitad': (j['mitad_actual'] as String?) ?? 'alta',
        'creado_ms': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }
}