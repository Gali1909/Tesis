# 1.4c (ajuste) - Tocar un jugador libre abre su perfil
# Ejecutar desde la raiz del proyecto (C:\Tesis\App_movil\entrenador_app)

$archivo = "lib\screens\jugadores_libres_screen.dart"

function Reemplazar($texto, $viejo, $nuevo) {
  $i = $texto.IndexOf($viejo)
  if ($i -lt 0 -or $i -ne $texto.LastIndexOf($viejo)) { throw "No se encontro exactamente una vez: $viejo" }
  return $texto.Substring(0, $i) + $nuevo + $texto.Substring($i + $viejo.Length)
}

try {
  $t = (Get-Content $archivo -Raw -Encoding UTF8) -replace "`r`n", "`n"
  if ($t.Contains("perfil_jugador_screen.dart")) { throw "Este paso ya se aplico. No se modifico nada." }

  # 1. import de la pantalla de perfil
  $t = Reemplazar $t "import '../services/database_helper.dart';" "import '../services/database_helper.dart';`nimport 'perfil_jugador_screen.dart';"

  # 2. al tocar la fila se abre el perfil y al volver se recarga la lista
  $onTap = @'
return ListTile(
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PerfilJugadorScreen(jugador: j),
              ),
            );
            if (!mounted) return;
            _cargar();
          },
'@
  $t = Reemplazar $t "return ListTile(" (($onTap -replace "`r`n", "`n").TrimEnd("`n"))

  Copy-Item $archivo "$archivo.bak_perfil" -Force
  Set-Content -Path $archivo -Value ($t -replace "`n", "`r`n") -Encoding UTF8 -NoNewline
  Write-Host "OK: jugadores libres abre el perfil" -ForegroundColor Green
}
catch {
  Write-Host "ERROR, no se modifico nada: $_" -ForegroundColor Red
}

flutter analyze
