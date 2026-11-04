import 'package:flutter/material.dart';

import '../services/database_helper.dart';

/// Tarjeta "Equipos anteriores": equipos por los que ya paso el jugador,
/// con fechas y motivo de salida. Si no tiene ninguno, no se muestra.
class EquiposAnterioresCard extends StatefulWidget {
  final int jugadorId;

  const EquiposAnterioresCard({super.key, required this.jugadorId});

  @override
  State<EquiposAnterioresCard> createState() => _EquiposAnterioresCardState();
}

class _EquiposAnterioresCardState extends State<EquiposAnterioresCard> {
  late final Future<List<Map<String, dynamic>>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = DatabaseHelper.instance.historialEquiposJugador(widget.jugadorId);
  }

  String _fecha(dynamic iso) {
    final texto = iso?.toString() ?? '';
    final partes = texto.split('-');
    if (partes.length != 3) return texto.isEmpty ? '?' : texto;
    return '${partes[2]}/${partes[1]}/${partes[0]}';
  }

  Widget _fila(Map<String, dynamic> m) {
    final libre = m['motivo_salida'] == 'libre';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            libre ? Icons.person_off_outlined : Icons.swap_horiz,
            color: Colors.grey.shade600,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (m['equipo_nombre'] ?? 'Equipo eliminado').toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_fecha(m['fecha_inicio'])} - ${_fecha(m['fecha_fin'])}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            libre ? 'Libre' : 'Cambiado',
            style: TextStyle(
              color: libre ? const Color(0xFFE36F10) : const Color(0xFF0ABDCF),
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _futuro,
      builder: (context, snapshot) {
        final anteriores = (snapshot.data ?? [])
            .where((m) => m['fecha_fin'] != null)
            .toList();
        if (anteriores.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'EQUIPOS ANTERIORES',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                ...anteriores.map(_fila),
              ],
            ),
          ),
        );
      },
    );
  }
}
