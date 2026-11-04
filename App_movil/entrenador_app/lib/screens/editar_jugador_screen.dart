import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/jugador.dart';
import '../services/database_helper.dart';

class EditarJugadorScreen extends StatefulWidget {
  final Jugador jugador;

  const EditarJugadorScreen({super.key, required this.jugador});

  @override
  State<EditarJugadorScreen> createState() => _EditarJugadorScreenState();
}

class _EditarJugadorScreenState extends State<EditarJugadorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _numeroCtrl = TextEditingController();

  String? _manoLanzamiento;
  String? _fotoPath;
  Set<String> _rolesSeleccionados = {};
  bool _cargando = true;
  bool _guardando = false;

  static const _rolesDisponibles = ['abridor', 'relevista', 'cerrador'];

  @override
  void initState() {
    super.initState();
    _nombreCtrl.text = widget.jugador.nombre;
    _numeroCtrl.text = widget.jugador.numero?.toString() ?? '';
    _manoLanzamiento = widget.jugador.manoLanzamiento;
    _fotoPath = widget.jugador.foto;
    _cargarRoles();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _numeroCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarRoles() async {
    if (widget.jugador.rol == 'lanzador') {
      final roles = await DatabaseHelper.instance.obtenerRolesLanzador(widget.jugador.jugadorId!);
      setState(() {
        _rolesSeleccionados = roles.map((r) => r.rolLanzador).toSet();
        _cargando = false;
      });
    } else {
      setState(() => _cargando = false);
    }
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

    await DatabaseHelper.instance.actualizarDatosBasicosJugador(
      jugadorId: id,
      nombre: _nombreCtrl.text.trim(),
      numero: numero,
      manoLanzamiento: _manoLanzamiento,
      foto: _fotoPath,
    );

    if (widget.jugador.rol == 'lanzador') {
      await DatabaseHelper.instance.borrarPosicionesYRoles(id);
      for (final rol in _rolesSeleccionados) {
        await DatabaseHelper.instance.agregarRolLanzadorTexto(id, rol);
      }
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
                    if (widget.jugador.rol == 'lanzador') ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _manoLanzamiento,
                        decoration: const InputDecoration(
                          labelText: 'Mano de lanzamiento',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'zurdo', child: Text('Zurdo')),
                          DropdownMenuItem(value: 'derecho', child: Text('Derecho')),
                        ],
                        onChanged: (valor) => setState(() => _manoLanzamiento = valor),
                      ),
                      const SizedBox(height: 16),
                      const Text('Posicion (rol)', style: TextStyle(fontWeight: FontWeight.bold)),
                      ..._rolesDisponibles.map((rol) => CheckboxListTile(
                            value: _rolesSeleccionados.contains(rol),
                            title: Text(rol[0].toUpperCase() + rol.substring(1)),
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (marcado) {
                              setState(() {
                                if (marcado == true) {
                                  _rolesSeleccionados.add(rol);
                                } else {
                                  _rolesSeleccionados.remove(rol);
                                }
                              });
                            },
                          )),
                    ],
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

