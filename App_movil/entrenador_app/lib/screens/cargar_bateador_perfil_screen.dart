import 'package:flutter/material.dart';
import '../services/database_helper.dart';

class CargarBateadorPerfilScreen extends StatefulWidget {
  final int bateadorId;
  final int? temporadaInicial;

  const CargarBateadorPerfilScreen({
    super.key,
    required this.bateadorId,
    this.temporadaInicial,
  });

  @override
  State<CargarBateadorPerfilScreen> createState() => _CargarBateadorPerfilScreenState();
}

class _CargarBateadorPerfilScreenState extends State<CargarBateadorPerfilScreen> {
  final _formKey = GlobalKey<FormState>();
  final _temporadaCtrl = TextEditingController();

  final _hitsCtrl = TextEditingController(text: '0');
  final _doblesCtrl = TextEditingController(text: '0');
  final _triplesCtrl = TextEditingController(text: '0');
  final _homeRunsCtrl = TextEditingController(text: '0');
  final _impulsadasCtrl = TextEditingController(text: '0');
  final _anotadasCtrl = TextEditingController(text: '0');
  final _robadasCtrl = TextEditingController(text: '0');
  final _turnosCtrl = TextEditingController(text: '0');
  final _basesBolasCtrl = TextEditingController(text: '0');
  final _golpeCtrl = TextEditingController(text: '0');
  final _sacrificioCtrl = TextEditingController(text: '0');

  bool _cargando = true;
  bool _cargandoTemporada = false;
  bool _existeTemporada = false;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _temporadaCtrl.text = (widget.temporadaInicial ?? DateTime.now().year).toString();
    _cargarExistente();
  }

  @override
  void dispose() {
    _hitsCtrl.dispose();
    _temporadaCtrl.dispose();
    _doblesCtrl.dispose();
    _triplesCtrl.dispose();
    _homeRunsCtrl.dispose();
    _impulsadasCtrl.dispose();
    _anotadasCtrl.dispose();
    _robadasCtrl.dispose();
    _turnosCtrl.dispose();
    _basesBolasCtrl.dispose();
    _golpeCtrl.dispose();
    _sacrificioCtrl.dispose();
    super.dispose();
  }

  String _texto(Object? valor) => valor == null ? '0' : valor.toString();

  Future<void> _cargarExistente() async {
    final temporada = int.tryParse(_temporadaCtrl.text.trim());
    if (temporada == null) {
      if (mounted) setState(() => _cargando = false);
      return;
    }
    if (!_cargando) setState(() => _cargandoTemporada = true);
    try {
      final existente = await DatabaseHelper.instance.obtenerBateadorPerfil(
        widget.bateadorId,
        temporada: temporada,
      );
      if (existente == null) {
        _existeTemporada = false;
        for (final c in [
          _hitsCtrl,
          _doblesCtrl,
          _triplesCtrl,
          _homeRunsCtrl,
          _impulsadasCtrl,
          _anotadasCtrl,
          _robadasCtrl,
          _turnosCtrl,
          _basesBolasCtrl,
          _golpeCtrl,
          _sacrificioCtrl,
        ]) {
          c.text = '0';
        }
      } else {
        _existeTemporada = true;
        _hitsCtrl.text = _texto(existente.hits);
        _doblesCtrl.text = _texto(existente.dobles);
        _triplesCtrl.text = _texto(existente.triples);
        _homeRunsCtrl.text = _texto(existente.homeRuns);
        _impulsadasCtrl.text = _texto(existente.carrerasImpulsadas);
        _anotadasCtrl.text = _texto(existente.carrerasAnotadas);
        _robadasCtrl.text = _texto(existente.basesRobadas);
        _turnosCtrl.text = _texto(existente.turnosAlBate);
        _basesBolasCtrl.text = _texto(existente.basesPorBolas);
        _golpeCtrl.text = _texto(existente.golpePorLanzador);
        _sacrificioCtrl.text = _texto(existente.elevadoSacrificio);
      }
    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
          _cargandoTemporada = false;
        });
      }
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    await DatabaseHelper.instance.guardarBateadorPerfil(
      bateadorId: widget.bateadorId,
      temporada: int.parse(_temporadaCtrl.text.trim()),
      hits: int.parse(_hitsCtrl.text.trim()),
      dobles: int.parse(_doblesCtrl.text.trim()),
      triples: int.parse(_triplesCtrl.text.trim()),
      homeRuns: int.parse(_homeRunsCtrl.text.trim()),
      carrerasImpulsadas: int.parse(_impulsadasCtrl.text.trim()),
      carrerasAnotadas: int.parse(_anotadasCtrl.text.trim()),
      basesRobadas: int.parse(_robadasCtrl.text.trim()),
      turnosAlBate: int.parse(_turnosCtrl.text.trim()),
      basesPorBolas: int.parse(_basesBolasCtrl.text.trim()),
      golpePorLanzador: int.parse(_golpeCtrl.text.trim()),
      elevadoSacrificio: int.parse(_sacrificioCtrl.text.trim()),
    );

    if (!mounted) return;
    setState(() => _guardando = false);
    Navigator.pop(context, int.parse(_temporadaCtrl.text.trim()));
  }

  String? _validarEntero(String? valor) {
    if (valor == null || valor.trim().isEmpty) return 'Requerido';
    if (int.tryParse(valor.trim()) == null) return 'Debe ser un numero entero';
    return null;
  }

  Widget _campoEntero(String etiqueta, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: etiqueta,
          border: const OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
        validator: _validarEntero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Estadisticas del bateador')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'El promedio (AVG), OBP, SLG y OPS se calculan automaticamente a partir de estos datos.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
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
                            onPressed: _cargandoTemporada ? null : _cargarExistente,
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
                    if (_existeTemporada)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Ya existe una temporada guardada con este año. Se actualizara al guardar.',
                          style: TextStyle(color: Colors.orange, fontStyle: FontStyle.italic),
                        ),
                      ),
                    const SizedBox(height: 8),
                    _campoEntero('Hits', _hitsCtrl),
                    _campoEntero('Dobles (2B)', _doblesCtrl),
                    _campoEntero('Triples (3B)', _triplesCtrl),
                    _campoEntero('Home runs', _homeRunsCtrl),
                    _campoEntero('Carreras impulsadas', _impulsadasCtrl),
                    _campoEntero('Carreras anotadas', _anotadasCtrl),
                    _campoEntero('Bases robadas', _robadasCtrl),
                    const SizedBox(height: 8),
                    const Text('Para calcular AVG, OBP y OPS', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _campoEntero('Turnos al bate (AB)', _turnosCtrl),
                    _campoEntero('Bases por bolas (BB)', _basesBolasCtrl),
                    _campoEntero('Golpeado por lanzador (HBP)', _golpeCtrl),
                    _campoEntero('Elevados de sacrificio (SF)', _sacrificioCtrl),
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
