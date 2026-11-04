import 'package:flutter/material.dart';

import '../services/analisis_jugador_db.dart';
import '../services/database_helper.dart';

const Color _superficieA = Color(0xFF1E232B);
const Color _cianA = Color(0xFF0ABDCF);
const Color _naranjaA = Color(0xFFE36F10);
const Color _suaveA = Color(0xFF9AA4B2);

/// Tarjeta "Analisis" del perfil: suma todos los juegos terminados del
/// jugador. Para bateadores muestra su rendimiento por tipo de pitcheo y
/// contra zurdos/derechos; para lanzadores, el uso y la efectividad de cada
/// tipo de pitcheo y su rendimiento contra zurdos/derechos.
class AnalisisJugadorCard extends StatefulWidget {
  final int jugadorId;
  final bool esLanzador;

  const AnalisisJugadorCard({
    super.key,
    required this.jugadorId,
    required this.esLanzador,
  });

  @override
  State<AnalisisJugadorCard> createState() => _AnalisisJugadorCardState();
}

class _AnalisisJugadorCardState extends State<AnalisisJugadorCard> {
  late final Future<Map<String, dynamic>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = widget.esLanzador
        ? DatabaseHelper.instance.analisisLanzadorTotal(widget.jugadorId)
        : DatabaseHelper.instance.analisisBateadorTotal(widget.jugadorId);
  }

  int _i(Object? v) => (v as num?)?.toInt() ?? 0;

  String _avg(int h, int ab) {
    if (ab == 0) return '-';
    final s = (h / ab).toStringAsFixed(3);
    return s.startsWith('0') ? s.substring(1) : s;
  }

  String _pct(int a, int b) => b == 0 ? '-' : '${(a * 100 / b).round()}%';

  String _mano(String m, {required bool lanzador}) {
    switch (m) {
      case 'zurdo':
        return 'Contra zurdos';
      case 'derecho':
        return 'Contra derechos';
      case 'izquierda':
        return 'Bateadores zurdos';
      case 'derecha':
        return 'Bateadores derechos';
      case 'ambos':
        return 'Bateadores ambidiestros';
      default:
        return 'Mano sin dato';
    }
  }

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Text(
          t,
          style: const TextStyle(
            color: _cianA,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  Widget _fila(String izq, String der, {Color color = Colors.white}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(izq, style: TextStyle(color: color, fontSize: 13)),
            ),
            Text(der, style: const TextStyle(color: _suaveA, fontSize: 12)),
          ],
        ),
      );

  Widget _nota(String t, Color c) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(t, style: TextStyle(color: c, fontSize: 13)),
      );

  List<Widget> _bateador(Map<String, dynamic> d) {
    final ab = _i(d['ab']);
    final h = _i(d['h']);
    final pa = _i(d['pa']);
    final tipos = (d['tipos'] as List).cast<Map<String, dynamic>>();
    final manos = (d['manos'] as List).cast<Map<String, dynamic>>();

    final hijos = <Widget>[
      Text(
        '${_i(d['juegos'])} juegos | $pa turnos | AVG ${_avg(h, ab)} ($h-$ab)',
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      const SizedBox(height: 4),
      Text(
        '2B ${_i(d['2b'])} | 3B ${_i(d['3b'])} | HR ${_i(d['hr'])} | '
        'K ${_i(d['k'])} (${_pct(_i(d['k']), pa)}) | BB ${_i(d['bb'])}',
        style: const TextStyle(color: _suaveA, fontSize: 12),
      ),
    ];

    final conMuestra = tipos.where((t) => _i(t['ab']) >= 3).toList();
    if (conMuestra.length >= 2) {
      final ordenados = [...conMuestra]..sort((a, c) {
          final pa1 = _i(a['h']) / _i(a['ab']);
          final pc = _i(c['h']) / _i(c['ab']);
          return pc.compareTo(pa1);
        });
      final mejor = ordenados.first;
      final peor = ordenados.last;
      hijos.add(_nota(
        'Le hace dano: ${mejor['tipo']} (${_avg(_i(mejor['h']), _i(mejor['ab']))})',
        _naranjaA,
      ));
      hijos.add(_nota(
        'Lo domina: ${peor['tipo']} (${_avg(_i(peor['h']), _i(peor['ab']))}, '
        '${_i(peor['k'])} K)',
        _cianA,
      ));
    }

    if (tipos.isNotEmpty) {
      hijos.add(_titulo('Por tipo de pitcheo (con que cerro el turno)'));
      for (final t in tipos) {
        hijos.add(_fila(
          '${t['tipo']}',
          'AB ${_i(t['ab'])} | H ${_i(t['h'])} | AVG ${_avg(_i(t['h']), _i(t['ab']))} | K ${_i(t['k'])}',
        ));
      }
    }
    if (manos.isNotEmpty) {
      hijos.add(_titulo('Segun la mano del lanzador'));
      for (final m in manos) {
        hijos.add(_fila(
          _mano('${m['mano']}', lanzador: false),
          'AB ${_i(m['ab'])} | H ${_i(m['h'])} | AVG ${_avg(_i(m['h']), _i(m['ab']))} | K ${_i(m['k'])}',
        ));
      }
    }
    return hijos;
  }

  List<Widget> _lanzador(Map<String, dynamic> d) {
    final n = _i(d['n']);
    final tipos = (d['tipos'] as List).cast<Map<String, dynamic>>();
    final manos = (d['manos'] as List).cast<Map<String, dynamic>>();

    final hijos = <Widget>[
      Text(
        '${_i(d['juegos'])} juegos | $n lanzamientos | strikes ${_pct(_i(d['st']), n)}',
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      const SizedBox(height: 4),
      Text(
        'H ${_i(d['h'])} | K ${_i(d['k'])} | BB ${_i(d['bb'])}',
        style: const TextStyle(color: _suaveA, fontSize: 12),
      ),
    ];

    final conMuestra = tipos.where((t) => _i(t['n']) >= 10).toList();
    if (conMuestra.length >= 2) {
      double puntos(Map<String, dynamic> t) =>
          (_i(t['k']) - _i(t['h'])) / _i(t['n']);
      final ordenados = [...conMuestra]
        ..sort((a, c) => puntos(c).compareTo(puntos(a)));
      final mejor = ordenados.first;
      final peor = ordenados.last;
      hijos.add(_nota(
        'Mas efectivo: ${mejor['tipo']} (${_i(mejor['k'])} K, ${_i(mejor['h'])} H)',
        _cianA,
      ));
      hijos.add(_nota(
        'Mas castigado: ${peor['tipo']} (${_i(peor['h'])} H, ${_i(peor['k'])} K)',
        _naranjaA,
      ));
    }

    if (tipos.isNotEmpty) {
      hijos.add(_titulo('Por tipo de pitcheo'));
      for (final t in tipos) {
        final nt = _i(t['n']);
        hijos.add(_fila(
          '${t['tipo']}',
          'Uso ${_pct(nt, n)} | Strike ${_pct(_i(t['st']), nt)} | H ${_i(t['h'])} | K ${_i(t['k'])}',
        ));
      }
    }
    if (manos.isNotEmpty) {
      hijos.add(_titulo('Segun la mano del bateador'));
      for (final m in manos) {
        final nm = _i(m['n']);
        hijos.add(_fila(
          _mano('${m['mano']}', lanzador: true),
          '$nm lanz. | Strike ${_pct(_i(m['st']), nm)} | H ${_i(m['h'])} | K ${_i(m['k'])}',
        ));
      }
    }
    return hijos;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _futuro,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final d = snap.data;
        final hayDatos = d != null &&
            _i(d['juegos']) > 0 &&
            (widget.esLanzador ? _i(d['n']) > 0 : _i(d['pa']) > 0);
        return Container(
          margin: const EdgeInsets.only(top: 16, bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _superficieA,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.insights, color: _cianA, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Analisis (todos sus juegos)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (!hayDatos)
                const Text(
                  'Todavia no hay juegos terminados con turnos registrados en el modo Juego en vivo.',
                  style: TextStyle(color: _suaveA, fontSize: 13),
                )
              else
                ...(widget.esLanzador ? _lanzador(d) : _bateador(d)),
            ],
          ),
        );
      },
    );
  }
}