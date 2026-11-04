class Equipo {
  final int? equipoId;
  final String nombre;
  final String tipo; // 'propio' o 'rival'

  Equipo({
    this.equipoId,
    required this.nombre,
    required this.tipo,
  });

  // Convierte un objeto Equipo a un Map, para guardarlo en SQLite
  Map<String, dynamic> toMap() {
    return {
      'equipo_id': equipoId,
      'nombre': nombre,
      'tipo': tipo,
    };
  }

  // Convierte un Map (lo que devuelve SQLite) de vuelta a un objeto Equipo
  factory Equipo.fromMap(Map<String, dynamic> map) {
    return Equipo(
      equipoId: map['equipo_id'] as int?,
      nombre: map['nombre'] as String,
      tipo: map['tipo'] as String,
    );
  }
}