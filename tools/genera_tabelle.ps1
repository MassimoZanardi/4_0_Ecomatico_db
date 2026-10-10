# Rigenera dal database gli script di tabelle e tipi tabella del repo (sql\tables, sql\types): un file per
# oggetto, nel formato di SSMS, con chiave primaria, vincoli, indici e chiavi esterne. Toglie i file delle
# tabelle e dei tipi che nel database non esistono piu'. SP, funzioni e viste non passano da qui: i loro file
# si scrivono a mano e si installano nel database.
#
# Da eseguire dopo ogni modifica alla struttura (colonna, indice, chiave esterna, tabella nuova o tolta), prima
# del commit, cosi' il repo resta sufficiente a ricostruire il database da zero (ricostruisci_database.ps1).
#
# Uso (dalla cartella tools): .\genera_tabelle.ps1 [-Server .\SQLSERVER] [-Database 4_0_ecomatico]
# Richiede SMO (installato con SSMS).
param(
    [string]$Server = '.\SQLSERVER',
    [string]$Database = '4_0_ecomatico'
)

$ErrorActionPreference = 'Stop'

[void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.Smo')
[void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.ConnectionInfo')

$radice = Join-Path (Split-Path -Parent $PSScriptRoot) 'sql'
$srv = New-Object Microsoft.SqlServer.Management.Smo.Server($Server)
$db = $srv.Databases[$Database]
if ($null -eq $db) { throw "Database $Database non trovato su $Server" }

$scripter = New-Object Microsoft.SqlServer.Management.Smo.Scripter($srv)
$o = $scripter.Options
$o.DriAll = $true
$o.Indexes = $true
$o.ClusteredIndexes = $true
$o.NonClusteredIndexes = $true
$o.NoCollation = $false
$o.SchemaQualify = $true
$o.SchemaQualifyForeignKeysReferences = $true
$o.AnsiPadding = $false
$o.IncludeHeaders = $false
$o.ExtendedProperties = $true
$o.Triggers = $true
$o.Statistics = $false
$o.ScriptBatchTerminator = $true
$o.IncludeDatabaseContext = $false
$o.TargetServerVersion = [Microsoft.SqlServer.Management.Smo.SqlServerVersion]::Version160

$utf8Bom = New-Object System.Text.UTF8Encoding($true)

function Scrivi([string]$cartella, $oggetto) {
    $righe = New-Object System.Text.StringBuilder
    foreach ($istruzione in $scripter.Script($oggetto)) {
        $testo = ($istruzione -replace "`r`n", "`n").Trim()
        # Righe vuote attorno a GO come le scrive SSMS, per non cambiare i file gia' nel repo
        $separatore = if ($testo -match '^(CREATE|SET ANSI_PADDING)') { "`n`nGO`n`n" } else { "`nGO`n`n" }
        [void]$righe.Append($testo).Append($separatore)
    }
    $contenuto = ($righe.ToString().TrimEnd() + "`n") -replace "`n", "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $cartella "$($oggetto.Name).sql"), $contenuto, $utf8Bom)
}

function Rigenera([string]$nome, $oggetti) {
    $cartella = Join-Path $radice $nome
    if (-not (Test-Path $cartella)) { [void](New-Item -ItemType Directory $cartella) }
    $nomi = @{}
    foreach ($oggetto in $oggetti) {
        Scrivi $cartella $oggetto
        $nomi[$oggetto.Name] = $true
    }
    $tolti = 0
    foreach ($file in (Get-ChildItem $cartella -Filter *.sql)) {
        if (-not $nomi.ContainsKey($file.BaseName)) {
            Remove-Item -LiteralPath $file.FullName
            Write-Host "  tolto $nome\$($file.Name): non esiste piu' nel database"
            $tolti++
        }
    }
    Write-Host "${nome}: $($nomi.Count) file scritti, $tolti tolti"
}

Rigenera 'tables' ($db.Tables | Where-Object { -not $_.IsSystemObject -and $_.Name -ne 'sysdiagrams' })
Rigenera 'types' ($db.UserDefinedTableTypes | Where-Object { $_.Schema -eq 'dbo' })
