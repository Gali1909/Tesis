class Jugador {
  final int? jugadorId;
  final int? equipoId;
  final String nombre;
  final String rol; // 'lanzador' o 'bateador'
  final String? manoBateo; // 'derecha', 'izquierda', 'ambos' — solo bateadores
  final String? manoLanzamiento; // 'zurdo', 'derecho' — solo lanzadores
  final int? numero;
  final String? foto;

  Jugador({
    this.jugadorId,
    required this.equipoId,
    required this.nombre,
    required this.rol,
    this.manoBateo,
    this.manoLanzamiento,
    this.numero,
    this.foto,
  });

  Map<String, dynamic> toMap() {
    return {
      'jugador_id': jugadorId,
      'equipo_id': equipoId,
      'nombre': nombre,
      'rol': rol,
      'mano_bateo': manoBateo,
      'mano_lanzamiento': manoLanzamiento,
      'numero': numero,
      'foto': foto,
    };
  }

  factory Jugador.fromMap(Map<String, dynamic> map) {
    return Jugador(
      jugadorId: map['jugador_id'] as int?,
      equipoId: map['equipo_id'] as int?,
      nombre: map['nombre'] as String,
      rol: map['rol'] as String,
      manoBateo: map['mano_bateo'] as String?,
      manoLanzamiento: map['mano_lanzamiento'] as String?,
      numero: map['numero'] as int?,
      foto: map['foto'] as String?,
    );
  }
}