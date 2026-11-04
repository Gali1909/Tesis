import 'database_helper.dart';

/// Ultimo lanzamiento de un turno (el que lo cerro).
const String _fin =
    '(l.numero = (SELECT MAX(l2.numero) FROM lanzamiento l2 WHERE l2.turno_id = l.turno_id))';
const Set<String> _hits = {'sencillo', 'doble', 'triple', 'home_run'};
const Set<String> _strikes = {'strike_cantado', 'strike_swing', 'foul'};

int _n(Object? v) => (v as num?)?.toInt() ?? 0;

extension AnalisisDB on DatabaseHelper {
  /// Juegos terminados que tienen turnos registrados.
  Future<List<Map<String, dynamic>>> obtenerJuegosAnalisis() async {
    final db = await database;
    return db.rawQuery('''
      SELECT j.juego_id, j.fecha, j.carreras_propias, j.carreras_rival,
             q.nombre AS rival
      FROM juego j
      LEFT JOIN equipo q ON q.equipo_id = j.equipo_rival_id
      WHERE j.estado = 'finalizado'
        AND EXISTS (SELECT 1 FROM turno_bate t WHERE t.juego_id = j.juego_id)
      ORDER BY j.fecha DESC, j.juego_id DESC
    ''');
  }

  /// Por bateador: turnos, hits, ponches, boletos y resultado segun el
  /// tipo de pitcheo con que termino cada turno.
  Future<List<Map<String, dynamic>>> analisisBateadores(
    int juegoId, {
    required bool propio,
  }) async {
    final db = await database;
    final filas = await db.rawQuery('''
      SELECT t.bateador_id AS id, b.nombre, b.numero, t.resultado,
             tl.nombre AS tipo, COUNT(*) AS n, MIN(t.numero) AS primero
      FROM turno_bate t
      JOIN jugador b ON b.jugador_id = t.bateador_id
      LEFT JOIN lanzamiento l ON l.turno_id = t.id AND $_fin
      LEFT JOIN tipo_lanzamiento tl
        ON tl.tipo_lanzamiento_id = l.tipo_lanzamiento_id
      WHERE t.juego_id = ? AND t.propio = ? AND t.resultado IS NOT NULL
      GROUP BY t.bateador_id, t.resultado, tl.nombre
    ''', [juegoId, propio ? 1 : 0]);

    final porId = <int, Map<String, dynamic>>{};
    for (final f in filas) {
      final id = f['id'] as int;
      final b = porId.putIfAbsent(
        id,
        () => <String, dynamic>{
          'id': id,
          'nombre': f['nombre'],
          'numero': f['numero'],
          'primero': _n(f['primero']),
          'ab': 0,
          'h': 0,
          'k': 0,
          'bb': 0,
          'tipos': <String, Map<String, int>>{},
        },
      );
      if (_n(f['primero']) < (b['primero'] as int)) b['primero'] = _n(f['primero']);
      final r = f['resultado'] as String;
      final n = _n(f['n']);
      if (r != 'boleto' && r != 'golpeado') b['ab'] = (b['ab'] as int) + n;
      if (_hits.contains(r)) b['h'] = (b['h'] as int) + n;
      if (r == 'ponche') b['k'] = (b['k'] as int) + n;
      if (r == 'boleto') b['bb'] = (b['bb'] as int) + n;
      final tipo = (f['tipo'] as String?) ?? 'Sin tipo';
      final tipos = b['tipos'] as Map<String, Map<String, int>>;
      final tm = tipos.putIfAbsent(tipo, () => <String, int>{'n': 0, 'h': 0, 'k': 0});
      tm['n'] = tm['n']! + n;
      if (_hits.contains(r)) tm['h'] = tm['h']! + n;
      if (r == 'ponche') tm['k'] = tm['k']! + n;
    }

    final lista = <Map<String, dynamic>>[];
    for (final b in porId.values) {
      final tipos = (b['tipos'] as Map<String, Map<String, int>>)
          .entries
          .map((e) => <String, dynamic>{
                'tipo': e.key,
                'n': e.value['n'],
                'h': e.value['h'],
                'k': e.value['k'],
              })
          .toList()
        ..sort((a, c) {
          final h = (c['h'] as int).compareTo(a['h'] as int);
          if (h != 0) return h;
          final k = (c['k'] as int).compareTo(a['k'] as int);
          if (k != 0) return k;
          return (c['n'] as int).compareTo(a['n'] as int);
        });
      lista.add({...b, 'tipos': tipos});
    }
    lista.sort((a, c) => (a['primero'] as int).compareTo(c['primero'] as int));
    return lista;
  }

