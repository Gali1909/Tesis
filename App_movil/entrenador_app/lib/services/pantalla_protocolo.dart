import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'database_helper.dart';

/// Protocolo app -> pantalla del coach (via BLE).
///
/// Trama: 0xAA 0x55 | tipo | seq | largo(2, little endian) | payload | xor
/// El xor es el de tipo, seq, largo y payload. El payload es texto UTF-8:
/// lineas separadas por \n y campos separados por |.
class PantallaProtocolo {
  static const int tHello = 0x01;
  static const int tTipos = 0x10;
  static const int tJugadas = 0x11;
  static const int tLineup = 0x12;
  static const int tPerfilLanzador = 0x13;
  static const int tQuitarPerfil = 0x14;
  static const int tPerfilDatos = 0x15;
  static const int tPerfilVista = 0x16;
  static const int tPerfilTipos = 0x17;
  static const int tAck = 0x20;
  static const int version = 1;
  static const int maxPayload = 2048;

  static Uint8List armar(int tipo, int seq, List<int> payload) {
    final len = payload.length;
    final b = BytesBuilder();
    b.add([0xAA, 0x55, tipo, seq & 0xFF, len & 0xFF, (len >> 8) & 0xFF]);
    b.add(payload);
    var x = tipo ^ (seq & 0xFF) ^ (len & 0xFF) ^ ((len >> 8) & 0xFF);
    for (final p in payload) {
      x ^= p;
    }
    b.addByte(x & 0xFF);
    return b.toBytes();
  }

  static String _limpio(Object? s) =>
      (s ?? '').toString().replaceAll(RegExp(r'[|\r\n]'), ' ').trim();

  static List<int> _codificar(String texto) {
    final bytes = utf8.encode(texto);
    if (bytes.length > maxPayload) {
      throw StateError(
        'El mensaje pesa ${bytes.length} bytes y el maximo es $maxPayload.',
      );
    }
    return bytes;
  }

  static List<int> payloadHello() => _codificar('v$version');

  /// Perfil de lanzador: nombre, numero, cantidad de tipos disponibles y la
  /// lista de slots disponibles separados por coma. El slot es la posicion
  /// del tipo en la lista que entrega payloadTipos.
  static Future<List<int>> payloadPerfilLanzador(int lanzadorId) async {
    final db = await DatabaseHelper.instance.database;
    final j = await db.rawQuery(
      'SELECT nombre, numero FROM jugador WHERE jugador_id = ?',
      [lanzadorId],
    );
    if (j.isEmpty) throw StateError('El lanzador ya no existe.');
    final disp = await db.rawQuery(
      '''
      SELECT DISTINCT t.nombre AS nombre
      FROM lanzador_tipo_picheo l
      JOIN tipo_lanzamiento t ON t.tipo_lanzamiento_id = l.tipo_lanzamiento_id
      WHERE l.lanzador_id = ?
      ''',
      [lanzadorId],
    );
    // El slot es la posicion del tipo en la lista predeterminada de la app
    // (no el orden de los ids de la base), para que coincida con la pantalla.
    final catalogo = DatabaseHelper.tiposLanzamientoPredeterminados
        .map((e) => e.toLowerCase())
        .toList();
    final unicos = <int>{};
    for (final f in disp) {
      final i = catalogo.indexOf(_limpio(f['nombre']).toLowerCase());
      if (i >= 0) unicos.add(i);
    }
    final slots = unicos.toList()..sort();
    if (slots.isEmpty) {
      throw StateError(
        'Este lanzador no tiene tipos de pitcheo registrados que la pantalla reconozca.',
      );
    }
    return _codificar(
      '${_limpio(j.first['nombre'])}\n${_limpio(j.first['numero'])}\n'
      '${slots.length}\n${slots.join(',')}\n',
    );
  }

