import 'package:sqflite/sqflite.dart';

const String _sqlHits = "('sencillo','doble','triple','home_run')";
const String _sqlOuts = "('ponche','out_roletazo','out_elevado','out_linea')";

int _n(Object? v) => (v as num?)?.toInt() ?? 0;

/// Escribe las estadisticas del juego a partir de sus turnos cerrados, de
/// las carreras registradas y de las jugadas de corredores. Borra antes lo
/// que este juego haya generado, asi que se puede repetir sin duplicar.
Future<void> escribirEstadisticasJuego(DatabaseExecutor txn, int juegoId) async {
  await txn.delete(
    'estadistica_juego_bateador',
    where: 'juego_id = ?',
    whereArgs: [juegoId],
  );
  await txn.delete(
    'estadistica_juego_lanzador',
    where: 'juego_id = ?',
    whereArgs: [juegoId],
  );

  final bateadores = await txn.rawQuery('''
    SELECT t.bateador_id,
      SUM(CASE WHEN t.resultado NOT IN ('boleto','golpeado') THEN 1 ELSE 0 END) AS ab,
      SUM(CASE WHEN t.resultado IN $_sqlHits THEN 1 ELSE 0 END) AS h,
      SUM(CASE WHEN t.resultado = 'doble' THEN 1 ELSE 0 END) AS d,
      SUM(CASE WHEN t.resultado = 'triple' THEN 1 ELSE 0 END) AS tr,
      SUM(CASE WHEN t.resultado = 'home_run' THEN 1 ELSE 0 END) AS hr,
      SUM(CASE WHEN t.resultado = 'ponche' THEN 1 ELSE 0 END) AS k,
      SUM(CASE WHEN t.resultado = 'boleto' THEN 1 ELSE 0 END) AS bb,
      (SELECT COUNT(*) FROM turno_carrera c
        WHERE c.juego_id = t.juego_id AND c.impulsor_id = t.bateador_id) AS rbi,
      (SELECT COUNT(*) FROM turno_carrera c
        WHERE c.juego_id = t.juego_id AND c.corredor_id = t.bateador_id)
      + (SELECT COUNT(*) FROM jugada_mov m
          WHERE m.juego_id = t.juego_id AND m.corredor_id = t.bateador_id
            AND m.destino = 'anota') AS runs,
      (SELECT COUNT(*) FROM jugada_mov m
        WHERE m.juego_id = t.juego_id AND m.corredor_id = t.bateador_id
          AND m.tipo = 'robo' AND m.destino NOT IN ('queda','out')) AS sb
    FROM turno_bate t
    WHERE t.juego_id = ? AND t.resultado IS NOT NULL
    GROUP BY t.bateador_id
  ''', [juegoId]);
  for (final f in bateadores) {
    await txn.insert('estadistica_juego_bateador', {
      'juego_id': juegoId,
      'bateador_id': f['bateador_id'],
      'turnos_al_bate': _n(f['ab']),
      'hits_juego': _n(f['h']),
      'dobles_juego': _n(f['d']),
      'triples_juego': _n(f['tr']),
      'home_runs_juego': _n(f['hr']),
      'ponches_juego': _n(f['k']),
      'bases_por_bolas_juego': _n(f['bb']),
      'carreras_impulsadas_juego': _n(f['rbi']),
      'carreras_anotadas_juego': _n(f['runs']),
      'bases_robadas_juego': _n(f['sb']),
    });
  }

  final lanzadores = await txn.rawQuery('''
    SELECT t.lanzador_id,
      SUM(CASE WHEN t.resultado IN $_sqlOuts THEN 1 ELSE 0 END)
        + COALESCE(SUM(t.outs_corredores), 0)
        + (SELECT COALESCE(SUM(jg.outs), 0) FROM jugada_corredor jg
            WHERE jg.juego_id = t.juego_id AND jg.lanzador_id = t.lanzador_id) AS outs,
      SUM(CASE WHEN t.resultado IN $_sqlHits THEN 1 ELSE 0 END) AS h,
      SUM(CASE WHEN t.resultado = 'ponche' THEN 1 ELSE 0 END) AS k,
      SUM(CASE WHEN t.resultado = 'boleto' THEN 1 ELSE 0 END) AS bb,
      (SELECT COUNT(*) FROM lanzamiento l
         JOIN turno_bate t2 ON t2.id = l.turno_id
        WHERE t2.juego_id = t.juego_id
          AND t2.lanzador_id = t.lanzador_id) AS picheos,
      (SELECT COUNT(*) FROM turno_carrera c
        WHERE c.juego_id = t.juego_id AND c.lanzador_id = t.lanzador_id)
      + (SELECT COUNT(*) FROM jugada_mov m
          WHERE m.juego_id = t.juego_id AND m.lanzador_id = t.lanzador_id
            AND m.destino = 'anota') AS cp,
      (SELECT COUNT(*) FROM turno_carrera c
        WHERE c.juego_id = t.juego_id AND c.lanzador_id = t.lanzador_id
          AND c.limpia = 1)
      + (SELECT COUNT(*) FROM jugada_mov m
          WHERE m.juego_id = t.juego_id AND m.lanzador_id = t.lanzador_id
            AND m.destino = 'anota' AND m.limpia = 1) AS cl
    FROM turno_bate t
    WHERE t.juego_id = ? AND t.resultado IS NOT NULL AND t.lanzador_id IS NOT NULL
    GROUP BY t.lanzador_id
  ''', [juegoId]);
  for (final f in lanzadores) {
    await txn.insert('estadistica_juego_lanzador', {
      'juego_id': juegoId,
      'lanzador_id': f['lanzador_id'],
      'innings_lanzados_juego': _n(f['outs']) / 3.0,
      'picheos_lanzados': _n(f['picheos']),
      'carreras_permitidas': _n(f['cp']),
      'carreras_limpias_juego': _n(f['cl']),
      'ponches': _n(f['k']),
      'bases_por_bolas': _n(f['bb']),
      'hits_permitidos': _n(f['h']),
    });
  }
}