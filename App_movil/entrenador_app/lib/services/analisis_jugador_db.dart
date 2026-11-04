import 'database_helper.dart';

/// Ultimo lanzamiento de un turno (el que lo cerro).
const String _finJ =
    '(l.numero = (SELECT MAX(l2.numero) FROM lanzamiento l2 WHERE l2.turno_id = l.turno_id))';
const Set<String> _hitsJ = {'sencillo', 'doble', 'triple', 'home_run'};
const Set<String> _strikesJ = {'strike_cantado', 'strike_swing', 'foul'};

int _nj(Object? v) => (v as num?)?.toInt() ?? 0;

extension AnalisisJugadorDB on DatabaseHelper {
  /// Analisis de un bateador sumando todos sus juegos terminados:
  /// totales, por tipo de pitcheo con que cerro el turno y contra
  /// lanzadores zurdos / derechos.
  Future<Map<String, dynamic>> analisisBateadorTotal(int bateadorId) async {
    final db = await database;
    final filas = await db.rawQuery('''
      SELECT t.resultado AS r, tl.nombre AS tipo, p.mano_lanzamiento AS mano,
             COUNT(*) AS n
      FROM turno_bate t
      JOIN juego j ON j.juego_id = t.juego_id AND j.estado = 'finalizado'
      LEFT JOIN jugador p ON p.jugador_id = t.lanzador_id
      LEFT JOIN lanzamiento l ON l.turno_id = t.id AND $_finJ
      LEFT JOIN tipo_lanzamiento tl
        ON tl.tipo_lanzamiento_id = l.tipo_lanzamiento_id
      WHERE t.bateador_id = ? AND t.resultado IS NOT NULL
      GROUP BY t.resultado, tl.nombre, p.mano_lanzamiento
    ''', [bateadorId]);

    final juegos = await db.rawQuery('''
      SELECT COUNT(DISTINCT t.juego_id) AS n
      FROM turno_bate t
      JOIN juego j ON j.juego_id = t.juego_id AND j.estado = 'finalizado'
      WHERE t.bateador_id = ? AND t.resultado IS NOT NULL
    ''', [bateadorId]);

    final tot = <String, int>{
      'pa': 0, 'ab': 0, 'h': 0, '2b': 0, '3b': 0, 'hr': 0, 'k': 0, 'bb': 0,
    };
    final tipos = <String, Map<String, int>>{};
    final manos = <String, Map<String, int>>{};

    void sumar(Map<String, int> m, String r, int n) {
      m['pa'] = (m['pa'] ?? 0) + n;
      if (r != 'boleto' && r != 'golpeado') m['ab'] = (m['ab'] ?? 0) + n;
      if (_hitsJ.contains(r)) m['h'] = (m['h'] ?? 0) + n;
      if (r == 'ponche') m['k'] = (m['k'] ?? 0) + n;
      if (r == 'boleto') m['bb'] = (m['bb'] ?? 0) + n;
    }

    for (final f in filas) {
      final r = f['r'] as String;
      final n = _nj(f['n']);
      sumar(tot, r, n);
      if (r == 'doble') tot['2b'] = tot['2b']! + n;
      if (r == 'triple') tot['3b'] = tot['3b']! + n;
      if (r == 'home_run') tot['hr'] = tot['hr']! + n;
      final tipo = (f['tipo'] as String?) ?? 'Sin tipo';
      sumar(tipos.putIfAbsent(tipo, () => <String, int>{}), r, n);
      final mano = (f['mano'] as String?) ?? 'sin dato';
      sumar(manos.putIfAbsent(mano, () => <String, int>{}), r, n);
    }

    List<Map<String, dynamic>> aLista(Map<String, Map<String, int>> m, String clave) {
      final l = m.entries
          .map((e) => <String, dynamic>{
                clave: e.key,
                'pa': e.value['pa'] ?? 0,
                'ab': e.value['ab'] ?? 0,
                'h': e.value['h'] ?? 0,
                'k': e.value['k'] ?? 0,
                'bb': e.value['bb'] ?? 0,
              })
          .toList();
      l.sort((a, c) => (c['ab'] as int).compareTo(a['ab'] as int));
      return l;
    }

    return {
      'juegos': _nj(juegos.first['n']),
      ...tot,
      'tipos': aLista(tipos, 'tipo'),
      'manos': aLista(manos, 'mano'),
    };
  }

