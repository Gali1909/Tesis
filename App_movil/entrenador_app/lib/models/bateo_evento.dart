class BateoEvento {
  final int id;
  final int bateadorId;
  final int? juegoId;
  final int tipoLanzamientoId;
  final String resultado;
  final String fecha;
  final String nombreLanzamiento;

  BateoEvento({
    required this.id,
    required this.bateadorId,
    this.juegoId,
    required this.tipoLanzamientoId,
    required this.resultado,
    required this.fecha,
    required this.nombreLanzamiento,
  });

  static const Map<String, String> etiquetasResultado = {
    'sencillo': '1B',
    'doble': '2B',
    'triple': '3B',
    'home_run': 'HR',
    'out': 'Out',
    'ponche': 'Ponche',
    'boleto': 'BB',
    'golpe_por_lanzador': 'HBP',
  };

  String get etiqueta => etiquetasResultado[resultado] ?? resultado;

  factory BateoEvento.fromMap(Map<String, dynamic> mapa) {
    return BateoEvento(
      id: mapa['id'] as int,
      bateadorId: mapa['bateador_id'] as int,
      juegoId: mapa['juego_id'] as int?,
      tipoLanzamientoId: mapa['tipo_lanzamiento_id'] as int,
      resultado: mapa['resultado'] as String,
      fecha: mapa['fecha'] as String,
      nombreLanzamiento: mapa['nombre'] as String,
    );
  }
}
