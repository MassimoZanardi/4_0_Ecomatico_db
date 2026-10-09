# Deploy produzione 2026-10-09 - esegue in ordine tutti gli script non ancora in produzione
# (dal tag deployed-prod: fatture, scadenziario, dati fiscali, fattura elettronica XML, MUD numero REA,
# prima nota, esportazione in Excel e CSV di tutti i moduli) e alla fine la verifica CRLF/accenti.
#
# Uso (dalla cartella tools, con autenticazione Windows):
#   .\deploy_produzione_2026-10-09_esegui_tutto.ps1 -Server NOMESERVER\ISTANZA
# Con utente SQL:
#   .\deploy_produzione_2026-10-09_esegui_tutto.ps1 -Server NOMESERVER\ISTANZA -Utente sa -Password ***
# Solo l'elenco degli script, senza eseguire nulla:
#   .\deploy_produzione_2026-10-09_esegui_tutto.ps1 -Server x -SoloElenco
#
# Si ferma al primo errore: gli script sono tutti rieseguibili, dopo la correzione si puo' rilanciare
# dall'inizio oppure dallo script indicato con -Da (numero d'ordine).
# PRIMA: backup del database. DOPO: pubblicare l'app (stessa versione del repo, commit 0ee5f78 o successivo).
param(
    [Parameter(Mandatory = $true)][string]$Server,
    [string]$Database = '4_0_ecomatico',
    [string]$Utente,
    [string]$Password,
    [int]$Da = 1,
    [switch]$SoloElenco
)

$ErrorActionPreference = 'Stop'

$script = @(
    'deploy_produzione_2026-10-07_fatturazione_fatture.sql',
    'deploy_produzione_2026-10-08_fatturazione_scadenziario.sql',
    'deploy_produzione_2026-10-08_fatturazione_dati_fiscali.sql',
    'deploy_produzione_2026-10-08_fatturazione_xml.sql',
    'deploy_produzione_2026-10-09_fatturazione_xml_carica_allegati.sql',
    'deploy_produzione_2026-10-09_fatturazione_prima_nota.sql',
    'deploy_produzione_2026-10-09_fatturazione_esportazione.sql',
    'deploy_produzione_2026-10-09_mud_numero_rea.sql',
    'deploy_produzione_2026-10-09_anagrafica_esportazione.sql',
    'deploy_produzione_2026-10-09_rifiuti_esportazione.sql',
    'deploy_produzione_2026-10-09_magazzino_esportazione.sql',
    'deploy_produzione_2026-10-09_eow_esportazione.sql',
    'deploy_produzione_2026-10-09_scadenze_servizi_rentri_esportazione.sql'
)

$mancanti = @($script + 'verifica_crlf_accenti.sql' | Where-Object { -not (Test-Path (Join-Path $PSScriptRoot $_)) })
if ($mancanti.Count -gt 0) { throw "Script mancanti nella cartella ${PSScriptRoot}: $($mancanti -join ', ')" }

if ($SoloElenco) {
    for ($i = 0; $i -lt $script.Count; $i++) { '{0,2}. {1}' -f ($i + 1), $script[$i] }
    '    verifica_crlf_accenti.sql (deve dare 0 righe)'
    return
}

# -f 65001: i file sono UTF-8; -I: QUOTED_IDENTIFIER ON; -b: errore = codice di uscita diverso da zero
$accesso = if ($Utente) { @('-U', $Utente, '-P', $Password) } else { @('-E') }
$base = @('-S', $Server, '-d', $Database) + $accesso + @('-f', '65001', '-I', '-b')

Write-Host "Server: $Server  Database: $Database" -ForegroundColor Cyan
for ($i = $Da - 1; $i -lt $script.Count; $i++) {
    $nome = $script[$i]
    Write-Host ('[{0}/{1}] {2}' -f ($i + 1), $script.Count, $nome) -ForegroundColor Cyan
    & sqlcmd @base -i (Join-Path $PSScriptRoot $nome)
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERRORE nello script $($i + 1) ($nome): deploy interrotto. Dopo la correzione rilanciare con -Da $($i + 1)" -ForegroundColor Red
        exit 1
    }
}

Write-Host 'Verifica CRLF e accenti (deve dare 0 righe)' -ForegroundColor Cyan
$verifica = & sqlcmd @base -h -1 -W -i (Join-Path $PSScriptRoot 'verifica_crlf_accenti.sql')
if ($LASTEXITCODE -ne 0) { Write-Host 'ERRORE nella verifica' -ForegroundColor Red; exit 1 }
$righe = @($verifica | Where-Object { $_ -and $_.Trim() -ne '' -and $_ -notmatch 'rows? affected' })
if ($righe.Count -gt 0) {
    $righe
    Write-Host "Verifica NON superata: $($righe.Count) oggetti da reinstallare" -ForegroundColor Red
    exit 1
}
Write-Host 'Deploy del database completato: tutti gli script eseguiti, verifica a 0 righe. Ora pubblicare l''app.' -ForegroundColor Green
