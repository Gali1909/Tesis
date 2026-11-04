import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import 'resultado_juego_seccion.dart';

const Color _colorFondoOscuro = Color(0xFF14171C);
const Color _colorAcento = Color(0xFF0ABDCF);

/// Convierte "6", "6.1" o "6.2" a outs (19 para 6.1). Devuelve null si es invalido.
int? outsDesdeInnings(String texto) {
  final t = texto.trim().replaceAll(',', '.');
  final m = RegExp(r'^(\d+)(?:\.([0-2]))?$').firstMatch(t);
  if (m == null) return null;
  return int.parse(m.group(1)!) * 3 + int.parse(m.group(2) ?? '0');
}

class RegistrarSalidaScreen extends StatefulWidget {
  final int lanzadorId;
  final String nombreLanzador;

  const RegistrarSalidaScreen({
    super.key,
    required this.lanzadorId,
    required this.nombreLanzador,
  });

  @override
  State<RegistrarSalidaScreen> createState() => _RegistrarSalidaScreenState();
}

class _RegistrarSalidaScreenState extends State<RegistrarSalidaScreen> {
  DateTime _fecha = DateTime.now();
  bool _guardando = false;
  final _resultado = ResultadoJuegoController();

  static const List<List<String>> _campos = [
    ['innings', 'Innings (ej. 6.1 = 6 y 1/3)'],
    ['picheos', 'Picheos lanzados'],
    ['carreras', 'Carreras permitidas'],
    ['limpias', 'Carreras limpias'],
    ['hits', 'Hits permitidos'],
    ['ponches', 'Ponches (K)'],
    ['bb', 'Bases por bolas (BB)'],
  ];

  late final Map<String, TextEditingController> _ctrl = {
    for (final c in _campos) c[0]: TextEditingController(),
  };

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    _resultado.dispose();
    super.dispose();
  }

  String _fechaIso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fechaVista(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _elegirFecha() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (elegida != null) setState(() => _fecha = elegida);
  }

  void _mensaje(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  int? _entero(String clave) {
    final txt = _ctrl[clave]!.text.trim();
    if (txt.isEmpty) return 0;
    final n = int.tryParse(txt);
    return (n == null || n < 0) ? null : n;
  }

  Future<void> _guardar() async {
    final outs = outsDesdeInnings(_ctrl['innings']!.text);
    if (outs == null) {
      _mensaje('Innings invalidos. Usa 6, 6.1 o 6.2 (solo .1 y .2 como fraccion).');
      return;
    }

    final v = <String, int>{};
    for (final c in _campos.skip(1)) {
      final n = _entero(c[0]);
      if (n == null) {
        _mensaje('"${c[1]}" debe ser un numero entero mayor o igual a 0.');
        return;
      }
      v[c[0]] = n;
    }

    if (outs == 0 && v['picheos']! == 0) {
      _mensaje('Ingresa los innings o los picheos lanzados.');
      return;
    }
    if (v['limpias']! > v['carreras']!) {
      _mensaje('Las carreras limpias no pueden superar las carreras permitidas.');
      return;
    }

    final errorResultado = _resultado.validar();
    if (errorResultado != null) {
      _mensaje(errorResultado);
      return;
    }

    setState(() => _guardando = true);
    try {
      await DatabaseHelper.instance.registrarSalidaLanzador(
        lanzadorId: widget.lanzadorId,
        fecha: _fechaIso(_fecha),
        equipoRivalId: _resultado.rivalId,
        carrerasPropias: _resultado.carrerasPropias,
        carrerasRival: _resultado.carrerasRival,
        outs: outs,
        picheos: v['picheos']!,
        carrerasPermitidas: v['carreras']!,
        carrerasLimpias: v['limpias']!,
        hitsPermitidos: v['hits']!,
        ponches: v['ponches']!,
        basesPorBolas: v['bb']!,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _mensaje(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _mensaje('No se pudo guardar la salida: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ancho = (MediaQuery.of(context).size.width - 16 * 2 - 12) / 2;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      appBar: AppBar(
        backgroundColor: _colorFondoOscuro,
        foregroundColor: Colors.white,
        title: const Text('REGISTRAR SALIDA'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.nombreLanzador,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _elegirFecha,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Fecha del juego',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_today),
                filled: true,
                fillColor: Colors.white,
              ),
              child: Text(_fechaVista(_fecha)),
            ),
          ),
          const SizedBox(height: 16),
          ResultadoJuegoSeccion(controller: _resultado),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final c in _campos)
                SizedBox(
                  width: c[0] == 'innings' ? double.infinity : ancho,
                  child: TextField(
                    controller: _ctrl[c[0]],
                    keyboardType: c[0] == 'innings'
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.number,
                    decoration: InputDecoration(
                      labelText: c[1],
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _colorAcento,
                foregroundColor: Colors.white,
              ),
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('GUARDAR SALIDA', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
