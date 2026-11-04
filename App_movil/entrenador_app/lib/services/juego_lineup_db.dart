import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

/// Agrega juego.lanzador_inicial_id y la tabla juego_lineup.
/// Se puede llamar varias veces sin problema.
Future<void> crearTablasLineup(DatabaseExecutor db) async {
  final cols = await db.rawQuery('PRAGMA table_info(juego)');
  final existentes = cols.map((c) => c['name'] as String).toSet();
  if (!existentes.contains('lanzador_inicial_id')) {
    await db.execute('ALTER TABLE juego ADD COLUMN lanzador_inicial_id INTEGER');
  }

  await db.execute('''
    CREATE TABLE IF NOT EXISTS juego_lineup (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      juego_id INTEGER NOT NULL,
      orden INTEGER NOT NULL,
      jugador_id INTEGER NOT NULL,
      posicion TEXT,
      uuid TEXT,
      UNIQUE (juego_id, orden),
      FOREIGN KEY (juego_id) REFERENCES juego (juego_id) ON DELETE CASCADE,
      FOREIGN KEY (jugador_id) REFERENCES jugador (jugador_id)
    )
  ''');
}

extension JuegoLineupDB on DatabaseHelper {
  /// Lineup del juego en orden al bate (vacio si todavia no se arma).
  Future<List<Map<String, dynamic>>> obtenerLineupJuego(int juegoId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT l.orden, l.jugador_id, l.posicion, j.nombre, j.numero
      FROM juego_lineup l
      JOIN jugador j ON j.jugador_id = l.jugador_id
      WHERE l.juego_id = ?
      ORDER BY l.orden
    ''', [juegoId]);
  }

  /// Guarda el lineup (cada item: jugador_id y posicion) y el abridor.
  /// Reemplaza cualquier lineup anterior del mismo juego.
  Future<void> guardarLineupJuego(
    int juegoId,
    List<Map<String, dynamic>> puestos,
    int? abridorId,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
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
        {'lanzador_inicial_id': abridorId},
        where: 'juego_id = ?',
        whereArgs: [juegoId],
      );
    });
  }
}