  /// Datos completos del perfil para la pantalla (trama 0x15, binaria).
  /// Enteros de 16 bits en little-endian. Ver perfil_lanzador_rx.c en la P4.
  ///  [0] numero  [1] mano (0 derecho, 1 zurdo)  [2] edad (0 = no se guarda)
  ///  [3..16] G, P, J, A, SV, SO, BB   [17..22] PCL*100, WHIP*100, IL*10
  ///  [23] cantidad de tipos (0..5)  [24..38] 5 x (slot, vel, vel)
  ///  [39] largo del nombre (max 24)  [40..] nombre UTF-8
  /// Las estadisticas son las de la temporada que muestra el perfil en la app
  /// (base manual + salidas registradas, obtenerLanzadorPerfilTotal). Si no se
  /// indica temporada se usa la mas reciente. La velocidad es la promedio de
  /// cada tipo.
  static Future<List<int>> payloadPerfilDatos(int lanzadorId, {int? temporada}) async {
    final dbh = DatabaseHelper.instance;
    final db = await dbh.database;
    final j = await db.rawQuery(
      'SELECT nombre, numero, mano_lanzamiento FROM jugador WHERE jugador_id = ?',
      [lanzadorId],
    );
    if (j.isEmpty) throw StateError('El lanzador ya no existe.');
    final temps = await dbh.obtenerTemporadasLanzadorTotal(lanzadorId);
    final anio = temporada ?? (temps.isEmpty ? null : temps.first);
    final h = anio == null
        ? null
        : await dbh.obtenerLanzadorPerfilTotal(lanzadorId, anio);
    final tipos = await dbh.obtenerTiposPicheo(lanzadorId);

    int acotar(num? v, int max) => (v ?? 0).round().clamp(0, max).toInt();
    final b = BytesBuilder();
    void w16(num? v) {
      final x = acotar(v, 65535);
      b.addByte(x & 0xFF);
      b.addByte((x >> 8) & 0xFF);
    }

    b.addByte(acotar(j.first['numero'] as num?, 255));
    b.addByte((j.first['mano_lanzamiento'] ?? '').toString() == 'zurdo' ? 1 : 0);
    b.addByte(0); // edad: la app no la guarda

    w16(h?.juegosGanados);
    w16(h?.juegosPerdidos);
    w16(h?.juegosLanzados);
    w16(h?.aperturas);
    w16(h?.salvados);
    w16(h?.ponches);
    w16(h?.basesPorBolas);
    final ef = h?.efectividad;
    final wh = h?.whip;
    w16(ef == null ? 0 : ef * 100);
    w16(wh == null ? 0 : wh * 100);
    final outs = ((h?.inningsLanzados ?? 0) * 3).round();
    w16((outs ~/ 3) * 10 + (outs % 3)); // 200.1 -> 2001

    // Hasta 5 tipos: primero los que mas usa. El slot es el mismo del 0x13.
    final catalogo = DatabaseHelper.tiposLanzamientoPredeterminados
        .map((e) => e.toLowerCase())
        .toList();
    // Mismo orden que el repertorio de la app: mas frecuente primero. Si un
    // mismo slot aparece dos veces (p. ej. "Slider" y "slider") se queda con
    // el de mayor frecuencia.
    final filas = <List<double>>[]; // [slot, frecuencia, velocidad]
    for (final t in tipos) {
      final i = catalogo.indexOf(_limpio(t.nombreTipo).toLowerCase());
      if (i < 0) continue;
      filas.add([i.toDouble(), t.frecuencia ?? 0, t.velocidadPromedio ?? 0]);
    }
    filas.sort((a, c) {
      final d = c[1].compareTo(a[1]);
      return d != 0 ? d : a[0].compareTo(c[0]);
    });
    final vistos = <int>{};
    filas.retainWhere((f) => vistos.add(f[0].toInt()));
    final top = filas.take(5).toList();
    b.addByte(top.length);
    for (var i = 0; i < 5; i++) {
      if (i < top.length) {
        final v = acotar(top[i][2], 255);
        b.add([top[i][0].toInt(), v, v]);
      } else {
        b.add([0, 0, 0]);
      }
    }

    var nombre = utf8.encode(_limpio(j.first['nombre']));
    if (nombre.length > 24) {
      var n = 24;
      while (n > 0 && (nombre[n] & 0xC0) == 0x80) {
        n--; // no cortar a mitad de un caracter
      }
      nombre = nombre.sublist(0, n);
    }
    b.addByte(nombre.length);
    b.add(nombre);
    debugPrint(
      '0x15 temporada=$anio perfil=${h != null} G=${h?.juegosGanados} '
      'P=${h?.juegosPerdidos} SO=${h?.ponches} ERA=${h?.efectividad} '
      'tiposDb=${tipos.length} enviados=${top.map((f) => "${f[0].toInt()}:${f[2]}").toList()} '
      'bytes=${b.length}',
    );
    return b.toBytes();
  }