  /// Por lanzador: lanzamientos, strikes, hits y ponches, por tipo de
  /// pitcheo y por cuenta. propio = true analiza a tu lanzador.
  Future<List<Map<String, dynamic>>> analisisLanzadores(
    int juegoId, {
    required bool propio,
  }) async {
    final db = await database;
    final filas = await db.rawQuery('''
      SELECT t.lanzador_id AS id, p.nombre, p.numero, tl.nombre AS tipo,
             l.bolas_antes AS b, l.strikes_antes AS s, l.resultado AS r,
             CASE WHEN $_fin THEN t.resultado ELSE NULL END AS fin,
             COUNT(*) AS n, MIN(t.numero) AS primero
      FROM lanzamiento l
      JOIN turno_bate t ON t.id = l.turno_id
      JOIN jugador p ON p.jugador_id = t.lanzador_id
      LEFT JOIN tipo_lanzamiento tl
        ON tl.tipo_lanzamiento_id = l.tipo_lanzamiento_id
      WHERE t.juego_id = ? AND t.propio = ? AND t.lanzador_id IS NOT NULL
      GROUP BY t.lanzador_id, tl.nombre, l.bolas_antes, l.strikes_antes,
               l.resultado, fin
    ''', [juegoId, propio ? 0 : 1]);

    final porId = <int, Map<String, dynamic>>{};
    for (final f in filas) {
      final id = f['id'] as int;
      final p = porId.putIfAbsent(
        id,
        () => <String, dynamic>{
          'id': id,
          'nombre': f['nombre'],
          'numero': f['numero'],
          'primero': _n(f['primero']),
          'n': 0,
          'st': 0,
          'h': 0,
          'k': 0,
          'tipos': <String, Map<String, int>>{},
          'cuentas': <String, Map<String, int>>{},
        },
      );
      if (_n(f['primero']) < (p['primero'] as int)) p['primero'] = _n(f['primero']);
      final n = _n(f['n']);
      final r = f['r'] as String;
      final fin = f['fin'] as String?;
      final esStrike = _strikes.contains(r);
      final esHit = fin != null && _hits.contains(fin);
      final esK = fin == 'ponche';

      p['n'] = (p['n'] as int) + n;
      if (esStrike) p['st'] = (p['st'] as int) + n;
      if (esHit) p['h'] = (p['h'] as int) + n;
      if (esK) p['k'] = (p['k'] as int) + n;

      final tipo = (f['tipo'] as String?) ?? 'Sin tipo';
      final tipos = p['tipos'] as Map<String, Map<String, int>>;
      final tm = tipos.putIfAbsent(
        tipo,
        () => <String, int>{'n': 0, 'st': 0, 'h': 0, 'k': 0},
      );
      tm['n'] = tm['n']! + n;
      if (esStrike) tm['st'] = tm['st']! + n;
      if (esHit) tm['h'] = tm['h']! + n;
      if (esK) tm['k'] = tm['k']! + n;

      final b = _n(f['b']);
      final s = _n(f['s']);
      final cuentas = p['cuentas'] as Map<String, Map<String, int>>;
      final cm = cuentas.putIfAbsent(
        '$b-$s',
        () => <String, int>{'b': b, 's': s, 'n': 0, 'st': 0, 'bo': 0, 'h': 0, 'k': 0},
      );
      cm['n'] = cm['n']! + n;
      if (esStrike) cm['st'] = cm['st']! + n;
      if (r == 'bola') cm['bo'] = cm['bo']! + n;
      if (esHit) cm['h'] = cm['h']! + n;
      if (esK) cm['k'] = cm['k']! + n;
    }

    final lista = <Map<String, dynamic>>[];
    for (final p in porId.values) {
      final tipos = (p['tipos'] as Map<String, Map<String, int>>)
          .entries
          .map((e) => <String, dynamic>{'tipo': e.key, ...e.value})
          .toList()
        ..sort((a, c) => (c['n'] as int).compareTo(a['n'] as int));
      final cuentas = (p['cuentas'] as Map<String, Map<String, int>>)
          .entries
          .map((e) => <String, dynamic>{'cuenta': e.key, ...e.value})
          .toList()
        ..sort((a, c) {
          final b = (a['b'] as int).compareTo(c['b'] as int);
          if (b != 0) return b;
          return (a['s'] as int).compareTo(c['s'] as int);
        });
      lista.add({...p, 'tipos': tipos, 'cuentas': cuentas});
    }
    lista.sort((a, c) => (a['primero'] as int).compareTo(c['primero'] as int));
    return lista;
  }
}