# 1.4c (correccion) - perfiles de jugadores libres (equipoId nulo)
# Ejecutar desde la raiz del proyecto (C:\Tesis\App_movil\entrenador_app)

$archivos = @(
  "lib\screens\perfil_bateador_screen.dart",
  "lib\screens\perfil_jugador_screen.dart"
)

$viejo = "final equipo = await DatabaseHelper.instance.obtenerEquipoPorId(widget.jugador.equipoId);"
$nuevo = "final equipo = widget.jugador.equipoId == null`n          ? null`n          : await DatabaseHelper.instance.obtenerEquipoPorId(widget.jugador.equipoId!);"

try {
  $textos = @{}
  foreach ($a in $archivos) {
    $t = (Get-Content $a -Raw -Encoding UTF8) -replace "`r`n", "`n"
    if ($t.Contains("widget.jugador.equipoId == null")) { throw "Este paso ya se aplico en $a. No se modifico nada." }
    $i = $t.IndexOf($viejo)
    if ($i -lt 0 -or $i -ne $t.LastIndexOf($viejo)) { throw "No se encontro exactamente una vez la linea en $a" }
    $textos[$a] = $t.Substring(0, $i) + $nuevo + $t.Substring($i + $viejo.Length)
  }

  foreach ($a in $archivos) {
    Copy-Item $a "$a.bak_1_4c" -Force
    Set-Content -Path $a -Value ($textos[$a] -replace "`n", "`r`n") -Encoding UTF8 -NoNewline
  }
  Write-Host "OK: perfiles corregidos" -ForegroundColor Green
}
catch {
  Write-Host "ERROR, no se modifico nada: $_" -ForegroundColor Red
}

flutter analyze