  /// Analisis de un lanzador sumando todos sus juegos terminados:
  /// lanzamientos, strikes, hits y ponches, por tipo de pitcheo y contra
  /// bateadores zurdos / derechos.
  Future<Map<String, dynamic>> analisisLanzadorTotal(int lanzadorId) async {
    final db = await database;
    final filas = await db.rawQuery('''
      SELECT tl.nombre AS tipo, b.mano_bateo AS mano, l.resultado AS r,
             CASE WHEN $_finJ THEN t.resultado ELSE NULL END AS fin,
             COUNT(*) AS n
      FROM lanzamiento l
      JOIN turno_bate t ON t.id = l.turno_id
      JOIN juego j ON j.juego_id = t.juego_id AND j.estado = 'finalizado'
      LEFT JOIN jugador b ON b.jugador_id = t.bateador_id
      LEFT JOIN tipo_lanzamiento tl
        ON tl.tipo_lanzamiento_id = l.tipo_lanzamiento_id
      WHERE t.lanzador_id = ?
      GROUP BY tl.nombre, b.mano_bateo, l.resultado, fin
    ''', [lanzadorId]);

    final juegos = await db.rawQuery('''
      SELECT COUNT(DISTINCT t.juego_id) AS n
      FROM turno_bate t
      JOIN juego j ON j.juego_id = t.juego_id AND j.estado = 'finalizado'
      WHERE t.lanzador_id = ?
    ''', [lanzadorId]);

    final tot = <String, int>{'n': 0, 'st': 0, 'bo': 0, 'h': 0, 'k': 0, 'bb': 0};
    final tipos = <String, Map<String, int>>{};
    final manos = <String, Map<String, int>>{};

    void sumar(Map<String, int> m, String r, String? fin, int n) {
      m['n'] = (m['n'] ?? 0) + n;
      if (_strikesJ.contains(r)) m['st'] = (m['st'] ?? 0) + n;
      if (r == 'bola') m['bo'] = (m['bo'] ?? 0) + n;
      if (fin != null && _hitsJ.contains(fin)) m['h'] = (m['h'] ?? 0) + n;
      if (fin == 'ponche') m['k'] = (m['k'] ?? 0) + n;
      if (fin == 'boleto') m['bb'] = (m['bb'] ?? 0) + n;
    }

    for (final f in filas) {
      final r = f['r'] as String;
      final fin = f['fin'] as String?;
      final n = _nj(f['n']);
      sumar(tot, r, fin, n);
      final tipo = (f['tipo'] as String?) ?? 'Sin tipo';
      sumar(tipos.putIfAbsent(tipo, () => <String, int>{}), r, fin, n);
      final mano = (f['mano'] as String?) ?? 'sin dato';
      sumar(manos.putIfAbsent(mano, () => <String, int>{}), r, fin, n);
    }

    List<Map<String, dynamic>> aLista(Map<String, Map<String, int>> m, String clave) {
      final l = m.entries
          .map((e) => <String, dynamic>{
                clave: e.key,
                'n': e.value['n'] ?? 0,
                'st': e.value['st'] ?? 0,
                'bo': e.value['bo'] ?? 0,
                'h': e.value['h'] ?? 0,
                'k': e.value['k'] ?? 0,
              })
          .toList();
      l.sort((a, c) => (c['n'] as int).compareTo(a['n'] as int));
      return l;
    }

    return {
      'juegos': _nj(juegos.first['n']),
      ...tot,
      'tipos': aLista(tipos, 'tipo'),
      'manos': aLista(manos, 'mano'),
    };
  }
}