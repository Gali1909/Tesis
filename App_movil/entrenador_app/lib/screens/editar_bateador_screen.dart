import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/jugador.dart';
import '../services/database_helper.dart';

class EditarBateadorScreen extends StatefulWidget {
  final Jugador jugador;

  const EditarBateadorScreen({super.key, required this.jugador});

  @override
  State<EditarBateadorScreen> createState() => _EditarBateadorScreenState();
}

class _EditarBateadorScreenState extends State<EditarBateadorScreen> {
  static const _posicionesDisponibles = ['P', 'C', '1B', '2B', '3B', 'SS', 'LF', 'CF', 'RF'];
  static const _manosValidas = ['derecha', 'izquierda', 'ambos'];

  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _numeroCtrl = TextEditingController();

  String? _manoBateo;
  String? _fotoPath;
  Set<String> _posicionesSeleccionadas = {};
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _nombreCtrl.text = widget.jugador.nombre;
    _numeroCtrl.text = widget.jugador.numero?.toString() ?? '';
    final mano = widget.jugador.manoBateo;
    _manoBateo = (mano != null && _manosValidas.contains(mano)) ? mano : null;
    _fotoPath = widget.jugador.foto;
    _cargarPosiciones();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _numeroCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarPosiciones() async {
    final posiciones = await DatabaseHelper.instance.obtenerPosiciones(widget.jugador.jugadorId!);
    setState(() {
      _posicionesSeleccionadas = posiciones.map((p) => p.posicion).toSet();
      _cargando = false;
    });
  }

  Future<void> _elegirFoto() async {
    final picker = ImagePicker();
    final imagen = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (imagen != null) {
      setState(() => _fotoPath = imagen.path);
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    final id = widget.jugador.jugadorId!;
    final numero = _numeroCtrl.text.trim().isEmpty ? null : int.tryParse(_numeroCtrl.text.trim());

    await DatabaseHelper.instance.actualizarDatosBateador(
      jugadorId: id,
      nombre: _nombreCtrl.text.trim(),
      numero: numero,
      manoBateo: _manoBateo,
      foto: _fotoPath,
    );

    await DatabaseHelper.instance.borrarPosicionesYRoles(id);
    for (final pos in _posicionesSeleccionadas) {
      await DatabaseHelper.instance.agregarPosicionTexto(id, pos);
    }

    if (!mounted) return;
    setState(() => _guardando = false);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final tieneFoto = _fotoPath != null && _fotoPath!.isNotEmpty && File(_fotoPath!).existsSync();

    return Scaffold(
      appBar: AppBar(title: const Text('Editar perfil')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    Center(
                      child: GestureDetector(
                        onTap: _elegirFoto,
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 48,
                              backgroundColor: Colors.grey.shade200,
                              backgroundImage: tieneFoto ? FileImage(File(_fotoPath!)) : null,
                              child: tieneFoto ? null : const Icon(Icons.person, size: 48, color: Colors.grey),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Colors.blueAccent,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _nombreCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _numeroCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Numero',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _manoBateo,
                      decoration: const InputDecoration(
                        labelText: 'Mano de bateo',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'derecha', child: Text('Derecha')),
                        DropdownMenuItem(value: 'izquierda', child: Text('Izquierda')),
                        DropdownMenuItem(value: 'ambos', child: Text('Ambos')),
                      ],
                      onChanged: (valor) => setState(() => _manoBateo = valor),
                    ),
                    const SizedBox(height: 16),
                    const Text('Posiciones', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: _posicionesDisponibles.map((pos) {
                        return FilterChip(
                          label: Text(pos),
                          selected: _posicionesSeleccionadas.contains(pos),
                          onSelected: (marcado) {
                            setState(() {
                              if (marcado) {
                                _posicionesSeleccionadas.add(pos);
                              } else {
                                _posicionesSeleccionadas.remove(pos);
                              }
                            });
                          },
                        );
                      }).toList(),
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
                  ],
                ),
              ),
            ),
    );
  }
}
