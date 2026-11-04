import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

/// Tablas de lineups guardados. Se puede llamar varias veces sin problema.
Future<void> crearTablasLineupsGuardados(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS lineup (
      lineup_id INTEGER PRIMARY KEY AUTOINCREMENT,
      nombre TEXT NOT NULL,
      uuid TEXT,
      lanzador_id INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS lineup_puesto (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      lineup_id INTEGER NOT NULL,
      orden INTEGER NOT NULL,
      jugador_id INTEGER NOT NULL,
      posicion TEXT,
      uuid TEXT,
      UNIQUE (lineup_id, orden),
      FOREIGN KEY (lineup_id) REFERENCES lineup (lineup_id) ON DELETE CASCADE,
      FOREIGN KEY (jugador_id) REFERENCES jugador (jugador_id) ON DELETE CASCADE
    )
  ''');
  final cols = await db.rawQuery('PRAGMA table_info(lineup)');
  final existentes = cols.map((c) => c['name'] as String).toSet();
  if (!existentes.contains('lanzador_id')) {
    await db.execute('ALTER TABLE lineup ADD COLUMN lanzador_id INTEGER');
  }
}

extension LineupsDB on DatabaseHelper {
  /// Lineups guardados con la cantidad de puestos y el lanzador de cada uno.
  Future<List<Map<String, dynamic>>> obtenerLineups() async {
    final db = await database;
    return db.rawQuery('''
      SELECT l.lineup_id, l.nombre, l.lanzador_id,
             (SELECT j.nombre FROM jugador j
              WHERE j.jugador_id = l.lanzador_id) AS lanzador,
             (SELECT COUNT(*) FROM lineup_puesto p
              WHERE p.lineup_id = l.lineup_id) AS puestos
      FROM lineup l
      ORDER BY l.nombre COLLATE NOCASE
    ''');
  }

  Future<Map<String, dynamic>?> obtenerLineup(int lineupId) async {
    final db = await database;
    final r = await db.query(
      'lineup',
      where: 'lineup_id = ?',
      whereArgs: [lineupId],
      limit: 1,
    );
    return r.isEmpty ? null : r.first;
  }

  Future<List<Map<String, dynamic>>> obtenerPuestosLineup(int lineupId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT p.orden, p.jugador_id, p.posicion, j.nombre, j.numero
      FROM lineup_puesto p
      JOIN jugador j ON j.jugador_id = p.jugador_id
      WHERE p.lineup_id = ?
      ORDER BY p.orden
    ''', [lineupId]);
  }

  /// Crea (lineupId null) o actualiza un lineup. Cada puesto trae
  /// jugador_id y posicion. Devuelve el id del lineup.
  Future<int> guardarLineup({
    int? lineupId,
    required String nombre,
    required int? lanzadorId,
    required List<Map<String, dynamic>> puestos,
  }) async {
    final db = await database;
    return db.transaction<int>((txn) async {
      int id;
      if (lineupId == null) {
        id = await txn.insert('lineup', {
          'nombre': nombre,
          'lanzador_id': lanzadorId,
        });
      } else {
        id = lineupId;
        await txn.update(
          'lineup',
          {'nombre': nombre, 'lanzador_id': lanzadorId},
          where: 'lineup_id = ?',
          whereArgs: [id],
        );
        await txn.delete('lineup_puesto', where: 'lineup_id = ?', whereArgs: [id]);
      }
      for (var i = 0; i < puestos.length; i++) {
        await txn.insert('lineup_puesto', {
          'lineup_id': id,
          'orden': i + 1,
          'jugador_id': puestos[i]['jugador_id'],
          'posicion': puestos[i]['posicion'],
        });
      }
      return id;
    });
  }

  Future<void> eliminarLineup(int lineupId) async {
    final db = await database;
    await db.delete('lineup', where: 'lineup_id = ?', whereArgs: [lineupId]);
  }

  /// Copia un lineup guardado al juego. El lanzador del lineup pasa a ser
  /// el abridor. Reemplaza cualquier lineup anterior del juego.
  Future<void> copiarLineupAJuego(int juegoId, int lineupId) async {
    final db = await database;
    await db.transaction((txn) async {
      final info = await txn.query(
        'lineup',
        where: 'lineup_id = ?',
        whereArgs: [lineupId],
        limit: 1,
      );
      if (info.isEmpty) throw StateError('El lineup elegido ya no existe.');
      final lanzadorId = info.first['lanzador_id'] as int?;
      if (lanzadorId == null) {
        throw StateError('El lineup no tiene lanzador. Editalo en Lineups.');
      }
      final puestos = await txn.query(
        'lineup_puesto',
        where: 'lineup_id = ?',
        whereArgs: [lineupId],
        orderBy: 'orden',
      );
      if (puestos.length < 9) {
        throw StateError('El lineup tiene menos de 9 puestos. Editalo en Lineups.');
      }
      await txn.delete('juego_lineup', where: 'juego_id = ?', whereArgs: [juegoId]);
      for (var i = 0; i < puestos.length; i++) {
        await txn.insert('juego_lineup', {
          'juego_id': juegoId,
          'orden': i + 1,
          'jugador_id': puestos[i]['jugador_id'],
          'posicion': puestos[i]['posicion'],
        });
      }
      await txn.update(
        'juego',
        {'lanzador_inicial_id': lanzadorId},
        where: 'juego_id = ?',
        whereArgs: [juegoId],
      );
    });
  }
}