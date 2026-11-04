import 'package:flutter/material.dart';
import 'equipos_screen.dart';
import '../models/equipo.dart';
import '../models/jugador.dart';
import '../services/database_helper.dart';
import 'agregar_jugador_screen.dart';
import 'jugadores_libres_screen.dart';
import 'perfil_jugador_screen.dart';

class RosterScreen extends StatefulWidget {
  final int equipoId;
  final String nombreEquipo;

  const RosterScreen({
    super.key,
    required this.equipoId,
    required this.nombreEquipo,
  });

  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  List<Jugador> _jugadores = [];
  final Map<int, List<String>> _posicionesPorJugador = {};

  @override
  void initState() {
    super.initState();
    _cargarJugadores();
  }

  Future<void> _cargarJugadores() async {
    final jugadores = await DatabaseHelper.instance
        .obtenerJugadoresPorEquipo(widget.equipoId);

    final Map<int, List<String>> posiciones = {};
    for (final jugador in jugadores) {
      if (jugador.rol == 'bateador' && jugador.jugadorId != null) {
        final listaPosiciones = await DatabaseHelper.instance
            .obtenerPosiciones(jugador.jugadorId!);
        posiciones[jugador.jugadorId!] =
            listaPosiciones.map((p) => p.posicion).toList();
      }
    }

    setState(() {
      _jugadores = jugadores;
      _posicionesPorJugador.clear();
      _posicionesPorJugador.addAll(posiciones);
    });
  }

  Future<void> _quitarDelRoster(Jugador jugador) async {
    final opcion = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Quitar a ${jugador.nombre}'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'cambiado'),
            child: const Text('Cambiado a otro equipo'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'libre'),
            child: const Text('Dejado en libertad'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'borrar'),
            child: const Text(
              'Borrar definitivamente (error de captura)',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (opcion == null || !mounted) return;

    if (opcion == 'borrar') {
      await _confirmarBorrado(jugador);
    } else if (opcion == 'libre') {
      await DatabaseHelper.instance.dejarJugadorLibre(jugador.jugadorId!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${jugador.nombre} quedo en libertad')),
      );
      _cargarJugadores();
    } else {
      await _elegirEquipoDestino(jugador);
    }
  }

  Future<void> _elegirEquipoDestino(Jugador jugador) async {
    final equipos = (await DatabaseHelper.instance.obtenerEquipos())
        .where((e) => e.equipoId != null && e.equipoId != widget.equipoId)
        .toList();
    if (!mounted) return;
    if (equipos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Primero crea otro equipo en Equipos y rivales'),
        ),
      );
      return;
    }
    final destino = await showDialog<Equipo>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Cambiado a...'),
        children: equipos
            .map(
              (e) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, e),
                child: Text(e.nombre),
              ),
            )
            .toList(),
      ),
    );
    if (destino == null || !mounted) return;
    await DatabaseHelper.instance.asignarJugadorAEquipo(
      jugadorId: jugador.jugadorId!,
      equipoId: destino.equipoId!,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${jugador.nombre} paso a ${destino.nombre}')),
    );
    _cargarJugadores();
  }
  Future<void> _confirmarBorrado(Jugador jugador) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar definitivamente'),
        content: Text('Se borrara a ${jugador.nombre} con todas sus estadisticas y no se puede deshacer. Continuar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );

    if (confirmado == true) {
      await DatabaseHelper.instance.borrarJugador(jugador.jugadorId!);
      _cargarJugadores();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Roster: ${widget.nombreEquipo}'),
        actions: [
          IconButton(
            tooltip: 'Jugadores libres',
            icon: const Icon(Icons.person_search),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => JugadoresLibresScreen(
                    equipoId: widget.equipoId,
                    nombreEquipo: widget.nombreEquipo,
                  ),
                ),
              );
              _cargarJugadores();
            },
          ),
          IconButton(
            tooltip: 'Equipos y rivales',
            icon: const Icon(Icons.groups),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const EquiposScreen()),
            ),
          ),
        ],
      ),
      body: _jugadores.isEmpty
          ? const Center(child: Text('No hay jugadores todavia'))
          : ListView.builder(
              itemCount: _jugadores.length,
              itemBuilder: (context, index) {
                final jugador = _jugadores[index];
                return ListTile(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PerfilJugadorScreen(jugador: jugador),
                      ),
                    );
                  },
                  leading: Icon(
                    jugador.rol == 'lanzador'
                        ? Icons.sports_baseball
                        : Icons.sports_cricket,
                  ),
                  title: Text(jugador.nombre),
                  subtitle: Text(
                    (jugador.rol == 'lanzador' ? 'Lanzador' : 'Bateador') +
                    (jugador.numero != null ? ' - #${jugador.numero}' : '') +
                    (_posicionesPorJugador[jugador.jugadorId] != null &&
                            _posicionesPorJugador[jugador.jugadorId]!.isNotEmpty
                        ? ' - ${_posicionesPorJugador[jugador.jugadorId]!.join(', ')}'
                        : ''),
                  ),
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (opcion) async {
                      if (opcion == 'borrar') {
                        _quitarDelRoster(jugador);
                      } else if (opcion == 'editar') {
                        final resultado = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AgregarJugadorScreen(
                              equipoId: widget.equipoId,
                              jugadorExistente: jugador,
                            ),
                          ),
                        );
                        if (resultado == true) {
                          _cargarJugadores();
                        }
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'editar',
                        child: Text('Editar'),
                      ),
                      const PopupMenuItem(
                        value: 'borrar',
                        child: Text('Quitar del roster'),
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final resultado = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  AgregarJugadorScreen(equipoId: widget.equipoId),
            ),
          );
          if (resultado == true) {
            _cargarJugadores();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}


