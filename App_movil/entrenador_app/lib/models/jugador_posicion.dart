class JugadorPosicion {
  final int? id;
  final int jugadorId;
  final String posicion; // 'P', 'C', '1B', '2B', '3B', 'SS', 'LF', 'CF', 'RF'

  JugadorPosicion({
    this.id,
    required this.jugadorId,
    required this.posicion,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'jugador_id': jugadorId,
      'posicion': posicion,
    };
  }

  factory JugadorPosicion.fromMap(Map<String, dynamic> map) {
    return JugadorPosicion(
      id: map['id'] as int?,
      jugadorId: map['jugador_id'] as int,
      posicion: map['posicion'] as String,
    );
  }
}