import 'package:flutter/material.dart';

import '../screens/enviar_pantalla_screen.dart';
import '../services/cambios_db.dart';
import '../services/database_helper.dart';
import '../services/pantalla_ble.dart';
import '../services/pantalla_protocolo.dart';

const Color _cianBtn = Color(0xFF0ABDCF);

/// Boton "Enviar perfil a la pantalla del entrenador" para el perfil de un
/// lanzador propio. Envia los tipos y el perfil con la misma conexion BLE que
/// usa la pantalla del coach. Si no hay pantalla conectada, abre la pantalla
/// de conexion y, al volver, envia el perfil si ya quedo conectada.
/// Solo aparece para lanzadores del propio equipo.
class BotonEnviarPerfilPantalla extends StatefulWidget {
  final int lanzadorId;

  /// Temporada que esta viendo el perfil en la app (null = la mas reciente).
  final int? temporada;
  const BotonEnviarPerfilPantalla({
    super.key,
    required this.lanzadorId,
    this.temporada,
  });

  @override
  State<BotonEnviarPerfilPantalla> createState() =>
      _BotonEnviarPerfilPantallaState();
}

class _BotonEnviarPerfilPantallaState extends State<BotonEnviarPerfilPantalla> {
  final _ble = PantallaBle.instance;
  bool _enviando = false;
  String? _mensaje;
  bool _ok = false;
  bool _propio = false;

  @override
  void initState() {
    super.initState();
    _verificarPropio();
  }

  Future<void> _verificarPropio() async {
    try {
      final l = await DatabaseHelper.instance.obtenerLanzadoresPropios();
      final es = l.any((f) => f['jugador_id'] == widget.lanzadorId);
      if (mounted) setState(() => _propio = es);
    } catch (_) {
      if (mounted) setState(() => _propio = false);
    }
  }

  Future<void> _enviar() async {
    if (!_ble.conectado) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const EnviarPantallaScreen()),
      );
      if (!mounted) return;
      if (!_ble.conectado) {
        setState(() {
          _ok = false;
          _mensaje = 'No hay una pantalla conectada.';
        });
        return;
      }
    }

    setState(() {
      _enviando = true;
      _mensaje = null;
    });
    String res;
    bool ok = false;
    try {
      final t = await _ble.enviar(
        PantallaProtocolo.tTipos,
        await PantallaProtocolo.payloadTipos(),
      );
      if (t != 0) {
        res = 'Fallo al enviar los tipos (codigo $t)';
      } else {
        final r = await _ble.enviar(
          PantallaProtocolo.tPerfilLanzador,
          await PantallaProtocolo.payloadPerfilLanzador(widget.lanzadorId),
        );
        if (r == 0) {
          final d = await _ble.enviar(
            PantallaProtocolo.tPerfilDatos,
            await PantallaProtocolo.payloadPerfilDatos(
              widget.lanzadorId,
              temporada: widget.temporada,
            ),
          );
          if (d == 0) {
            try {
              final vistas = await PantallaProtocolo.payloadsPerfilVistas(
                widget.lanzadorId,
                temporada: widget.temporada,
              );
              await _ble.enviar(PantallaProtocolo.tPerfilTipos, await PantallaProtocolo.payloadPerfilTipos(widget.lanzadorId));
              for (final v in vistas) {
                await _ble.enviar(PantallaProtocolo.tPerfilVista, v);
              }
            } catch (_) {}
          }
          ok = d == 0;
          res = d == 0
              ? 'Perfil enviado y confirmado por la pantalla'
              : d == -1
                  ? 'La pantalla no respondio a los datos del perfil'
                  : 'La pantalla rechazo los datos del perfil (codigo $d)';
        } else {
          res = r == -1
              ? 'La pantalla no respondio (sin confirmacion)'
              : 'La pantalla rechazo el perfil (codigo $r)';
        }
      }
    } catch (e) {
      res = e is StateError ? e.message : 'Error: $e';
    }
    if (!mounted) return;
    setState(() {
      _enviando = false;
      _ok = ok;
      _mensaje = res;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_propio) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _enviando ? null : _enviar,
            style: OutlinedButton.styleFrom(
              foregroundColor: _cianBtn,
              side: const BorderSide(color: _cianBtn),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            icon: _enviando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_to_mobile),
            label: Text(_enviando
                ? 'Enviando...'
                : 'Enviar perfil a la pantalla del entrenador'),
          ),
        ),
        if (_mensaje != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _mensaje!,
              style: TextStyle(
                color: _ok ? _cianBtn : Colors.redAccent,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }
}