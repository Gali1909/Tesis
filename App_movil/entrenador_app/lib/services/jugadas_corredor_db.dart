import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'corredores_db.dart';
import 'database_helper.dart';

const Set<String> _tiposJugada = {
  'robo',
  'robo_frustrado',
  'wild_pitch',
  'passed_ball',
  'balk',
};

/// Tablas de jugadas de corredores (robos, wild pitch, passed ball, balk) y
/// la columna de bases robadas por juego. Se puede llamar varias veces.
Future<void> crearTablasJugadasCorredor(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS jugada_corredor (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      juego_id INTEGER NOT NULL,
      turno_ref INTEGER NOT NULL,
      cerrado INTEGER NOT NULL DEFAULT 0,
      tipo TEXT NOT NULL,
      entrada INTEGER NOT NULL,
      mitad TEXT NOT NULL,
      propio INTEGER NOT NULL,
      lanzador_id INTEGER,
      outs INTEGER NOT NULL DEFAULT 0,
      carreras INTEGER NOT NULL DEFAULT 0,
      outs_antes INTEGER NOT NULL,
      bases_antes TEXT,
      bases_despues TEXT,
      creado_ms INTEGER NOT NULL,
      uuid TEXT,
      FOREIGN KEY (juego_id) REFERENCES juego (juego_id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS jugada_mov (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      jugada_id INTEGER NOT NULL,
      juego_id INTEGER NOT NULL,
      tipo TEXT NOT NULL,
      corredor_id INTEGER NOT NULL,
      origen INTEGER NOT NULL,
      destino TEXT NOT NULL,
      lanzador_id INTEGER,
      limpia INTEGER NOT NULL DEFAULT 1,
      uuid TEXT,
      FOREIGN KEY (jugada_id) REFERENCES jugada_corredor (id) ON DELETE CASCADE,
      FOREIGN KEY (juego_id) REFERENCES juego (juego_id) ON DELETE CASCADE
    )
  ''');
  final cols = await db.rawQuery('PRAGMA table_info(estadistica_juego_bateador)');
  final existentes = cols.map((c) => c['name'] as String).toSet();
  if (!existentes.contains('bases_robadas_juego')) {
    await db.execute(
      'ALTER TABLE estadistica_juego_bateador ADD COLUMN bases_robadas_juego INTEGER',
    );
  }
}

int _cuenta(List<Map<String, Object?>> r) => (r.first['n'] as num?)?.toInt() ?? 0;

/// Ultima jugada del juego, solo si no se registro nada despues de ella.
Future<Map<String, dynamic>?> _ultimaDeshacible(
  DatabaseExecutor txn,
  int juegoId,
) async {
  final u = await txn.query(
    'jugada_corredor',
    where: 'juego_id = ?',
    whereArgs: [juegoId],
    orderBy: 'id DESC',
    limit: 1,
  );
  if (u.isEmpty) return null;
  final ms = u.first['creado_ms'] as int;
  final lz = await txn.rawQuery(
    'SELECT COUNT(*) AS n FROM lanzamiento WHERE juego_id = ? AND creado_ms > ?',
    [juegoId, ms],
  );
  final ac = await txn.rawQuery(
    "SELECT COUNT(*) AS n FROM juego_accion WHERE juego_id = ? AND creado_ms > ? "
    "AND NOT (tipo = 'jugada_corredor' AND ref_id = ?)",
    [juegoId, ms, u.first['id']],
  );
  if (_cuenta(lz) + _cuenta(ac) > 0) return null;
  return Map<String, dynamic>.from(u.first);
}

extension JugadasCorredorDB on DatabaseHelper {
  /// Corredores en base ahora mismo, o null si no se puede registrar una
  /// jugada (juego terminado o turno anterior sin corredores registrados).
  Future<Map<String, dynamic>?> obtenerCorredoresActuales(int juegoId) async {
    final db = await database;
    final j = await db.query(
      'juego',
      columns: ['estado', 'entrada_actual', 'mitad_actual', 'outs_actuales'],
      where: 'juego_id = ?',
      whereArgs: [juegoId],
      limit: 1,
    );
    if (j.isEmpty || j.first['estado'] != 'en_juego') return null;
    final ult = await db.query(
      'turno_bate',
      columns: ['bases_antes', 'bases_despues'],
      where: 'juego_id = ? AND resultado IS NOT NULL',
      whereArgs: [juegoId],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (ult.isNotEmpty &&
        ult.first['bases_antes'] != null &&
        ult.first['bases_despues'] == null) {
      return null;
    }
    final abierto = await db.query(
      'turno_bate',
      columns: ['id'],
      where: 'juego_id = ? AND resultado IS NULL',
      whereArgs: [juegoId],
      limit: 1,
    );
    final tope = abierto.isNotEmpty ? abierto.first['id'] as int : 1 << 40;
    final bases = await basesActuales(
      db,
      juegoId,
      (j.first['entrada_actual'] as int?) ?? 1,
      (j.first['mitad_actual'] as String?) ?? 'alta',
      tope,
    );
    final corredores = <Map<String, dynamic>>[];
    for (var i = 0; i < 3; i++) {
      final b = bases[i];
      if (b == null) continue;
      final p = await db.query(
        'jugador',
        columns: ['nombre', 'numero'],
        where: 'jugador_id = ?',
        whereArgs: [b[0]],
        limit: 1,
      );
      corredores.add({
        'base': i + 1,
        'jugador_id': b[0],
        'nombre': p.isEmpty ? '?' : p.first['nombre'],
        'numero': p.isEmpty ? null : p.first['numero'],
      });
    }
    return {
      'corredores': corredores,
      'outs': (j.first['outs_actuales'] as int?) ?? 0,
    };
  }

  Future<Map<String, dynamic>?> obtenerUltimaJugadaDeshacible(int juegoId) async {
    final db = await database;
    return _ultimaDeshacible(db, juegoId);
  }

  /// movs: lista de {origen: 1..3, destino: queda|2|3|anota|out}
  Future<void> registrarJugadaCorredores(
    int juegoId,
    String tipo,
    List<Map<String, dynamic>> movs,
  ) async {
    if (!_tiposJugada.contains(tipo)) throw StateError('Jugada desconocida.');
    final db = await database;
    await db.transaction((txn) async {
      final jr = await txn.query(
        'juego',
        columns: [
          'estado',
          'entrada_actual',
          'mitad_actual',
          'outs_actuales',
          'propio_local',
          'lanzador_inicial_id',
          'lanzador_propio_id',
          'lanzador_rival_id',
        ],
        where: 'juego_id = ?',
        whereArgs: [juegoId],
        limit: 1,
      );
      if (jr.isEmpty) throw StateError('El juego ya no existe.');
      final j = jr.first;
      if (j['estado'] != 'en_juego') throw StateError('Este juego ya termino.');
      await exigirCorredoresResueltos(txn, juegoId);

      final entrada = (j['entrada_actual'] as int?) ?? 1;
      final mitad = (j['mitad_actual'] as String?) ?? 'alta';
      final outs = (j['outs_actuales'] as int?) ?? 0;
      final local = ((j['propio_local'] as int?) ?? 0) == 1;
      final propio = (local && mitad == 'baja') || (!local && mitad == 'alta');

      final abierto = await txn.query(
        'turno_bate',
        columns: ['id'],
        where: 'juego_id = ? AND resultado IS NULL',
        whereArgs: [juegoId],
        limit: 1,
      );
      var turnoRef = 0;
      var cerrado = 0;
      if (abierto.isNotEmpty) {
        turnoRef = abierto.first['id'] as int;
      } else {
        final u = await txn.query(
          'turno_bate',
          columns: ['id'],
          where: 'juego_id = ?',
          whereArgs: [juegoId],
          orderBy: 'id DESC',
          limit: 1,
        );
        if (u.isEmpty) throw StateError('No hay corredores en base.');
        turnoRef = u.first['id'] as int;
        cerrado = 1;
      }
      final tope = abierto.isNotEmpty ? turnoRef : 1 << 40;
      final antes = await basesActuales(txn, juegoId, entrada, mitad, tope);
      if (antes.every((b) => b == null)) {
        throw StateError('No hay corredores en base.');
      }

      final destinos = <int, String>{
        for (final m in movs) m['origen'] as int: m['destino'] as String,
      };
      final nuevas = <List<int?>?>[null, null, null];
      final registros = <Map<String, Object?>>[];
      var outsN = 0;
      var carreras = 0;

      void colocar(int base, List<int?> e) {
        if (nuevas[base - 1] != null) {
          throw StateError('Dos jugadores no pueden quedar en la misma base.');
        }
        nuevas[base - 1] = e;
      }

      for (var b = 1; b <= 3; b++) {
        final e = antes[b - 1];
        if (e == null) continue;
        final d = destinos[b] ?? 'queda';
        if (d == 'queda') {
          colocar(b, e);
          continue;
        }
        final limpia = (tipo != 'passed_ball' && (e[2] ?? 1) == 1) ? 1 : 0;
        registros.add({
          'tipo': tipo,
          'corredor_id': e[0],
          'origen': b,
          'destino': d,
          'lanzador_id': e[1],
          'limpia': limpia,
        });
        if (d == 'out') {
          outsN++;
        } else if (d == 'anota') {
          carreras++;
        } else {
          final base = int.tryParse(d);
          if (base == null || base <= b || base > 3) {
            throw StateError('Destino invalido.');
          }
          colocar(base, e);
        }
      }
      if (registros.isEmpty) {
        throw StateError('Elige que paso con algun corredor.');
      }

      final termina = outsN > 0 && outs + outsN >= 3;
      if (termina && abierto.isNotEmpty) {
        final p = await txn.rawQuery(
          'SELECT COUNT(*) AS n FROM lanzamiento WHERE turno_id = ?',
          [turnoRef],
        );
        if (_cuenta(p) > 0) {
          throw StateError(
            'Ese out termina la mitad con un turno en curso. Termina o deshaz ese turno primero.',
          );
        }
        await txn.delete('turno_bate', where: 'id = ?', whereArgs: [turnoRef]);
      }

      final basesFinal = termina ? <List<int?>?>[null, null, null] : nuevas;
      final ahora = DateTime.now().millisecondsSinceEpoch;
      final lanzadorId = propio
          ? j['lanzador_rival_id']
          : (j['lanzador_propio_id'] ?? j['lanzador_inicial_id']);
      final jid = await txn.insert('jugada_corredor', {
        'juego_id': juegoId,
        'turno_ref': turnoRef,
        'cerrado': cerrado,
        'tipo': tipo,
        'entrada': entrada,
        'mitad': mitad,
        'propio': propio ? 1 : 0,
        'lanzador_id': lanzadorId,
        'outs': outsN,
        'carreras': carreras,
        'outs_antes': outs,
        'bases_antes': jsonEncode(antes),
        'bases_despues': jsonEncode(basesFinal),
        'creado_ms': ahora,
      });
      for (final r in registros) {
        await txn.insert('jugada_mov', {
          ...r,
          'jugada_id': jid,
          'juego_id': juegoId,
        });
      }

      if (carreras > 0) {
        final col = propio ? 'carreras_propias' : 'carreras_rival';
        await txn.rawInsert(
          'INSERT OR IGNORE INTO juego_entrada '
          '(juego_id, numero, carreras_propias, carreras_rival) VALUES (?, ?, 0, 0)',
          [juegoId, entrada],
        );
        await txn.rawUpdate(
          'UPDATE juego_entrada SET $col = $col + ? WHERE juego_id = ? AND numero = ?',
          [carreras, juegoId, entrada],
        );
      }

      if (outsN > 0) {
        await txn.insert('juego_accion', {
          'juego_id': juegoId,
          'tipo': 'jugada_corredor',
          'equipo': null,
          'delta': 0,
          'entrada_antes': entrada,
          'mitad_antes': mitad,
          'outs_antes': outs,
          'ref_id': jid,
          'creado_ms': ahora,
        });
        if (termina) {
          if (mitad == 'alta') {
            await txn.update(
              'juego',
              {'entrada_actual': entrada, 'mitad_actual': 'baja', 'outs_actuales': 0},
              where: 'juego_id = ?',
              whereArgs: [juegoId],
            );
          } else {
            await txn.rawInsert(
              'INSERT OR IGNORE INTO juego_entrada '
              '(juego_id, numero, carreras_propias, carreras_rival) VALUES (?, ?, 0, 0)',
              [juegoId, entrada + 1],
            );
            await txn.update(
              'juego',
              {
                'entrada_actual': entrada + 1,
                'mitad_actual': 'alta',
                'outs_actuales': 0,
              },
              where: 'juego_id = ?',
              whereArgs: [juegoId],
            );
          }
        } else {
          await txn.update(
            'juego',
            {'outs_actuales': outs + outsN},
            where: 'juego_id = ?',
            whereArgs: [juegoId],
          );
        }
      }
    });
  }

  /// Deshace la ultima jugada de corredores. Devuelve false si no habia.
  Future<bool> deshacerJugadaCorredores(int juegoId) async {
    final db = await database;
    return db.transaction<bool>((txn) async {
      final g = await txn.query(
        'juego',
        columns: ['estado'],
        where: 'juego_id = ?',
        whereArgs: [juegoId],
        limit: 1,
      );
      if (g.isEmpty) throw StateError('El juego ya no existe.');
      if (g.first['estado'] != 'en_juego') throw StateError('Este juego ya termino.');
      final cualquiera = await txn.query(
        'jugada_corredor',
        columns: ['id'],
        where: 'juego_id = ?',
        whereArgs: [juegoId],
        limit: 1,
      );
      if (cualquiera.isEmpty) return false;
      final u = await _ultimaDeshacible(txn, juegoId);
      if (u == null) {
        throw StateError('Antes deshaz lo que se registro despues de esa jugada.');
      }
      final carreras = (u['carreras'] as int?) ?? 0;
      if (carreras > 0) {
        final col = (u['propio'] as int?) == 1 ? 'carreras_propias' : 'carreras_rival';
        await txn.rawUpdate(
          'UPDATE juego_entrada SET $col = MAX(0, $col - ?) '
          'WHERE juego_id = ? AND numero = ?',
          [carreras, juegoId, u['entrada']],
        );
      }
      if (((u['outs'] as int?) ?? 0) > 0) {
        await txn.update(
          'juego',
          {
            'entrada_actual': u['entrada'],
            'mitad_actual': u['mitad'],
            'outs_actuales': u['outs_antes'],
          },
          where: 'juego_id = ?',
          whereArgs: [juegoId],
        );
        await txn.delete(
          'juego_accion',
          where: "juego_id = ? AND tipo = 'jugada_corredor' AND ref_id = ?",
          whereArgs: [juegoId, u['id']],
        );
      }
      await txn.delete('jugada_corredor', where: 'id = ?', whereArgs: [u['id']]);
      return true;
    });
  }
}