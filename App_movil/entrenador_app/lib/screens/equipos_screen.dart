import 'package:flutter/material.dart';
import '../models/equipo.dart';
import '../services/database_helper.dart';
import 'roster_screen.dart';

const Color _colorFondoOscuro = Color(0xFF14171C);
const Color _colorAcento = Color(0xFF0ABDCF);

class EquiposScreen extends StatefulWidget {
  const EquiposScreen({super.key});

  @override
  State<EquiposScreen> createState() => _EquiposScreenState();
}

class _EquiposScreenState extends State<EquiposScreen> {
  List<Equipo> _equipos = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final lista = await DatabaseHelper.instance.obtenerEquipos();
    lista.sort((a, b) {
      if (a.tipo != b.tipo) return a.tipo == 'propio' ? -1 : 1;
      return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
    });
    if (!mounted) return;
    setState(() {
      _equipos = lista;
      _cargando = false;
    });
  }

  Future<void> _nuevoRival() async {
    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) => const _NuevoRivalDialog(),
    );
    if (nombre == null || nombre.isEmpty) return;

    final existe = _equipos.any((e) => e.nombre.toLowerCase() == nombre.toLowerCase());
    if (existe) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ya existe un equipo con ese nombre.')),
      );
      return;
    }

    await DatabaseHelper.instance.crearEquipo(Equipo(nombre: nombre, tipo: 'rival'));
    await _cargar();
  }

  Future<void> _borrarRival(Equipo e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar equipo rival'),
        content: Text(
          'Se borrara "${e.nombre}" y todos sus jugadores. Esta accion no se puede deshacer.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('BORRAR')),
        ],
      ),
    );
    if (ok != true) return;
    await DatabaseHelper.instance.borrarEquipo(e.equipoId!);
    await _cargar();
  }

  void _abrirRoster(Equipo e) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RosterScreen(equipoId: e.equipoId!, nombreEquipo: e.nombre),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      appBar: AppBar(
        backgroundColor: _colorFondoOscuro,
        foregroundColor: Colors.white,
        title: const Text('EQUIPOS'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _colorAcento,
        foregroundColor: Colors.white,
        onPressed: _nuevoRival,
        icon: const Icon(Icons.add),
        label: const Text('NUEVO RIVAL'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              itemCount: _equipos.length,
              itemBuilder: (ctx, i) {
                final e = _equipos[i];
                final propio = e.tipo == 'propio';
                return Card(
                  child: ListTile(
                    leading: Icon(
                      propio ? Icons.home : Icons.sports_baseball,
                      color: propio ? _colorFondoOscuro : _colorAcento,
                    ),
                    title: Text(e.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(propio ? 'Mi equipo' : 'Rival'),
                    trailing: propio
                        ? const Icon(Icons.chevron_right)
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.redAccent),
                                onPressed: () => _borrarRival(e),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                    onTap: () => _abrirRoster(e),
                  ),
                );
              },
            ),
    );
  }
}

class _NuevoRivalDialog extends StatefulWidget {
  const _NuevoRivalDialog();

  @override
  State<_NuevoRivalDialog> createState() => _NuevoRivalDialogState();
}

class _NuevoRivalDialogState extends State<_NuevoRivalDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo equipo rival'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Nombre del equipo',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('CREAR'),
        ),
      ],
    );
  }
}