  /// Lista completa de lanzamientos del pitcher (trama 0x17):
  /// [n] + n x [slot, vel, vel]  (n <= 14). Primero los que mas usa.
  static Future<List<int>> payloadPerfilTipos(int lanzadorId) async {
    final dbh = DatabaseHelper.instance;
    final tipos = await dbh.obtenerTiposPicheo(lanzadorId);
    final catalogo = DatabaseHelper.tiposLanzamientoPredeterminados
        .map((e) => e.toLowerCase())
        .toList();
    final filas = <List<double>>[]; // [slot, frecuencia, velocidad]
    for (final t in tipos) {
      final i = catalogo.indexOf(_limpio(t.nombreTipo).toLowerCase());
      if (i < 0) continue;
      filas.add([i.toDouble(), t.frecuencia ?? 0, t.velocidadPromedio ?? 0]);
    }
    filas.sort((a, c) {
      final d = c[1].compareTo(a[1]);
      return d != 0 ? d : a[0].compareTo(c[0]);
    });
    final vistos = <int>{};
    filas.retainWhere((f) => vistos.add(f[0].toInt()));
    final top = filas.take(14).toList();
    final b = BytesBuilder();
    b.addByte(top.length);
    for (final f in top) {
      final v = f[2].round().clamp(0, 255).toInt();
      b.add([f[0].toInt(), v, v]);
    }
    return b.toBytes();
  }

  /// Vistas de estadisticas del perfil (trama 0x16): devuelve 6 payloads, uno
  /// por vista: 0 ultima salida, 1 ultimas 5, 2 ultimas 10, 3 ultimas 15,
  /// 4 temporada, 5 de por vida. Ver perfil_vistas.h en la P4.
  /// Payload: [vista][salidas][anio lo][anio hi][n] + n x [id][valor lo][valor hi]
  /// Ids: 0 ERA(x100) 1 WHIP(x100) 2 K/9(x100) 3 IP(x10) 4 H 5 CL 6 SO 7 BB
  ///      8 PIT 9 G 10 P 11 AP 12 SV 13 JL
  static Future<List<List<int>>> payloadsPerfilVistas(
    int lanzadorId, {
    int? temporada,
  }) async {
    final dbh = DatabaseHelper.instance;

    int redondo(num? v, num mult) => ((v ?? 0) * mult).round();
    int ip10(num? innings) {
      final outs = ((innings ?? 0) * 3).round();
      return (outs ~/ 3) * 10 + (outs % 3);
    }

    List<int> armar16(int vista, int salidas, int anio, List<List<int>> campos) {
      final b = BytesBuilder();
      b.add([vista, salidas & 0xFF, anio & 0xFF, (anio >> 8) & 0xFF, campos.length]);
      for (final c in campos) {
        final v = c[1].clamp(0, 65535).toInt();
        b.addByte(c[0]);
        b.addByte(v & 0xFF);
        b.addByte((v >> 8) & 0xFF);
      }
      return b.toBytes();
    }

    final res = <List<int>>[];

    const cuantas = [1, 5, 10, 15];
    for (var i = 0; i < cuantas.length; i++) {
      final m = await dbh.ultimasSalidasLanzador(lanzadorId, cuantas[i]);
      final salidas = (m['salidas'] as num?)?.toInt() ?? 0;
      final outs = (m['outs'] as num?)?.toInt() ?? 0;
      final campos = salidas == 0
          ? <List<int>>[]
          : <List<int>>[
              [0, redondo(m['era'] as num?, 100)],
              [1, redondo(m['whip'] as num?, 100)],
              [2, redondo(m['k9'] as num?, 100)],
              [3, (outs ~/ 3) * 10 + (outs % 3)],
              [4, redondo(m['h'] as num?, 1)],
              [5, redondo(m['cl'] as num?, 1)],
              [6, redondo(m['k'] as num?, 1)],
              [7, redondo(m['bb'] as num?, 1)],
              [8, redondo(m['picheos'] as num?, 1)],
            ];
      res.add(armar16(i, salidas, 0, campos));
    }

    final temps = await dbh.obtenerTemporadasLanzadorTotal(lanzadorId);
    final anio = temporada ?? (temps.isEmpty ? 0 : temps.first);
    final t = anio == 0 ? null : await dbh.obtenerLanzadorPerfilTotal(lanzadorId, anio);
    if (t == null) {
      res.add(armar16(4, 0, anio, []));
    } else {
      final mp = t.toMap();
      res.add(armar16(4, 0, anio, [
        [0, redondo(t.efectividad, 100)],
        [9, redondo(t.juegosGanados, 1)],
        [10, redondo(t.juegosPerdidos, 1)],
        [6, redondo(t.ponches, 1)],
        [1, redondo(t.whip, 100)],
        [11, redondo(t.aperturas, 1)],
        [12, redondo(t.salvados, 1)],
        [13, redondo(t.juegosLanzados, 1)],
        [3, ip10(t.inningsLanzados)],
        [7, redondo(t.basesPorBolas, 1)],
        [4, redondo(mp['hits_permitidos'] as num?, 1)],
        [5, redondo(mp['carreras_limpias'] as num?, 1)],
      ]));
    }

    final hv = await dbh.obtenerLanzadorPerfilHistorico(lanzadorId);
    if (hv == null) {
      res.add(armar16(5, 0, 0, []));
    } else {
      res.add(armar16(5, 0, 0, [
        [0, redondo(hv.efectividad, 100)],
        [9, redondo(hv.juegosGanados, 1)],
        [10, redondo(hv.juegosPerdidos, 1)],
        [6, redondo(hv.ponches, 1)],
        [1, redondo(hv.whip, 100)],
        [11, redondo(hv.aperturas, 1)],
        [12, redondo(hv.salvados, 1)],
        [13, redondo(hv.juegosLanzados, 1)],
        [3, ip10(hv.inningsLanzados)],
        [7, redondo(hv.basesPorBolas, 1)],
        [4, redondo(hv.hitsPermitidos, 1)],
        [5, redondo(hv.carrerasLimpias, 1)],
      ]));
    }
    return res;
  }
  /// Tipos de lanzamiento: "n" y luego "slot|nombre". El slot es la posicion
  /// en la lista (0, 1, 2...), en el orden del catalogo de la app.
  static Future<List<int>> payloadTipos() async {
    final nombres = DatabaseHelper.tiposLanzamientoPredeterminados;
    final sb = StringBuffer('${nombres.length}\n');
    for (var i = 0; i < nombres.length; i++) {
      sb.write('$i|${_limpio(nombres[i])}\n');
    }
    return _codificar(sb.toString());
  }

