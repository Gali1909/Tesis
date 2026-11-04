class LanzadorPerfilHistorico {
  final int lanzadorId;
  final int juegosGanados;
  final int juegosPerdidos;
  final int aperturas;
  final int salvados;
  final int juegosLanzados;
  final double inningsLanzados;
  final int ponches;
  final int basesPorBolas;
  final int hitsPermitidos;
  final int carrerasLimpias;

  LanzadorPerfilHistorico({
    required this.lanzadorId,
    this.juegosGanados = 0,
    this.juegosPerdidos = 0,
    this.aperturas = 0,
    this.salvados = 0,
    this.juegosLanzados = 0,
    this.inningsLanzados = 0,
    this.ponches = 0,
    this.basesPorBolas = 0,
    this.hitsPermitidos = 0,
    this.carrerasLimpias = 0,
  });

  double? get efectividad {
    if (inningsLanzados == 0) return null;
    return (carrerasLimpias * 9) / inningsLanzados;
  }

  double? get whip {
    if (inningsLanzados == 0) return null;
    return (basesPorBolas + hitsPermitidos) / inningsLanzados;
  }

  Map<String, dynamic> toMap() {
    return {
      'lanzador_id': lanzadorId,
      'juegos_ganados': juegosGanados,
      'juegos_perdidos': juegosPerdidos,
      'aperturas': aperturas,
      'salvados': salvados,
      'juegos_lanzados': juegosLanzados,
      'innings_lanzados': inningsLanzados,
      'ponches': ponches,
      'bases_por_bolas': basesPorBolas,
      'hits_permitidos': hitsPermitidos,
      'carreras_limpias': carrerasLimpias,
    };
  }

  factory LanzadorPerfilHistorico.fromMap(Map<String, dynamic> map) {
    return LanzadorPerfilHistorico(
      lanzadorId: map['lanzador_id'] as int,
      juegosGanados: map['juegos_ganados'] as int? ?? 0,
      juegosPerdidos: map['juegos_perdidos'] as int? ?? 0,
      aperturas: map['aperturas'] as int? ?? 0,
      salvados: map['salvados'] as int? ?? 0,
      juegosLanzados: map['juegos_lanzados'] as int? ?? 0,
      inningsLanzados: (map['innings_lanzados'] as num?)?.toDouble() ?? 0,
      ponches: map['ponches'] as int? ?? 0,
      basesPorBolas: map['bases_por_bolas'] as int? ?? 0,
      hitsPermitidos: map['hits_permitidos'] as int? ?? 0,
      carrerasLimpias: map['carreras_limpias'] as int? ?? 0,
    );
  }
}