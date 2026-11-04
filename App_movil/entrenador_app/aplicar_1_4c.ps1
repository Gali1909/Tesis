# 1.4c - Conservar jugadores libres aunque se borre su equipo anterior
# Ejecutar desde la raiz del proyecto (C:\Tesis\App_movil\entrenador_app)

$dbFile  = "lib\services\database_helper.dart"
$jugFile = "lib\models\jugador.dart"

function Reemplazar($texto, $viejo, $nuevo) {
  $i = $texto.IndexOf($viejo)
  if ($i -lt 0 -or $i -ne $texto.LastIndexOf($viejo)) { throw "No se encontro exactamente una vez: $viejo" }
  return $texto.Substring(0, $i) + $nuevo + $texto.Substring($i + $viejo.Length)
}

function ReemplazarRx($texto, $patron, $nuevo) {
  $ms = [regex]::Matches($texto, $patron)
  if ($ms.Count -ne 1) { throw "Se esperaba 1 coincidencia y hubo $($ms.Count): $patron" }
  $m = $ms[0]
  return $texto.Substring(0, $m.Index) + $nuevo + $texto.Substring($m.Index + $m.Length)
}

function Leer($ruta) {
  return (Get-Content $ruta -Raw -Encoding UTF8) -replace "`r`n", "`n"
}

