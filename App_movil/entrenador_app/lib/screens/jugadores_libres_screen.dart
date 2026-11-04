import 'package:flutter/material.dart';

import '../models/jugador.dart';
import '../services/database_helper.dart';
import 'perfil_jugador_screen.dart';

class JugadoresLibresScreen extends StatefulWidget {
  final int equipoId;
  final String nombreEquipo;

  const JugadoresLibresScreen({
    super.key,
    required this.equipoId,
    required this.nombreEquipo,
  });

  @override
  State<JugadoresLibresScreen> createState() => _JugadoresLibresScreenState();
}

class _JugadoresLibresScreenState extends State<JugadoresLibresScreen> {
  final TextEditingController _controlBusqueda = TextEditingController();
  List<Jugador> _libres = [];
  String _busqueda = '';
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _controlBusqueda.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final libres = await DatabaseHelper.instance.obtenerJugadoresLibres();
    if (!mounted) return;
    setState(() {
      _libres = libres;
      _cargando = false;
    });
  }

  /// Minusculas y sin tildes, para que "jose" encuentre a "Jose" con tilde.
  String _normalizar(String texto) {
    const origen = '\u00e1\u00e0\u00e4\u00e2\u00e9\u00e8\u00eb\u00ea\u00ed\u00ec\u00ef\u00ee\u00f3\u00f2\u00f6\u00f4\u00fa\u00f9\u00fc\u00fb\u00f1';
    const destino = 'aaaaeeeeiiiioooouuuun';
    var resultado = texto.toLowerCase();
    for (var i = 0; i < origen.length; i++) {
      resultado = resultado.replaceAll(origen[i], destino[i]);
    }
    return resultado.trim();
  }

  List<Jugador> get _filtrados {
    final q = _normalizar(_busqueda);
    if (q.isEmpty) return _libres;
    return _libres.where((j) {
      final numero = j.numero?.toString() ?? '';
      return _normalizar(j.nombre).contains(q) || numero.contains(q);
    }).toList();
  }

  Future<void> _fichar(Jugador jugador) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fichar jugador'),
        content: Text('Fichar a ${jugador.nombre} en ${widget.nombreEquipo}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Fichar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    await DatabaseHelper.instance.asignarJugadorAEquipo(
      jugadorId: jugador.jugadorId!,
      equipoId: widget.equipoId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${jugador.nombre} ahora es de ${widget.nombreEquipo}')),
    );
    _cargar();
  }

  Widget _barraBusqueda() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _controlBusqueda,
        textInputAction: TextInputAction.search,
        onChanged: (valor) => setState(() => _busqueda = valor),
        decoration: InputDecoration(
          hintText: 'Buscar por nombre o numero',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _busqueda.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Limpiar',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _controlBusqueda.clear();
                    setState(() => _busqueda = '');
                  },
                ),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _filtrados;

    return Scaffold(
      appBar: AppBar(title: const Text('Jugadores libres')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _barraBusqueda(),
                if (_libres.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _busqueda.isEmpty
                            ? '${_libres.length} jugadores'
                            : '${filtrados.length} de ${_libres.length} jugadores',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                Expanded(
                  child: filtrados.isEmpty
                      ? Center(
                          child: Text(
                            _libres.isEmpty
                                ? 'No hay jugadores libres'
                                : 'Sin resultados para: $_busqueda',
                          ),
                        )
                      : ListView.builder(
                          itemCount: filtrados.length,
                          itemBuilder: (context, index) {
                            final j = filtrados[index];
                            return ListTile(
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        PerfilJugadorScreen(jugador: j),
                                  ),
                                );
                                if (!mounted) return;
                                _cargar();
                              },
                              leading: Icon(
                                j.rol == 'lanzador'
                                    ? Icons.sports_baseball
                                    : Icons.sports_cricket,
                              ),
                              title: Text(j.nombre),
                              subtitle: Text(
                                (j.rol == 'lanzador' ? 'Lanzador' : 'Bateador') +
                                    (j.numero != null ? ' - #${j.numero}' : ''),
                              ),
                              trailing: TextButton(
                                onPressed: () => _fichar(j),
                                child: const Text('Fichar'),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
