class LanzadorTipoPicheo {
  final int? id;
  final int lanzadorId;
  final int tipoLanzamientoId;
  final String nombreTipo; // viene de un JOIN con tipo_lanzamiento
  final double? frecuencia;
  final double? velocidadPromedio;
  final double? velocidadMax;

  LanzadorTipoPicheo({
    this.id,
    required this.lanzadorId,
    required this.tipoLanzamientoId,
    required this.nombreTipo,
    this.frecuencia,
    this.velocidadPromedio,
    this.velocidadMax,
  });

  factory LanzadorTipoPicheo.fromMap(Map<String, dynamic> map) {
    return LanzadorTipoPicheo(
      id: map['id'] as int?,
      lanzadorId: map['lanzador_id'] as int,
      tipoLanzamientoId: map['tipo_lanzamiento_id'] as int,
      nombreTipo: map['nombre'] as String,
      frecuencia: (map['frecuencia'] as num?)?.toDouble(),
      velocidadPromedio: (map['velocidad_promedio'] as num?)?.toDouble(),
      velocidadMax: (map['velocidad_max'] as num?)?.toDouble(),
    );
  }
}