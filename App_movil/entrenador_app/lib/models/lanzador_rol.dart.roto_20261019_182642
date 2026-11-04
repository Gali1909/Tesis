class LanzadorRol {
  final int? id;
  final int lanzadorId;
  final String rolLanzador; // 'abridor', 'relevista', 'cerrador'

  LanzadorRol({
    this.id,
    required this.lanzadorId,
    required this.rolLanzador,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'lanzador_id': lanzadorId,
      'rol_lanzador': rolLanzador,
    };
  }

  factory LanzadorRol.fromMap(Map<String, dynamic> map) {
    return LanzadorRol(
      id: map['id'] as int?,
      lanzadorId: map['lanzador_id'] as int,
      rolLanzador: map['rol_lanzador'] as String,
    );
  }
}