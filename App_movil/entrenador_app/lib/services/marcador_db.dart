import 'dart:math';

import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

String _nuevoUuidMarcador() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final s = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-'
      '${s.substring(16, 20)}-${s.substring(20)}';
}

/// Crea (si hace falta) las columnas de hits/errores en juego y la tabla
/// juego_entrada. Se puede llamar varias veces sin problema.
Future<void> crearTablasMarcador(DatabaseExecutor db) async {
  final cols = await db.rawQuery('PRAGMA table_info(juego)');
  final existentes = cols.map((c) => c['name'] as String).toSet();
  for (final c in const [
    'hits_propios',
    'errores_propios',
    'hits_rival',
    'errores_rival',
  ]) {
    if (!existentes.contains(c)) {
      await db.execute('ALTER TABLE juego ADD COLUMN $c INTEGER');
    }
  }

  await db.execute('''
    CREATE TABLE IF NOT EXISTS juego_entrada (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      juego_id INTEGER NOT NULL,
      numero INTEGER NOT NULL,
      carreras_propias INTEGER NOT NULL DEFAULT 0,
      carreras_rival INTEGER NOT NULL DEFAULT 0,
      uuid TEXT,
      UNIQUE (juego_id, numero),
      FOREIGN KEY (juego_id) REFERENCES juego (juego_id) ON DELETE CASCADE
    )
  ''');
}

extension MarcadorDB on DatabaseHelper {
  Future<Map<String, dynamic>?> obtenerJuegoMarcador(int juegoId) async {
    final db = await database;
    final r = await db.rawQuery('''
      SELECT j.juego_id, j.fecha, j.equipo_rival_id, j.carreras_propias,
             j.carreras_rival, j.hits_propios, j.errores_propios,
             j.hits_rival, j.errores_rival, q.nombre AS rival_nombre
      FROM juego j
      LEFT JOIN equipo q ON q.equipo_id = j.equipo_rival_id
      WHERE j.juego_id = ?
    ''', [juegoId]);
    return r.isEmpty ? null : r.first;
  }

  Future<List<Map<String, dynamic>>> obtenerEntradasJuego(int juegoId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT numero, carreras_propias, carreras_rival
      FROM juego_entrada
      WHERE juego_id = ?
      ORDER BY numero
    ''', [juegoId]);
  }

  /// Guarda el marcador por entradas. Las carreras totales del juego se
  /// recalculan como la suma de las entradas, asi el record G/P no se descuadra.
  Future<void> guardarMarcadorJuego(
    int juegoId, {
    required int? rivalId,
    required List<int> propias,
    required List<int> rival,
    int? hitsPropios,
    int? erroresPropios,
    int? hitsRival,
    int? erroresRival,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'juego',
        {
          'equipo_rival_id': rivalId,
          'carreras_propias': propias.fold<int>(0, (a, b) => a + b),
          'carreras_rival': rival.fold<int>(0, (a, b) => a + b),
          'hits_propios': hitsPropios,
          'errores_propios': erroresPropios,
          'hits_rival': hitsRival,
          'errores_rival': erroresRival,
        },
        where: 'juego_id = ?',
        whereArgs: [juegoId],
      );
      await txn.delete(
        'juego_entrada',
        where: 'juego_id = ?',
        whereArgs: [juegoId],
      );
      for (var i = 0; i < propias.length; i++) {
        await txn.insert('juego_entrada', {
          'juego_id': juegoId,
          'numero': i + 1,
          'carreras_propias': propias[i],
          'carreras_rival': rival[i],
          'uuid': _nuevoUuidMarcador(),
        });
      }
    });
  }

  /// Borra el desglose por entradas. El juego conserva su marcador final.
  Future<void> quitarEntradasJuego(int juegoId) async {
    final db = await database;
    await db.delete(
      'juego_entrada',
      where: 'juego_id = ?',
      whereArgs: [juegoId],
    );
  }
}