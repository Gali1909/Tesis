import 'package:flutter/material.dart';
import '../services/database_helper.dart';

class CargarVulnerabilidadScreen extends StatefulWidget {
  final int bateadorId;
  final Map<String, dynamic>? existente;

  const CargarVulnerabilidadScreen({
    super.key,
    required this.bateadorId,
    this.existente,
  });

  @override
  State<CargarVulnerabilidadScreen> createState() => _CargarVulnerabilidadScreenState();
}

class _CargarVulnerabilidadScreenState extends State<CargarVulnerabilidadScreen> {
  static const _valorNuevo = -1;

  final _formKey = GlobalKey<FormState>();
  final _nombreNuevoCtrl = TextEditingController();
  final _nivelCtrl = TextEditingController();

  List<Map<String, dynamic>> _catalogo = [];
  int? _tipoSeleccionado;
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existente;
    if (e != null) {
      _nivelCtrl.text = (e['nivel_efectividad_contra'] as num?)?.toString() ?? '';
    }
    _cargarCatalogo();
  }

  @override
  void dispose() {
    _nombreNuevoCtrl.dispose();
    _nivelCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarCatalogo() async {
    final catalogo = await DatabaseHelper.instance.obtenerCatalogoTiposLanzamiento();
    setState(() {
      _catalogo = catalogo;
      final e = widget.existente;
      if (e != null) {
        _tipoSeleccionado = e['tipo_lanzamiento_id'] as int;
      }
      _cargando = false;
    });
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    int tipoLanzamientoId;
    if (_tipoSeleccionado == _valorNuevo) {
      tipoLanzamientoId =
          await DatabaseHelper.instance.obtenerOCrearTipoLanzamiento(_nombreNuevoCtrl.text.trim());
    } else {
      tipoLanzamientoId = _tipoSeleccionado!;
    }

    await DatabaseHelper.instance.guardarBateadorVulnerabilidad(
      id: widget.existente?['id'] as int?,
      bateadorId: widget.bateadorId,
      tipoLanzamientoId: tipoLanzamientoId,
      nivelEfectividadContra: double.parse(_nivelCtrl.text.trim()),
    );

    if (!mounted) return;
    setState(() => _guardando = false);
    Navigator.pop(context);
  }

  Future<void> _borrar() async {
    final id = widget.existente?['id'] as int?;
    if (id == null) return;
    await DatabaseHelper.instance.borrarBateadorVulnerabilidad(id);
    if (!mounted) return;
    Navigator.pop(context);
  }

  String? _validarNivel(String? valor) {
    if (valor == null || valor.trim().isEmpty) return 'Requerido';
    final n = double.tryParse(valor.trim());
    if (n == null) return 'Debe ser un numero';
    if (n < 0 || n > 1) return 'Usa formato decimal, ej. 0.250';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existente == null ? 'Agregar vulnerabilidad' : 'Editar vulnerabilidad'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: _tipoSeleccionado,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de lanzamiento',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        ..._catalogo.map((t) => DropdownMenuItem<int>(
                              value: t['tipo_lanzamiento_id'] as int,
                              child: Text(t['nombre'] as String),
                            )),
                        const DropdownMenuItem<int>(
                          value: _valorNuevo,
                          child: Text('+ Agregar otro lanzamiento...'),
                        ),
                      ],
                      onChanged: (valor) => setState(() => _tipoSeleccionado = valor),
                      validator: (valor) => valor == null ? 'Selecciona un tipo' : null,
                    ),
                    if (_tipoSeleccionado == _valorNuevo)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextFormField(
                          controller: _nombreNuevoCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Nombre del nuevo tipo',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            if (_tipoSeleccionado != _valorNuevo) return null;
                            if (v == null || v.trim().isEmpty) return 'Requerido';
                            return null;
                          },
                        ),
                      ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nivelCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Efectividad del bateador contra este lanzamiento',
                        helperText: 'Ej. 0.250. Mientras menor sea, mas vulnerable es.',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: _validarNivel,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _guardando ? null : _guardar,
                      child: _guardando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Guardar'),
                    ),
                    if (widget.existente != null) ...[
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _guardando ? null : _borrar,
                        child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
