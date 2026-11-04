# aplicar_vistas.ps1  -  Instala perfil_vistas (P4) y reenvio de la trama 0x16 (P4 + C6).
# Uso: dejar este script, perfil_vistas.c y perfil_vistas.h en la misma carpeta y ejecutarlo.
$ErrorActionPreference = "Stop"
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
$p4   = "C:\Tesis\Entrenador\Out\Entrenador\main"
$c6   = "C:\Tesis\Entrenador\Out\c6_espnow_bridge\main\main.c"
$sello = Get-Date -Format "yyyyMMdd_HHmmss"
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Copiar($origen, $destino) {
    if (-not (Test-Path $origen)) { throw "No encuentro $origen" }
    if (Test-Path $destino) { Copy-Item $destino "$destino.$sello.bak" }
    Copy-Item $origen $destino -Force
    Write-Host "Copiado: $destino" -ForegroundColor Green
}

# Reemplazo exacto de una linea; avisa si ya estaba aplicado o si no la encuentra.
function Parchear($archivo, $buscar, $nuevo, $marca) {
    $t = [IO.File]::ReadAllText($archivo)
    if ($t.Contains($marca)) { Write-Host "  ya aplicado: $marca" -ForegroundColor Yellow; return }
    if (-not $t.Contains($buscar)) { Write-Host "  NO ENCONTRE en $(Split-Path -Leaf $archivo): $buscar" -ForegroundColor Red; return }
    $i = $t.IndexOf($buscar)
    $t = $t.Substring(0, $i) + $nuevo + $t.Substring($i + $buscar.Length)
    [IO.File]::WriteAllText($archivo, $t, $utf8)
    Write-Host "  OK: $marca" -ForegroundColor Green
}

function Respaldo($archivo) {
    if (-not (Test-Path $archivo)) { throw "No existe $archivo" }
    Copy-Item $archivo "$archivo.$sello.bak"
    Write-Host "Parchando $archivo"
}

# 1) Archivos nuevos
Copiar "$aqui\perfil_vistas.c" "$p4\perfil_vistas.c"
Copiar "$aqui\perfil_vistas.h" "$p4\include\perfil_vistas.h"

# 2) uart_bridge.h y uart_bridge.c
Respaldo "$p4\include\uart_bridge.h"
Parchear "$p4\include\uart_bridge.h" "#define UART_MSG_PERFIL_DATOS  0x15" `
 "#define UART_MSG_PERFIL_DATOS  0x15`r`n#define UART_MSG_PERFIL_VISTA  0x16   /* vista de estadisticas del perfil */" "UART_MSG_PERFIL_VISTA"

Respaldo "$p4\uart_bridge.c"
Parchear "$p4\uart_bridge.c" "tipo == UART_MSG_QUITAR_PERFIL || tipo == UART_MSG_PERFIL_DATOS))" `
 "tipo == UART_MSG_QUITAR_PERFIL || tipo == UART_MSG_PERFIL_DATOS || tipo == UART_MSG_PERFIL_VISTA))" "tipo == UART_MSG_PERFIL_VISTA))"

# 3) perfil_lanzador_rx.c
Respaldo "$p4\perfil_lanzador_rx.c"
Parchear "$p4\perfil_lanzador_rx.c" '#include "perfil_lanzador_rx.h"' `
 "#include `"perfil_lanzador_rx.h`"`r`n#include `"perfil_vistas.h`"" '#include "perfil_vistas.h"'
Parchear "$p4\perfil_lanzador_rx.c" "if (tipo == UART_MSG_QUITAR_PERFIL) {" `
 "if (tipo == UART_MSG_PERFIL_VISTA) { perfil_vistas_on_frame(p, len); return; }`r`n    if (tipo == UART_MSG_QUITAR_PERFIL) {`r`n        perfil_vistas_borrar();" "perfil_vistas_on_frame(p, len)"
Parchear "$p4\perfil_lanzador_rx.c" "    bool hay, dirty;" `
 "    perfil_vistas_ui_tick();`r`n    bool hay, dirty;" "perfil_vistas_ui_tick();"

# 4) perfil_lanzador_ui.c
Respaldo "$p4\perfil_lanzador_ui.c"
Parchear "$p4\perfil_lanzador_ui.c" '#include "perfil_lanzador_ui.h"' `
 "#include `"perfil_lanzador_ui.h`"`r`n#include `"perfil_vistas.h`"" '#include "perfil_vistas.h"'
Parchear "$p4\perfil_lanzador_ui.c" "    if (vista_es(&v)) reset_vista(&v, false);" `
 "    perfil_vistas_ui_ocultar();`r`n    if (vista_es(&v)) reset_vista(&v, false);" "perfil_vistas_ui_ocultar();"
Parchear "$p4\perfil_lanzador_ui.c" "    if (vista_en(&v)) aplicar(&v, true, p);" `
 "    if (vista_en(&v)) aplicar(&v, true, p);`r`n    perfil_vistas_ui_mostrar();" "perfil_vistas_ui_mostrar();"

# 5) CMakeLists.txt de main (agrega perfil_vistas.c junto a perfil_lanzador_rx.c)
$cmake = "$p4\CMakeLists.txt"
Respaldo $cmake
Parchear $cmake '"perfil_lanzador_rx.c"' '"perfil_lanzador_rx.c" "perfil_vistas.c"' '"perfil_vistas.c"'

# 6) C6: reenviar la trama 0x16
Respaldo $c6
Parchear $c6 "#define APP_T_PERFIL_DATOS   0x15" `
 "#define APP_T_PERFIL_DATOS   0x15`r`n#define APP_T_PERFIL_VISTA   0x16" "APP_T_PERFIL_VISTA   0x16"
Parchear $c6 "} else if (tipo == APP_T_PERFIL_DATOS) {" `
 "} else if (tipo == APP_T_PERFIL_VISTA) {`r`n        if (largo < 5 || largo > MAX_PAYLOAD) {`r`n            ESP_LOGW(TAG, `"Vista 0x16 con largo invalido (%u)`", (unsigned)largo);`r`n            estado = 3;`r`n        } else {`r`n            enviar_trama_uart(APP_T_PERFIL_VISTA, p, (uint8_t)largo);`r`n        }`r`n    } else if (tipo == APP_T_PERFIL_DATOS) {" "tipo == APP_T_PERFIL_VISTA"

Write-Host "`nListo. Si algun paso dice NO ENCONTRE, pegame esa linea." -ForegroundColor Cyan
Write-Host "Ahora: en el P4 'idf.py fullclean build' y en el C6 compila y flashea de nuevo."
