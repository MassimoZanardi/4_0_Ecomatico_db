# Ricostruisce da zero lo schema di 4_0_ecomatico in un database NUOVO e vuoto, dai file del repo:
# sql\types, sql\tables, sql\functions, sql\views, sql\procedures. Nessun dato: solo la struttura.
#
# Uso (dalla cartella tools, con autenticazione Windows):
#   .\ricostruisci_database.ps1 -Server NOMESERVER\ISTANZA -Database 4_0_ecomatico_nuovo
# Con utente SQL:
#   .\ricostruisci_database.ps1 -Server NOMESERVER\ISTANZA -Database 4_0_ecomatico_nuovo -Utente sa -Password ***
#
# Il database non deve esistere: lo script lo crea e non tocca mai un database esistente.
# L'ordine tra i file non conta: ogni istruzione che fallisce perche' dipende da un oggetto non ancora creato
# (chiave esterna verso un'altra tabella, funzione che ne usa un'altra) viene ritentata nei giri successivi,
# finche' un giro non crea piu' nulla. Alla fine elenca le istruzioni rimaste in errore.
# Le viste e le SP che leggono il database 1_0_rentri richiedono che quel database esista sullo stesso server.
# Dopo: confronta_schema.sql confronta il database ricostruito con uno esistente.
param(
    [Parameter(Mandatory = $true)][string]$Server,
    [Parameter(Mandatory = $true)][string]$Database,
    [string]$Collation = 'Latin1_General_CI_AS',
    [string]$Utente,
    [string]$Password
)

$ErrorActionPreference = 'Stop'

if ($Database -notmatch '^[A-Za-z0-9_]+$') { throw "Nome del database non valido: $Database" }

$radice = Join-Path (Split-Path -Parent $PSScriptRoot) 'sql'
$accesso = if ($Utente) { "User ID=$Utente;Password=$Password" } else { 'Integrated Security=True' }

function Apri([string]$db) {
    $c = New-Object System.Data.SqlClient.SqlConnection("Server=$Server;Database=$db;$accesso;TrustServerCertificate=True")
    $c.Open()
    return $c
}

function Esegui($connessione, [string]$sql) {
    $cmd = $connessione.CreateCommand()
    $cmd.CommandText = $sql
    $cmd.CommandTimeout = 300
    [void]$cmd.ExecuteNonQuery()
}

# Il database deve essere nuovo
$master = Apri 'master'
$cmd = $master.CreateCommand()
$cmd.CommandText = 'SELECT COUNT(*) FROM sys.databases WHERE name = @nome'
[void]$cmd.Parameters.AddWithValue('@nome', $Database)
if ([int]$cmd.ExecuteScalar() -gt 0) {
    $master.Close()
    throw "Il database $Database esiste gia': indicare un nome nuovo"
}
Esegui $master "CREATE DATABASE [$Database] COLLATE $Collation"
$master.Close()
Write-Host "Creato il database $Database ($Collation)"

# Istruzioni di tutti i file, separate dalle righe GO. Le righe SET ANSI_NULLS / QUOTED_IDENTIFIER dei file
# non servono: le due opzioni vengono attivate prima di ogni istruzione
$istruzioni = New-Object System.Collections.Generic.List[object]
foreach ($cartella in 'types', 'tables', 'functions', 'views', 'procedures') {
    $percorso = Join-Path $radice $cartella
    if (-not (Test-Path $percorso)) { continue }
    foreach ($file in (Get-ChildItem $percorso -Filter *.sql | Sort-Object Name)) {
        $testo = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
        foreach ($blocco in [regex]::Split($testo, '(?im)^[ \t]*GO[ \t]*;?[ \t]*\r?$')) {
            $sql = $blocco.Trim().TrimStart([char]0xFEFF).Trim()
            if ($sql -eq '') { continue }
            if ($sql -match '(?is)^(\s*SET\s+(ANSI_NULLS|QUOTED_IDENTIFIER)\s+(ON|OFF)\s*;?\s*)+$') { continue }
            $istruzioni.Add([pscustomobject]@{ File = "$cartella\$($file.Name)"; Sql = $sql; Errore = $null })
        }
    }
}
Write-Host "Istruzioni da eseguire: $($istruzioni.Count)"

$db = Apri $Database
$daFare = $istruzioni
$giro = 0
while ($daFare.Count -gt 0) {
    $giro++
    $fallite = New-Object System.Collections.Generic.List[object]
    foreach ($i in $daFare) {
        try {
            Esegui $db 'SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;'
            Esegui $db $i.Sql
        }
        catch {
            $i.Errore = $_.Exception.InnerException.Message
            if (-not $i.Errore) { $i.Errore = $_.Exception.Message }
            $fallite.Add($i)
            # Un errore grave puo' chiudere la connessione
            if ($db.State -ne 'Open') { $db = Apri $Database }
        }
    }
    Write-Host "Giro ${giro}: eseguite $($daFare.Count - $fallite.Count), in errore $($fallite.Count)"
    if ($fallite.Count -eq $daFare.Count) { break }
    $daFare = $fallite
}
$db.Close()

if ($fallite.Count -gt 0) {
    Write-Host ''
    Write-Host "ISTRUZIONI NON ESEGUITE: $($fallite.Count)" -ForegroundColor Red
    foreach ($i in $fallite) { Write-Host "  $($i.File): $($i.Errore)" -ForegroundColor Red }
    exit 1
}
Write-Host "Schema ricostruito in $Database senza errori" -ForegroundColor Green
