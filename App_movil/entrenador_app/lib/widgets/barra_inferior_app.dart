import 'package:flutter/material.dart';

import '../screens/analisis_screen.dart';
import '../screens/debug_tablas_screen.dart';

const Color _barra = Color(0xFF07182F);
const Color _barraActivo = Color(0xFFE0B04A);
const Color _barraInactivo = Color(0xFF6FA0E8);

enum SeccionBarra { inicio, equipo, analisis, ajustes }

/// Barra inferior de la app (Inicio / Equipo / Analisis / Ajustes) para usarla
/// en pantallas secundarias, con la misma apariencia que la del menu principal.
class BarraInferiorApp extends StatelessWidget {
  final SeccionBarra activa;

  /// Si se da, reemplaza la accion por defecto del boton Equipo.
  final VoidCallback? alTocarEquipo;

  const BarraInferiorApp({super.key, required this.activa, this.alTocarEquipo});

  void _irInicio(BuildContext context) {
    Navigator.of(context).popUntil((ruta) => ruta.isFirst);
  }

  void _irEquipo(BuildContext context) {
    // Las pantallas de jugador se abren desde el roster: volver a el.
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  void _irAnalisis(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AnalisisScreen()),
    );
  }

  void _abrirAjustes(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.storage_outlined, color: Color(0xFF0F172A)),
              title: const Text('Tablas de la base de datos'),
              subtitle: const Text('Revisar los datos guardados'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DebugTablasScreen()),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _item(IconData icono, String texto, SeccionBarra seccion, VoidCallback onTap) {
    final color = seccion == activa ? _barraActivo : _barraInactivo;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 26, color: color),
            const SizedBox(height: 2),
            Text(
              texto,
              style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _barra,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _item(Icons.home_outlined, 'Inicio', SeccionBarra.inicio, () => _irInicio(context)),
              _item(Icons.groups_outlined, 'Equipo', SeccionBarra.equipo, alTocarEquipo ?? () => _irEquipo(context)),
              _item(Icons.bar_chart, 'Análisis', SeccionBarra.analisis, () => _irAnalisis(context)),
              _item(Icons.settings_outlined, 'Ajustes', SeccionBarra.ajustes, () => _abrirAjustes(context)),
            ],
          ),
        ),
      ),
    );
  }
}
