class BateadorPerfil {
  final int bateadorId;
  final int temporada;
  final int carrerasImpulsadas;
  final int carrerasAnotadas;
  final int homeRuns;
  final int dobles;
  final int triples;
  final int hits;
  final int turnosAlBate;
  final int basesPorBolas;
  final int golpePorLanzador;
  final int elevadoSacrificio;
  final int basesRobadas;

  BateadorPerfil({
    required this.bateadorId,
    this.temporada = 0,
    required this.carrerasImpulsadas,
    required this.carrerasAnotadas,
    required this.homeRuns,
    required this.dobles,
    required this.triples,
    required this.hits,
    this.turnosAlBate = 0,
    this.basesPorBolas = 0,
    this.golpePorLanzador = 0,
    this.elevadoSacrificio = 0,
    this.basesRobadas = 0,
  });

  double? get promedioBateo => turnosAlBate == 0 ? null : hits / turnosAlBate;

  int get totalBases => hits + dobles + (2 * triples) + (3 * homeRuns);

  double? get porcentajeEmbase {
    final denominador = turnosAlBate + basesPorBolas + golpePorLanzador + elevadoSacrificio;
    if (denominador == 0) return null;
    return (hits + basesPorBolas + golpePorLanzador) / denominador;
  }

  double? get porcentajeSlugging {
    if (turnosAlBate == 0) return null;
    return totalBases / turnosAlBate;
  }

  double? get ops {
    final obp = porcentajeEmbase;
    final slg = porcentajeSlugging;
    if (obp == null || slg == null) return null;
    return obp + slg;
  }

  factory BateadorPerfil.fromMap(Map<String, dynamic> mapa) {
    return BateadorPerfil(
      bateadorId: mapa['bateador_id'] as int,
      temporada: (mapa['temporada'] as int?) ?? 0,
      carrerasImpulsadas: (mapa['carreras_impulsadas'] as int?) ?? 0,
      carrerasAnotadas: (mapa['carreras_anotadas'] as int?) ?? 0,
      homeRuns: (mapa['home_runs'] as int?) ?? 0,
      dobles: (mapa['dobles'] as int?) ?? 0,
      triples: (mapa['triples'] as int?) ?? 0,
      hits: (mapa['hits'] as int?) ?? 0,
      turnosAlBate: (mapa['turnos_al_bate'] as int?) ?? 0,
      basesPorBolas: (mapa['bases_por_bolas'] as int?) ?? 0,
      golpePorLanzador: (mapa['golpe_por_lanzador'] as int?) ?? 0,
      elevadoSacrificio: (mapa['elevado_sacrificio'] as int?) ?? 0,
      basesRobadas: (mapa['bases_robadas'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'bateador_id': bateadorId,
      'promedio_bateo': promedioBateo,
      'carreras_impulsadas': carrerasImpulsadas,
      'carreras_anotadas': carrerasAnotadas,
      'home_runs': homeRuns,
      'dobles': dobles,
      'triples': triples,
      'hits': hits,
      'turnos_al_bate': turnosAlBate,
      'bases_por_bolas': basesPorBolas,
      'golpe_por_lanzador': golpePorLanzador,
      'elevado_sacrificio': elevadoSacrificio,
      'bases_robadas': basesRobadas,
    };
  }
}