try {
  $t = Leer $dbFile
  $j = Leer $jugFile

  if ($t.Contains("_migrarEquipoOpcional")) { throw "Este paso ya se aplico. No se modifico nada." }

  # ---------- database_helper.dart ----------

  # 1. import de dart:io (para el respaldo de la base de datos)
  if (-not $t.Contains("import 'dart:io';")) { $t = "import 'dart:io';`n" + $t }

  # 2. La migracion corre al abrir la base de datos, despues de las membresias
  $t = Reemplazar $t "    await _prepararMembresias(db);`n" "    await _prepararMembresias(db);`n    await _migrarEquipoOpcional(db);`n"

  # 3. Metodos nuevos de migracion
  $metodos = @'
  /// 1.4c: jugador.equipo_id y jugador_equipo.equipo_id pasan a ser opcionales
  /// para que un jugador libre (o el historial de un equipo borrado) no dependa
  /// de un equipo. Se reconstruyen las tablas con su misma definicion.
  Future<bool> _columnaObligatoria(
    Database db,
    String tabla,
    String columna,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($tabla)');
    for (final c in info) {
      if (c['name'] == columna) return c['notnull'] == 1;
    }
    return false;
  }

  Future<void> _reconstruirEquipoOpcional(
    DatabaseExecutor ex,
    String tabla,
  ) async {
    final filas = await ex.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
      [tabla],
    );
    final sqlViejo = filas.first['sql'] as String;
    final sinNotNull = sqlViejo.replaceFirst(
      RegExp(r'equipo_id\s+INTEGER\s+NOT\s+NULL', caseSensitive: false),
      'equipo_id INTEGER',
    );
    if (sinNotNull == sqlViejo) {
      throw Exception('No se pudo adaptar la definicion de $tabla');
    }
    final sqlNuevo = sinNotNull.replaceFirst(
      RegExp(
        'CREATE TABLE\\s+(IF NOT EXISTS\\s+)?["`\\[]?$tabla["`\\]]?(?=\\s*\\()',
        caseSensitive: false,
      ),
      'CREATE TABLE ${tabla}_nueva',
    );
    if (!sqlNuevo.contains('${tabla}_nueva')) {
      throw Exception('No se pudo renombrar la definicion de $tabla');
    }

    final indices = await ex.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type = 'index' AND tbl_name = ? AND sql IS NOT NULL",
      [tabla],
    );
    final secuencia = await ex.rawQuery(
      'SELECT seq FROM sqlite_sequence WHERE name = ?',
      [tabla],
    );

    await ex.execute(sqlNuevo);
    await ex.execute('INSERT INTO ${tabla}_nueva SELECT * FROM $tabla');
    await ex.execute('DROP TABLE $tabla');
    await ex.execute('ALTER TABLE ${tabla}_nueva RENAME TO $tabla');
    for (final i in indices) {
      await ex.execute(i['sql'] as String);
    }
    if (secuencia.isNotEmpty) {
      await ex.rawUpdate(
        'UPDATE sqlite_sequence SET seq = ? WHERE name = ?',
        [secuencia.first['seq'], tabla],
      );
    }
  }

  Future<void> _migrarEquipoOpcional(Database db) async {
    final jugadorObligatorio =
        await _columnaObligatoria(db, 'jugador', 'equipo_id');
    final membresiaObligatoria =
        await _columnaObligatoria(db, 'jugador_equipo', 'equipo_id');
    final columnasMembresia =
        await db.rawQuery('PRAGMA table_info(jugador_equipo)');
    final tieneNombre =
        columnasMembresia.any((c) => c['name'] == 'nombre_equipo');
    if (!jugadorObligatorio && !membresiaObligatoria && tieneNombre) return;

    try {
      final copia = File('${db.path}.bak_equipo_opcional');
      if (!await copia.exists()) {
        await File(db.path).copy(copia.path);
      }

      if (!tieneNombre) {
        await db.execute(
          'ALTER TABLE jugador_equipo ADD COLUMN nombre_equipo TEXT',
        );
      }

      if (jugadorObligatorio || membresiaObligatoria) {
        await db.execute('PRAGMA foreign_keys = OFF');
        await db.transaction((txn) async {
          if (jugadorObligatorio) {
            await _reconstruirEquipoOpcional(txn, 'jugador');
          }
          if (membresiaObligatoria) {
            await _reconstruirEquipoOpcional(txn, 'jugador_equipo');
          }
          if (jugadorObligatorio) {
            // Los jugadores sin pertenencia vigente quedan sin equipo.
            await txn.execute('''
              UPDATE jugador SET equipo_id = NULL
              WHERE jugador_id NOT IN (
                SELECT jugador_id FROM jugador_equipo WHERE fecha_fin IS NULL
              )
            ''');
          }
          final problemas = await txn.rawQuery('PRAGMA foreign_key_check');
          if (problemas.isNotEmpty) {
            throw Exception(
              'foreign_key_check: ${problemas.length} violaciones, '
              'primeras: ${problemas.take(5).toList()}',
            );
          }
        });
      }
    } catch (e) {
      // ignore: avoid_print
      print('1.4c: migracion cancelada, se conserva el esquema anterior: $e');
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }

'@
  $ancla = "  /// Historial de pertenencia de jugadores a equipos (fase 1.4)."
  $t = Reemplazar $t $ancla (($metodos -replace "`r`n", "`n") + $ancla)

  # 4. borrarEquipo: solo se borran los jugadores de la plantilla vigente
  $consultaNueva = @'
final jugadores = await db.rawQuery(
      '''
      SELECT m.jugador_id AS jugador_id FROM jugador_equipo m
      WHERE m.equipo_id = ? AND m.fecha_fin IS NULL
      ''',
      [equipoId],
    );
'@
  $patronConsulta = "final jugadores = await db\.query\(\s*'jugador',\s*columns: \['jugador_id'\],\s*where: 'equipo_id = \?',\s*whereArgs: \[equipoId\],\s*\);"
  $t = ReemplazarRx $t $patronConsulta (($consultaNueva -replace "`r`n", "`n").TrimEnd("`n"))

  # 5. borrarEquipo: el historial se conserva sin equipo y los libres quedan sin equipo
  $historialNuevo = @'
// Se conserva el historial: la fila queda sin equipo pero con su nombre.
    await db.rawUpdate(
      'UPDATE jugador_equipo SET nombre_equipo = '
      '(SELECT nombre FROM equipo WHERE equipo_id = ?), equipo_id = NULL '
      'WHERE equipo_id = ?',
      [equipoId, equipoId],
    );
    // Los jugadores libres que apuntaban a este equipo se conservan.
    await db.update(
      'jugador',
      {'equipo_id': null},
      where: 'equipo_id = ?',
      whereArgs: [equipoId],
    );
'@
  $patronBorrado = "await db\.delete\(\s*'jugador_equipo',\s*where: 'equipo_id = \?',\s*whereArgs: \[equipoId\],?\s*\);"
  $t = ReemplazarRx $t $patronBorrado (($historialNuevo -replace "`r`n", "`n").TrimEnd("`n"))

  # 6. dejarJugadorLibre: el jugador libre ya no apunta a ningun equipo
  $libreNuevo = @'
await db.transaction((txn) async {
      await txn.update(
        'jugador_equipo',
        {'fecha_fin': hoy, 'motivo_salida': 'libre'},
        where: 'jugador_id = ? AND fecha_fin IS NULL',
        whereArgs: [jugadorId],
      );
      await txn.update(
        'jugador',
        {'equipo_id': null},
        where: 'jugador_id = ?',
        whereArgs: [jugadorId],
      );
    });
'@
  $patronLibre = "await db\.update\(\s*'jugador_equipo',\s*\{'fecha_fin': hoy, 'motivo_salida': 'libre'\},\s*where: 'jugador_id = \? AND fecha_fin IS NULL',\s*whereArgs: \[jugadorId\],?\s*\);"
  $t = ReemplazarRx $t $patronLibre (($libreNuevo -replace "`r`n", "`n").TrimEnd("`n"))

  # ---------- jugador.dart ----------
  $j = Reemplazar $j "final int equipoId;" "final int? equipoId;"
  $j = Reemplazar $j "equipoId: map['equipo_id'] as int," "equipoId: map['equipo_id'] as int?,"

  # ---------- Todo salio bien: respaldos y escritura ----------
  Copy-Item $dbFile "$dbFile.bak_1_4c" -Force
  Copy-Item $jugFile "$jugFile.bak_1_4c" -Force
  Set-Content -Path $dbFile -Value ($t -replace "`n", "`r`n") -Encoding UTF8 -NoNewline
  Set-Content -Path $jugFile -Value ($j -replace "`n", "`r`n") -Encoding UTF8 -NoNewline
  Write-Host "OK: 1.4c aplicado" -ForegroundColor Green
}
catch {
  Write-Host "ERROR, no se modifico nada: $_" -ForegroundColor Red
}

flutter analyze
