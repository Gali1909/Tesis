import 'package:flutter/material.dart';
import '../models/jugador.dart';
import '../models/jugador_posicion.dart';
import '../models/lanzador_rol.dart';
import '../services/database_helper.dart';

class AgregarJugadorScreen extends StatefulWidget {
  final int equipoId;
  final Jugador? jugadorExistente;
  final String rolInicial;

  const AgregarJugadorScreen({
    super.key,
    required this.equipoId,
    this.jugadorExistente,
    this.rolInicial = 'bateador',
  });

  @override
  State<AgregarJugadorScreen> createState() => _AgregarJugadorScreenState();
}

class _AgregarJugadorScreenState extends State<AgregarJugadorScreen> {
  final _nombreController = TextEditingController();
  final _numeroController = TextEditingController();

  String _rol = 'bateador'; // valor por defecto
  String? _manoBateo;
  String? _manoLanzamiento;

  bool get _esEdicion => widget.jugadorExistente != null;

  @override
  void initState() {
    super.initState();
    _rol = widget.rolInicial;
    final jugador = widget.jugadorExistente;
    if (jugador != null) {
      _nombreController.text = jugador.nombre;
      _numeroController.text = jugador.numero?.toString() ?? '';
      _rol = jugador.rol;
      _manoBateo = jugador.manoBateo;
      _manoLanzamiento = jugador.manoLanzamiento;
      _cargarPosicionesYRoles(jugador.jugadorId!);
    }
  }

  Future<void> _cargarPosicionesYRoles(int jugadorId) async {
    if (_rol == 'bateador') {
      final posiciones = await DatabaseHelper.instance.obtenerPosiciones(jugadorId);
      setState(() {
        _posicionesSeleccionadas.addAll(posiciones.map((p) => p.posicion));
      });
    } else {
      final roles = await DatabaseHelper.instance.obtenerRolesLanzador(jugadorId);
      setState(() {
        _rolesSeleccionados.addAll(roles.map((r) => r.rolLanzador));
      });
    }
  }

  final List<String> _posicionesDisponibles = [
    'P', 'C', '1B', '2B', '3B', 'SS', 'LF', 'CF', 'RF'
  ];
  final Set<String> _posicionesSeleccionadas = {};

  final List<String> _rolesDisponibles = ['abridor', 'relevista', 'cerrador'];
  final Set<String> _rolesSeleccionados = {};

   Future<void> _guardarJugador() async {
    if (_nombreController.text.trim().isEmpty) return;

    int jugadorId;

    if (_esEdicion) {
      jugadorId = widget.jugadorExistente!.jugadorId!;
      final jugadorActualizado = Jugador(
        jugadorId: jugadorId,
        equipoId: widget.equipoId,
        nombre: _nombreController.text.trim(),
        rol: _rol,
        manoBateo: _rol == 'bateador' ? _manoBateo : null,
        manoLanzamiento: _rol == 'lanzador' ? _manoLanzamiento : null,
        numero: int.tryParse(_numeroController.text),
      );
      await DatabaseHelper.instance.actualizarJugador(jugadorActualizado);
      await DatabaseHelper.instance.borrarPosicionesYRoles(jugadorId);
    } else {
      final nuevoJugador = Jugador(
        equipoId: widget.equipoId,
        nombre: _nombreController.text.trim(),
        rol: _rol,
        manoBateo: _rol == 'bateador' ? _manoBateo : null,
        manoLanzamiento: _rol == 'lanzador' ? _manoLanzamiento : null,
        numero: int.tryParse(_numeroController.text),
      );
      jugadorId = await DatabaseHelper.instance.crearJugador(nuevoJugador);
    }

    if (_rol == 'bateador') {
      for (final posicion in _posicionesSeleccionadas) {
        await DatabaseHelper.instance.agregarPosicion(
          JugadorPosicion(jugadorId: jugadorId, posicion: posicion),
        );
      }
    } else {
      for (final rolLanzador in _rolesSeleccionados) {
        await DatabaseHelper.instance.agregarRolLanzador(
          LanzadorRol(lanzadorId: jugadorId, rolLanzador: rolLanzador),
        );
      }
    }

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_esEdicion ? 'Editar Jugador' : 'Agregar Jugador')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: _nombreController,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            TextField(
              controller: _numeroController,
              decoration: const InputDecoration(labelText: 'Numero'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            const Text('Rol'),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'bateador', label: Text('Bateador')),
                ButtonSegment(value: 'lanzador', label: Text('Lanzador')),
              ],
              selected: {_rol},
              onSelectionChanged: (nuevoValor) {
                setState(() => _rol = nuevoValor.first);
              },
            ),
            const SizedBox(height: 16),
            if (_rol == 'bateador') ...[
              const Text('Mano de bateo'),
              DropdownButton<String>(
                value: _manoBateo,
                hint: const Text('Selecciona'),
                items: const [
                  DropdownMenuItem(value: 'derecha', child: Text('Derecha')),
                  DropdownMenuItem(value: 'izquierda', child: Text('Izquierda')),
                  DropdownMenuItem(value: 'ambos', child: Text('Ambos')),
                ],
                onChanged: (valor) => setState(() => _manoBateo = valor),
              ),
              const SizedBox(height: 16),
              const Text('Posiciones'),
              Wrap(
                spacing: 8,
                children: _posicionesDisponibles.map((posicion) {
                  final seleccionada = _posicionesSeleccionadas.contains(posicion);
                  return FilterChip(
                    label: Text(posicion),
                    selected: seleccionada,
                    onSelected: (valor) {
                      setState(() {
                        if (valor) {
                          _posicionesSeleccionadas.add(posicion);
                        } else {
                          _posicionesSeleccionadas.remove(posicion);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ] else ...[
              const Text('Mano de lanzamiento'),
              DropdownButton<String>(
                value: _manoLanzamiento,
                hint: const Text('Selecciona'),
                items: const [
                  DropdownMenuItem(value: 'zurdo', child: Text('Zurdo')),
                  DropdownMenuItem(value: 'derecho', child: Text('Derecho')),
                ],
                onChanged: (valor) => setState(() => _manoLanzamiento = valor),
              ),
              const SizedBox(height: 16),
              const Text('Rol de lanzador'),
              Wrap(
                spacing: 8,
                children: _rolesDisponibles.map((rolLanzador) {
                  final seleccionado = _rolesSeleccionados.contains(rolLanzador);
                  return FilterChip(
                    label: Text(rolLanzador),
                    selected: seleccionado,
                    onSelected: (valor) {
                      setState(() {
                        if (valor) {
                          _rolesSeleccionados.add(rolLanzador);
                        } else {
                          _rolesSeleccionados.remove(rolLanzador);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _guardarJugador,
              child: Text(_esEdicion ? 'Actualizar' : 'Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}
