import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

/// Agrega juego.lanzador_rival_id. Se puede llamar varias veces.
Future<void> crearColumnaLanzadorRival(DatabaseExecutor db) async {
  final cols = await db.rawQuery('PRAGMA table_info(juego)');
  final existentes = cols.map((c) => c['name'] as String).toSet();
  if (!existentes.contains('lanzador_rival_id')) {
    await db.execute('ALTER TABLE juego ADD COLUMN lanzador_rival_id INTEGER');
  }
}

Future<int> _rivalDelJuego(DatabaseExecutor txn, int juegoId) async {
  final r = await txn.query(
    'juego',
    columns: ['estado', 'equipo_rival_id'],
    where: 'juego_id = ?',
    whereArgs: [juegoId],
    limit: 1,
  );
  if (r.isEmpty) throw StateError('El juego ya no existe.');
  if (r.first['estado'] != 'en_juego') throw StateError('Este juego ya termino.');
  final rivalId = r.first['equipo_rival_id'] as int?;
  if (rivalId == null) {
    throw StateError(
      'Este juego no tiene rival. Asignalo en Record y juegos para identificar a su lanzador.',
    );
  }
  return rivalId;
}

extension LanzadorRivalDB on DatabaseHelper {
  /// Lanzador rival vigente del juego, o null si todavia no se identifica.
  Future<Map<String, dynamic>?> obtenerLanzadorRivalActual(int juegoId) async {
    final db = await database;
    final r = await db.rawQuery('''
      SELECT j.jugador_id, j.nombre, j.numero
      FROM juego g
      JOIN jugador j ON j.jugador_id = g.lanzador_rival_id
      WHERE g.juego_id = ?
    ''', [juegoId]);
    return r.isEmpty ? null : r.first;
  }

  /// Lanzadores ya registrados en el equipo rival del juego.
  Future<List<Map<String, dynamic>>> obtenerLanzadoresRival(int juegoId) async {
    final db = await database;
    final rivalId = await _rivalDelJuego(db, juegoId);
    return db.query(
      'jugador',
      columns: ['jugador_id', 'nombre', 'numero'],
      where: "equipo_id = ? AND rol = 'lanzador'",
      whereArgs: [rivalId],
      orderBy: 'nombre COLLATE NOCASE',
    );
  }

  Future<void> fijarLanzadorRival(int juegoId, int jugadorId) async {
    final db = await database;
    await db.transaction((txn) async {
      await _rivalDelJuego(txn, juegoId);
      await txn.update(
        'juego',
        {'lanzador_rival_id': jugadorId},
        where: 'juego_id = ?',
        whereArgs: [juegoId],
      );
    });
  }

  /// Crea un lanzador del equipo rival con sus tipos de pitcheo y lo deja
  /// como lanzador vigente del juego.
  Future<int> crearLanzadorRival(
    int juegoId, {
    required String nombre,
    int? numero,
    String? mano,
    List<int> tipos = const [],
  }) async {
    final db = await database;
    return db.transaction<int>((txn) async {
      final rivalId = await _rivalDelJuego(txn, juegoId);
      final id = await txn.insert('jugador', {
        'equipo_id': rivalId,
        'nombre': nombre,
        'rol': 'lanzador',
        'mano_lanzamiento': mano,
        'numero': numero,
      });
      for (final t in tipos) {
        await txn.insert('lanzador_tipo_picheo', {
          'lanzador_id': id,
          'tipo_lanzamiento_id': t,
        });
      }
      await txn.update(
        'juego',
        {'lanzador_rival_id': id},
        where: 'juego_id = ?',
        whereArgs: [juegoId],
      );
      return id;
    });
  }
}