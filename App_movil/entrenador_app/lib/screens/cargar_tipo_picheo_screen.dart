import 'package:flutter/material.dart';
import '../models/lanzador_tipo_picheo.dart';
import '../services/database_helper.dart';

class CargarTipoPicheoScreen extends StatefulWidget {
  final int lanzadorId;
  final LanzadorTipoPicheo? existente;

  const CargarTipoPicheoScreen({
    super.key,
    required this.lanzadorId,
    this.existente,
  });

  @override
  State<CargarTipoPicheoScreen> createState() => _CargarTipoPicheoScreenState();
}

class _CargarTipoPicheoScreenState extends State<CargarTipoPicheoScreen> {
  static const _valorNuevo = -1;

  final _formKey = GlobalKey<FormState>();
  final _nombreNuevoCtrl = TextEditingController();
  final _frecuenciaCtrl = TextEditingController();
  final _velocidadPromedioCtrl = TextEditingController();
  final _velocidadMaxCtrl = TextEditingController();

  List<Map<String, dynamic>> _catalogo = [];
  int? _tipoSeleccionado;
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existente;
    if (e != null) {
      _frecuenciaCtrl.text = e.frecuencia?.toString() ?? '';
      _velocidadPromedioCtrl.text = e.velocidadPromedio?.toString() ?? '';
      _velocidadMaxCtrl.text = e.velocidadMax?.toString() ?? '';
    }
    _cargarCatalogo();
  }

  @override
  void dispose() {
    _nombreNuevoCtrl.dispose();
    _frecuenciaCtrl.dispose();
    _velocidadPromedioCtrl.dispose();
    _velocidadMaxCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarCatalogo() async {
    final catalogo = await DatabaseHelper.instance.obtenerCatalogoTiposLanzamiento();
    setState(() {
      _catalogo = catalogo;
      final e = widget.existente;
      if (e != null) {
        _tipoSeleccionado = e.tipoLanzamientoId;
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

    final frecuencia =
        _frecuenciaCtrl.text.trim().isEmpty ? null : double.tryParse(_frecuenciaCtrl.text.trim());
    final velocidadPromedio = _velocidadPromedioCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(_velocidadPromedioCtrl.text.trim());
    final velocidadMax =
        _velocidadMaxCtrl.text.trim().isEmpty ? null : double.tryParse(_velocidadMaxCtrl.text.trim());

    await DatabaseHelper.instance.guardarLanzadorTipoPicheo(
      id: widget.existente?.id,
      lanzadorId: widget.lanzadorId,
      tipoLanzamientoId: tipoLanzamientoId,
      frecuencia: frecuencia,
      velocidadPromedio: velocidadPromedio,
      velocidadMax: velocidadMax,
    );

    if (!mounted) return;
    setState(() => _guardando = false);
    Navigator.pop(context);
  }

  Future<void> _borrar() async {
    final id = widget.existente?.id;
    if (id == null) return;
    await DatabaseHelper.instance.borrarLanzadorTipoPicheo(id);
    if (!mounted) return;
    Navigator.pop(context);
  }

  String? _validarDecimalOpcional(String? valor) {
    if (valor == null || valor.trim().isEmpty) return null;
    if (double.tryParse(valor.trim()) == null) return 'Debe ser un numero';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existente == null ? 'Agregar tipo de lanzamiento' : 'Editar tipo de lanzamiento'),
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
                      controller: _frecuenciaCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Frecuencia (%)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: _validarDecimalOpcional,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _velocidadPromedioCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Velocidad promedio (mph)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: _validarDecimalOpcional,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _velocidadMaxCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Velocidad maxima (mph)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: _validarDecimalOpcional,
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

