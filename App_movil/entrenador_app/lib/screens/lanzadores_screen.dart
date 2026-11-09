import 'dart:io';

import 'package:flutter/material.dart';

import '../models/jugador.dart';
import '../models/lanzador_perfil.dart';
import '../models/lanzador_rol.dart';
import '../models/lanzador_tipo_picheo.dart';
import '../services/database_helper.dart';
import '../widgets/barra_inferior_app.dart';
import 'nuevo_lanzador_screen.dart';
import 'perfil_jugador_screen.dart';

const Color _fondo = Color(0xFFF4F6FA);
const Color _tinta = Color(0xFF0F172A);
const Color _gris = Color(0xFF64748B);
const Color _azul = Color(0xFF1D4ED8);
const Color _azulClaro = Color(0xFFE3ECFF);
const Color _azulTexto = Color(0xFF1E3A8A);
const Color _naranja = Color(0xFFFF7A1A);
const Color _borde = Color(0xFFE2E8F0);
const Color _bordeChip = Color(0xFFCBD5E1);
const Color _textoChip = Color(0xFF334155);

enum _Filtro { todos, abridores, relevistas, zurdos }

class _FilaLanzador {
  final Jugador jugador;
  final List<LanzadorRol> roles;
  final List<LanzadorTipoPicheo> tipos;
  final LanzadorPerfil? perfil;

  const _FilaLanzador(this.jugador, this.roles, this.tipos, this.perfil);

  double? get era => perfil?.efectividad;
}

/// Lista de lanzadores del equipo (solo jugadores con rol 'lanzador').
class LanzadoresScreen extends StatefulWidget {
  final int equipoId;

  const LanzadoresScreen({super.key, required this.equipoId});

  @override
  State<LanzadoresScreen> createState() => _LanzadoresScreenState();
}

class _LanzadoresScreenState extends State<LanzadoresScreen> {
  List<_FilaLanzador> _filas = [];
  bool _cargando = true;
  String? _error;
  _Filtro _filtro = _Filtro.todos;
  bool _porEfectividad = true;
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final db = DatabaseHelper.instance;
    try {
      final todos = await db.obtenerJugadoresPorEquipo(widget.equipoId);
      final filas = <_FilaLanzador>[];
      for (final j in todos) {
        if (j.rol != 'lanzador' || j.jugadorId == null) continue;
        final id = j.jugadorId!;
        final roles = await db.obtenerRolesLanzador(id);
        final tipos = await db.obtenerTiposPicheo(id);
        final temporadas = await db.obtenerTemporadasLanzadorTotal(id);
        LanzadorPerfil? perfil;
        if (temporadas.isNotEmpty) {
          perfil = await db.obtenerLanzadorPerfilTotal(id, temporadas.first);
        }
        tipos.sort((a, b) => (b.frecuencia ?? 0).compareTo(a.frecuencia ?? 0));
        filas.add(_FilaLanzador(j, roles, tipos, perfil));
      }
      if (!mounted) return;
      setState(() {
        _filas = filas;
        _cargando = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  Future<void> _agregar() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NuevoLanzadorScreen(equipoId: widget.equipoId),
      ),
    );
    if (ok == true) _cargar();
  }