  /// Jugadas estrategicas: "n" y luego "slot|nombre".
  static Future<List<int>> payloadJugadas() async {
    final db = await DatabaseHelper.instance.database;
    final filas = await db.rawQuery(
      'SELECT nombre FROM jugada_estrategica ORDER BY jugada_id',
    );
    final sb = StringBuffer('${filas.length}\n');
    for (var i = 0; i < filas.length; i++) {
      sb.write('$i|${_limpio(filas[i]['nombre'])}\n');
    }
    return _codificar(sb.toString());
  }

  /// Alineacion: nombre del lineup, "lanzador|numero", "n" y luego
  /// "orden|numero|nombre|posicion" por cada puesto.
  static Future<List<int>> payloadLineup(int lineupId) async {
    final db = await DatabaseHelper.instance.database;
    final cab = await db.rawQuery('''
      SELECT l.nombre AS nombre, p.nombre AS lanzador, p.numero AS numero
      FROM lineup l
      LEFT JOIN jugador p ON p.jugador_id = l.lanzador_id
      WHERE l.lineup_id = ?
    ''', [lineupId]);
    if (cab.isEmpty) throw StateError('El lineup ya no existe.');
    final puestos = await db.rawQuery('''
      SELECT lp.orden AS orden, j.numero AS numero, j.nombre AS nombre,
             lp.posicion AS posicion
      FROM lineup_puesto lp
      JOIN jugador j ON j.jugador_id = lp.jugador_id
      WHERE lp.lineup_id = ?
      ORDER BY lp.orden
    ''', [lineupId]);
    final c = cab.first;
    final sb = StringBuffer()
      ..write('${_limpio(c['nombre'])}\n')
      ..write('${_limpio(c['lanzador'])}|${_limpio(c['numero'])}\n')
      ..write('${puestos.length}\n');
    for (final p in puestos) {
      sb.write(
        '${p['orden']}|${_limpio(p['numero'])}|${_limpio(p['nombre'])}|${_limpio(p['posicion'])}\n',
      );
    }
    return _codificar(sb.toString());
  }
}