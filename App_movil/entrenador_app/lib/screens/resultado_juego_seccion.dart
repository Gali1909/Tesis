import 'package:flutter/material.dart';
import '../models/equipo.dart';
import '../services/database_helper.dart';

class ResultadoJuegoController {
  int? rivalId;
  final TextEditingController propias = TextEditingController();
  final TextEditingController rival = TextEditingController();

  int? get carrerasPropias => int.tryParse(propias.text.trim());
  int? get carrerasRival => int.tryParse(rival.text.trim());

  /// Devuelve null si todo esta bien; si no, el mensaje de error.
  String? validar() {
    final a = propias.text.trim();
    final b = rival.text.trim();
    if (a.isEmpty && b.isEmpty) return null;
    if (a.isEmpty || b.isEmpty) {
      return 'Completa las carreras de ambos equipos o deja las dos vacias.';
    }
    final x = int.tryParse(a);
    final y = int.tryParse(b);
    if (x == null || y == null || x < 0 || y < 0) {
      return 'El marcador debe tener enteros mayores o iguales a 0.';
    }
    return null;
  }

  void dispose() {
    propias.dispose();
    rival.dispose();
  }
}

class ResultadoJuegoSeccion extends StatefulWidget {
  final ResultadoJuegoController controller;

  const ResultadoJuegoSeccion({super.key, required this.controller});

  @override
  State<ResultadoJuegoSeccion> createState() => _ResultadoJuegoSeccionState();
}

class _ResultadoJuegoSeccionState extends State<ResultadoJuegoSeccion> {
  List<Equipo> _rivales = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final lista = await DatabaseHelper.instance.obtenerEquiposRivales();
    if (!mounted) return;
    setState(() => _rivales = lista);
  }

  InputDecoration _decoracion(String etiqueta) => InputDecoration(
        labelText: etiqueta,
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      );

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InputDecorator(
          decoration: _decoracion('Equipo rival (opcional)').copyWith(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              isExpanded: true,
              value: c.rivalId,
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Sin rival')),
                for (final e in _rivales)
                  DropdownMenuItem<int?>(value: e.equipoId, child: Text(e.nombre)),
              ],
              onChanged: (v) => setState(() => c.rivalId = v),
            ),
          ),
        ),
        if (_rivales.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4, left: 4),
            child: Text(
              'No hay equipos rivales cargados todavia.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: c.propias,
                keyboardType: TextInputType.number,
                decoration: _decoracion('Carreras propias'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: c.rival,
                keyboardType: TextInputType.number,
                decoration: _decoracion('Carreras del rival'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