  Future<void> _abrirPerfil(Jugador j) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PerfilJugadorScreen(jugador: j)),
    );
    if (mounted) _cargar();
  }

  List<_FilaLanzador> _visibles() {
    final q = _busqueda.trim().toLowerCase();
    final lista = _filas.where((f) {
      if (q.isNotEmpty && !f.jugador.nombre.toLowerCase().contains(q)) {
        return false;
      }
      switch (_filtro) {
        case _Filtro.todos:
          return true;
        case _Filtro.abridores:
          return f.roles.any((r) => r.rolLanzador == 'abridor');
        case _Filtro.relevistas:
          return f.roles.any((r) => r.rolLanzador == 'relevista');
        case _Filtro.zurdos:
          return f.jugador.manoLanzamiento?.toLowerCase() == 'zurdo';
      }
    }).toList();

    if (_porEfectividad) {
      lista.sort((a, b) {
        if (a.era == null && b.era == null) {
          return a.jugador.nombre.compareTo(b.jugador.nombre);
        }
        if (a.era == null) return 1;
        if (b.era == null) return -1;
        return a.era!.compareTo(b.era!);
      });
    } else {
      lista.sort((a, b) => a.jugador.nombre.toLowerCase().compareTo(b.jugador.nombre.toLowerCase()));
    }
    return lista;
  }

  String _capitalizar(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  String _iniciales(String nombre) {
    final partes = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first[0].toUpperCase();
    return '${partes[0][0]}${partes[1][0]}'.toUpperCase();
  }

  String _nombreCorto(String tipo) {
    switch (tipo) {
      case 'Four-Seam Fastball':
        return 'Recta';
      case 'Two-Seam Fastball':
        return 'Recta 2C';
      case 'Curveball':
        return 'Curva';
      case 'Changeup':
      case 'Circle Change':
        return 'Cambio';
      case 'Split-Finger Fastball':
        return 'Splitter';
      case 'Knuckleball':
        return 'Nudillo';
      default:
        return tipo;
    }
  }

  // ---------------------------------------------------------------------

  PreferredSizeWidget _barraSuperior() {
    return AppBar(
      backgroundColor: _fondo,
      foregroundColor: _tinta,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Lanzadores',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, height: 1.2)),
          Text('${_filas.length} en el roster',
              style: const TextStyle(fontSize: 11, color: _gris, fontWeight: FontWeight.w400)),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _agregar,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(color: _naranja, borderRadius: BorderRadius.circular(10)),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 16, color: _tinta),
                    SizedBox(width: 2),
                    Text('Agregar',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _tinta)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buscador() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: TextField(
        onChanged: (v) => setState(() => _busqueda = v),
        style: const TextStyle(fontSize: 13, color: _tinta),
        decoration: InputDecoration(
          hintText: 'Buscar lanzador',
          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
          prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 11),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _bordeChip, width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _azul, width: 1),
          ),
        ),
      ),
    );
  }

  Widget _chipsFiltro() {
    const etiquetas = {
      _Filtro.todos: 'Todos',
      _Filtro.abridores: 'Abridores',
      _Filtro.relevistas: 'Relevistas',
      _Filtro.zurdos: 'Zurdos',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            for (final e in etiquetas.entries)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() => _filtro = e.key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _filtro == e.key ? _azul : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _filtro == e.key ? _azul : _bordeChip,
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      e.value,
                      style: TextStyle(
                        fontSize: 12,
                        color: _filtro == e.key ? Colors.white : _textoChip,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _filaOrden() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: InkWell(
        onTap: () => setState(() => _porEfectividad = !_porEfectividad),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _porEfectividad ? 'Ordenar por efectividad' : 'Ordenar por nombre',
              style: const TextStyle(fontSize: 12, color: _gris),
            ),
            const Icon(Icons.swap_vert, size: 18, color: _gris),
          ],
        ),
      ),
    );
  }

  Widget _tarjeta(_FilaLanzador f, int indice) {
    const fondosAvatar = [Color(0xFFE3ECFF), Color(0xFFFFE9D6), Color(0xFFE8EDF5)];
    const letrasAvatar = [Color(0xFF1D4ED8), Color(0xFFC2410C), Color(0xFF334155)];
    final j = f.jugador;
    final fotoPath = j.foto;
    final tieneFoto = fotoPath != null && fotoPath.isNotEmpty && File(fotoPath).existsSync();

    final partes = <String>[
      if (f.roles.isNotEmpty) _capitalizar(f.roles.first.rolLanzador),
      if (j.manoLanzamiento != null && j.manoLanzamiento!.isNotEmpty)
        _capitalizar(j.manoLanzamiento!),
    ];
    final subtitulo = partes.isEmpty ? 'Lanzador' : partes.join(' · ');

    final mostrados = f.tipos.take(3).toList();
    final resto = f.tipos.length - mostrados.length;
    final p = f.perfil;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borde, width: 0.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _abrirPerfil(j),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: fondosAvatar[indice % 3],
                      backgroundImage: tieneFoto ? FileImage(File(fotoPath)) : null,
                      child: tieneFoto
                          ? null
                          : Text(
                              _iniciales(j.nombre),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: letrasAvatar[indice % 3],
                              ),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: j.nombre,
                                  style: const TextStyle(
                                      fontSize: 14, fontWeight: FontWeight.w500, color: _tinta),
                                ),
                                if (j.numero != null)
                                  TextSpan(
                                    text: ' #${j.numero}',
                                    style: const TextStyle(
                                        fontSize: 14, fontWeight: FontWeight.w500, color: _naranja),
                                  ),
                              ],
                            ),
                          ),
                          Text(subtitulo, style: const TextStyle(fontSize: 12, color: _gris)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          f.era == null ? '--' : f.era!.toStringAsFixed(2),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w500, color: _azulTexto),
                        ),
                        const Text('Efectividad', style: TextStyle(fontSize: 11, color: _gris)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: f.tipos.isEmpty
                          ? const Text('Sin lanzamientos cargados',
                              style: TextStyle(fontSize: 11, color: _gris))
                          : Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                for (final t in mostrados) _chipLanzamiento(_nombreCorto(t.nombreTipo)),
                                if (resto > 0) _chipLanzamiento('+$resto'),
                              ],
                            ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      p == null ? '--' : '${p.juegosGanados}-${p.juegosPerdidos}',
                      style: const TextStyle(fontSize: 12, color: _textoChip),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chipLanzamiento(String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: _azulClaro, borderRadius: BorderRadius.circular(8)),
      child: Text(texto, style: const TextStyle(fontSize: 11, color: _azulTexto)),
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Error cargando lanzadores: $_error'),
        ),
      );
    }
    final visibles = _visibles();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buscador(),
        _chipsFiltro(),
        _filaOrden(),
        Expanded(
          child: visibles.isEmpty
              ? Center(
                  child: Text(
                    _filas.isEmpty
                        ? 'Aun no hay lanzadores. Usa Agregar.'
                        : 'Ningun lanzador coincide con el filtro',
                    style: const TextStyle(fontSize: 13, color: _gris),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  itemCount: visibles.length,
                  itemBuilder: (_, i) => _tarjeta(visibles[i], i),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fondo,
      appBar: _barraSuperior(),
      body: _cuerpo(),
      bottomNavigationBar: BarraInferiorApp(
        activa: SeccionBarra.equipo,
        alTocarEquipo: () {},
      ),
    );
  }
}
