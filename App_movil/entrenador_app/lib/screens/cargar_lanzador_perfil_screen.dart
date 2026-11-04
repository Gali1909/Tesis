import 'package:flutter/material.dart';
import '../models/lanzador_perfil.dart';
import '../services/database_helper.dart';

class CargarLanzadorPerfilScreen extends StatefulWidget {
  final int lanzadorId;
  final int? temporadaInicial;

  const CargarLanzadorPerfilScreen({
    super.key,
    required this.lanzadorId,
    this.temporadaInicial,
  });

  @override
  State<CargarLanzadorPerfilScreen> createState() => _CargarLanzadorPerfilScreenState();
}

class _CargarLanzadorPerfilScreenState extends State<CargarLanzadorPerfilScreen> {
  final _formKey = GlobalKey<FormState>();

  final _temporadaCtrl = TextEditingController();
  final _juegosGanadosCtrl = TextEditingController(text: '0');
  final _juegosPerdidosCtrl = TextEditingController(text: '0');
  final _aperturasCtrl = TextEditingController(text: '0');
  final _salvadosCtrl = TextEditingController(text: '0');
  final _juegosLanzadosCtrl = TextEditingController(text: '0');
  final _inningsLanzadosCtrl = TextEditingController(text: '0');
  final _ponchesCtrl = TextEditingController(text: '0');
  final _basesPorBolasCtrl = TextEditingController(text: '0');
  final _hitsPermitidosCtrl = TextEditingController(text: '0');
  final _carrerasLimpiasCtrl = TextEditingController(text: '0');

  int? _idExistente;
  bool _cargandoTemporada = false;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _temporadaCtrl.text = (widget.temporadaInicial ?? DateTime.now().year).toString();
    _cargarTemporada();
  }

  @override
  void dispose() {
    _temporadaCtrl.dispose();
    _juegosGanadosCtrl.dispose();
    _juegosPerdidosCtrl.dispose();
    _aperturasCtrl.dispose();
    _salvadosCtrl.dispose();
    _juegosLanzadosCtrl.dispose();
    _inningsLanzadosCtrl.dispose();
    _ponchesCtrl.dispose();
    _basesPorBolasCtrl.dispose();
    _hitsPermitidosCtrl.dispose();
    _carrerasLimpiasCtrl.dispose();
    super.dispose();
  }

  void _resetCampos() {
    _juegosGanadosCtrl.text = '0';
    _juegosPerdidosCtrl.text = '0';
    _aperturasCtrl.text = '0';
    _salvadosCtrl.text = '0';
    _juegosLanzadosCtrl.text = '0';
    _inningsLanzadosCtrl.text = '0';
    _ponchesCtrl.text = '0';
    _basesPorBolasCtrl.text = '0';
    _hitsPermitidosCtrl.text = '0';
    _carrerasLimpiasCtrl.text = '0';
  }

  Future<void> _cargarTemporada() async {
    final temporada = int.tryParse(_temporadaCtrl.text.trim());
    if (temporada == null) return;

    setState(() => _cargandoTemporada = true);

    final existente = await DatabaseHelper.instance.obtenerLanzadorPerfil(
      widget.lanzadorId,
      temporada,
    );

    if (existente == null) {
      _idExistente = null;
      _resetCampos();
    } else {
      _idExistente = existente.id;
      _juegosGanadosCtrl.text = existente.juegosGanados.toString();
      _juegosPerdidosCtrl.text = existente.juegosPerdidos.toString();
      _aperturasCtrl.text = existente.aperturas.toString();
      _salvadosCtrl.text = existente.salvados.toString();
      _juegosLanzadosCtrl.text = existente.juegosLanzados.toString();
      _inningsLanzadosCtrl.text = existente.inningsLanzados.toString();
      _ponchesCtrl.text = existente.ponches.toString();
      _basesPorBolasCtrl.text = existente.basesPorBolas.toString();
      _hitsPermitidosCtrl.text = existente.hitsPermitidos.toString();
      _carrerasLimpiasCtrl.text = existente.carrerasLimpias.toString();
    }

    setState(() => _cargandoTemporada = false);
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    final perfil = LanzadorPerfil(
      id: _idExistente,
      lanzadorId: widget.lanzadorId,
      temporada: int.parse(_temporadaCtrl.text.trim()),
      juegosGanados: int.parse(_juegosGanadosCtrl.text.trim()),
      juegosPerdidos: int.parse(_juegosPerdidosCtrl.text.trim()),
      aperturas: int.parse(_aperturasCtrl.text.trim()),
      salvados: int.parse(_salvadosCtrl.text.trim()),
      juegosLanzados: int.parse(_juegosLanzadosCtrl.text.trim()),
      inningsLanzados: double.parse(_inningsLanzadosCtrl.text.trim()),
      ponches: int.parse(_ponchesCtrl.text.trim()),
      basesPorBolas: int.parse(_basesPorBolasCtrl.text.trim()),
      hitsPermitidos: int.parse(_hitsPermitidosCtrl.text.trim()),
      carrerasLimpias: int.parse(_carrerasLimpiasCtrl.text.trim()),
    );

    await DatabaseHelper.instance.guardarLanzadorPerfil(perfil);

    if (!mounted) return;
    setState(() => _guardando = false);
    Navigator.pop(context);
  }

  String? _validarEntero(String? valor) {
    if (valor == null || valor.trim().isEmpty) return 'Requerido';
    if (int.tryParse(valor.trim()) == null) return 'Debe ser un numero entero';
    return null;
  }

  String? _validarDecimal(String? valor) {
    if (valor == null || valor.trim().isEmpty) return 'Requerido';
    if (double.tryParse(valor.trim()) == null) return 'Debe ser un numero';
    return null;
  }

  Widget _campo(String etiqueta, TextEditingController controller, {bool decimal = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: etiqueta,
          border: const OutlineInputBorder(),
        ),
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        validator: decimal ? _validarDecimal : _validarEntero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cargar temporada de lanzador')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _temporadaCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Temporada (año)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: _validarEntero,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: ElevatedButton(
                      onPressed: _cargandoTemporada ? null : _cargarTemporada,
                      child: _cargandoTemporada
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Cargar'),
                    ),
                  ),
                ],
              ),
              if (_idExistente != null)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Ya existe una temporada guardada con este año. Se actualizara al guardar.',
                    style: TextStyle(color: Colors.orange, fontStyle: FontStyle.italic),
                  ),
                ),
              const SizedBox(height: 8),
              _campo('Juegos ganados', _juegosGanadosCtrl),
              _campo('Juegos perdidos', _juegosPerdidosCtrl),
              _campo('Aperturas', _aperturasCtrl),
              _campo('Salvados', _salvadosCtrl),
              _campo('Juegos lanzados', _juegosLanzadosCtrl),
              _campo('Innings lanzados', _inningsLanzadosCtrl, decimal: true),
              _campo('Ponches', _ponchesCtrl),
              _campo('Bases por bolas', _basesPorBolasCtrl),
              _campo('Hits permitidos', _hitsPermitidosCtrl),
              _campo('Carreras limpias', _carrerasLimpiasCtrl),
              const SizedBox(height: 16),
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
            ],
          ),
        ),
      ),
    );
  }
}