class BateadorVulnerabilidad {
  final int? id;
  final int bateadorId;
  final int tipoLanzamientoId;
  final String nombreTipo; // viene de un JOIN con tipo_lanzamiento
  final double? nivelEfectividadContra;
  final String origen;

  BateadorVulnerabilidad({
    this.id,
    required this.bateadorId,
    required this.tipoLanzamientoId,
    required this.nombreTipo,
    this.nivelEfectividadContra,
    required this.origen,
  });

  factory BateadorVulnerabilidad.fromMap(Map<String, dynamic> map) {
    return BateadorVulnerabilidad(
      id: map['id'] as int?,
      bateadorId: map['bateador_id'] as int,
      tipoLanzamientoId: map['tipo_lanzamiento_id'] as int,
      nombreTipo: map['nombre'] as String,
      nivelEfectividadContra: (map['nivel_efectividad_contra'] as num?)?.toDouble(),
      origen: map['origen'] as String,
    );
  }
}