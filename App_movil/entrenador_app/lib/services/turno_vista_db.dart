import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

/// Agrega la zona (x, y) del lanzamiento. Se puede llamar varias veces.
Future<void> crearColumnasZona(DatabaseExecutor db) async {
  final cols = await db.rawQuery('PRAGMA table_info(lanzamiento)');
  final existentes = cols.map((c) => c['name'] as String).toSet();
  for (final c in const ['zona_x', 'zona_y']) {
    if (!existentes.contains(c)) {
      await db.execute('ALTER TABLE lanzamiento ADD COLUMN $c REAL');
    }
  }
}

int _n(Object? v) => (v as num?)?.toInt() ?? 0;

extension TurnoVistaDB on DatabaseHelper {
  Future<List<Map<String, dynamic>>> obtenerLanzamientosTurnoZona(
    int turnoId,
  ) async {
    final db = await database;
    return db.rawQuery('''
      SELECT l.numero, l.resultado, l.zona_x, l.zona_y, t.nombre AS tipo
      FROM lanzamiento l
      LEFT JOIN tipo_lanzamiento t
        ON t.tipo_lanzamiento_id = l.tipo_lanzamiento_id
      WHERE l.turno_id = ?
      ORDER BY l.numero
    ''', [turnoId]);
  }

  /// Datos para el marcador (H y E por equipo), la tarjeta del bateador y
  /// la tarjeta del lanzador.
  Future<Map<String, dynamic>> obtenerVistaTurno(
    int juegoId, {
    int? bateadorId,
    int? lanzadorId,
  }) async {
    final db = await database;
    final vista = <String, dynamic>{
      'h_propio': 0,
      'h_rival': 0,
      'e_propio': 0,
      'e_rival': 0,
    };

    final eq = await db.rawQuery('''
      SELECT propio,
        SUM(CASE WHEN resultado IN ('sencillo','doble','triple','home_run')
                 THEN 1 ELSE 0 END) AS h,
        SUM(CASE WHEN resultado = 'error' THEN 1 ELSE 0 END) AS e
      FROM turno_bate
      WHERE juego_id = ? AND resultado IS NOT NULL
      GROUP BY propio
    ''', [juegoId]);
    for (final f in eq) {
      final propio = _n(f['propio']) == 1;
      vista[propio ? 'h_propio' : 'h_rival'] = _n(f['h']);
      // El error se le carga al equipo que defiende.
      vista[propio ? 'e_rival' : 'e_propio'] = _n(f['e']);
    }

    if (bateadorId != null) {
      final p = await db.query(
        'jugador',
        columns: ['mano_bateo'],
        where: 'jugador_id = ?',
        whereArgs: [bateadorId],
        limit: 1,
      );
      final hist = await db.rawQuery('''
        SELECT COALESCE(SUM(hits_juego), 0) AS h,
               COALESCE(SUM(turnos_al_bate), 0) AS ab
        FROM estadistica_juego_bateador
        WHERE bateador_id = ?
      ''', [bateadorId]);
      final hoy = await db.rawQuery('''
        SELECT
          SUM(CASE WHEN resultado NOT IN ('boleto','golpeado') THEN 1 ELSE 0 END) AS ab,
          SUM(CASE WHEN resultado IN ('sencillo','doble','triple','home_run')
                   THEN 1 ELSE 0 END) AS h
        FROM turno_bate
        WHERE juego_id = ? AND bateador_id = ? AND resultado IS NOT NULL
      ''', [juegoId, bateadorId]);
      vista['bateador'] = {
        'mano': p.isEmpty ? null : p.first['mano_bateo'],
        'h': _n(hist.first['h']),
        'ab': _n(hist.first['ab']),
        'hoy_h': _n(hoy.first['h']),
        'hoy_ab': _n(hoy.first['ab']),
      };
    }

    if (lanzadorId != null) {
      final p = await db.query(
        'jugador',
        columns: ['nombre', 'numero'],
        where: 'jugador_id = ?',
        whereArgs: [lanzadorId],
        limit: 1,
      );
      final pit = await db.rawQuery('''
        SELECT COUNT(*) AS n
        FROM lanzamiento l
        JOIN turno_bate t ON t.id = l.turno_id
        WHERE t.juego_id = ? AND t.lanzador_id = ?
      ''', [juegoId, lanzadorId]);
      final outsT = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN resultado IN
                 ('ponche','out_roletazo','out_elevado','out_linea')
                 THEN 1 ELSE 0 END), 0)
               + COALESCE(SUM(outs_corredores), 0) AS o
        FROM turno_bate
        WHERE juego_id = ? AND lanzador_id = ? AND resultado IS NOT NULL
      ''', [juegoId, lanzadorId]);
      final outsJ = await db.rawQuery(
        'SELECT COALESCE(SUM(outs), 0) AS o FROM jugada_corredor '
        'WHERE juego_id = ? AND lanzador_id = ?',
        [juegoId, lanzadorId],
      );
      final er1 = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM turno_carrera '
        'WHERE juego_id = ? AND lanzador_id = ? AND limpia = 1',
        [juegoId, lanzadorId],
      );
      final er2 = await db.rawQuery(
        "SELECT COUNT(*) AS n FROM jugada_mov "
        "WHERE juego_id = ? AND lanzador_id = ? AND destino = 'anota' AND limpia = 1",
        [juegoId, lanzadorId],
      );
      vista['lanzador'] = {
        'nombre': p.isEmpty ? '?' : p.first['nombre'],
        'numero': p.isEmpty ? null : p.first['numero'],
        'pitches': _n(pit.first['n']),
        'outs': _n(outsT.first['o']) + _n(outsJ.first['o']),
        'er': _n(er1.first['n']) + _n(er2.first['n']),
      };
    }
    return vista;
  }
}