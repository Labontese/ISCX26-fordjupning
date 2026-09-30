# ============================================================================
# 02-testa.ps1: testar rättigheterna på Windowsservern som alice och bob.
#
# Krav: B2, B3, B4, B5, B6, B7 och B10. Skriver PASS eller FAIL per test och
# avslutar med felkod 1 om något test misslyckades.
#
# Körs från min dator i PowerShell, inte på servern. Testerna loggar in som
# den riktiga användaren med hennes eller hans egen nyckel, så rättigheterna
# prövas mot användarens egna grupper och inte mot ett administratörskonto.
#
#   powershell -ExecutionPolicy Bypass -File skript\windows\02-testa.ps1 [-Vard adress]
# ============================================================================
param([string]$Vard = '10.10.70.118')

$Projekt = 'C:\Projekt'
$script:Fel = 0

# Koden skickas kodad i base64 (-EncodedCommand). Då slipper man problemen med
# citattecken som ska passera både min PowerShell, ssh och serverns PowerShell.
# IdentitiesOnly=yes gör att ssh bara provar den nyckel jag anger.
function Som($Anvandare, [string]$Kod) {
    $hela = "`$ProgressPreference = 'SilentlyContinue'; `$ErrorActionPreference = 'Stop'; $Kod"
    $b64  = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($hela))
    $ut = & ssh.exe -i "$HOME\.ssh\iscx26_$Anvandare" -o IdentitiesOnly=yes -o BatchMode=yes `
        "$Anvandare@$Vard" "powershell -NoProfile -NonInteractive -EncodedCommand $b64"
    [pscustomobject]@{ Kod = $LASTEXITCODE; Ut = ($ut | Out-String).Trim() }
}

function Skriv($Resultat, $Krav, $Text) {
    '{0,-5} {1,-4} {2}' -f $Resultat, $Krav, $Text
    if ($Resultat -eq 'FAIL') { $script:Fel = 1 }
}

# PASS om handlingen lyckas.
function Ska-Lyckas($Krav, $Text, $Anvandare, [string]$Handling) {
    $r = Som $Anvandare "try { $Handling; 'OK' } catch { 'FEL: ' + `$_ }"
    if ($r.Ut -eq 'OK') { Skriv PASS $Krav $Text }
    else { Skriv FAIL $Krav "$Text ($($r.Ut))" }
}

# PASS bara om handlingen nekas med åtkomstfel. Ett annat fel, till exempel
# att inloggningen misslyckas, ska inte räknas som att nekandet fungerar.
# ssh avslutar med 255 när själva anslutningen misslyckas.
function Ska-Nekas($Krav, $Text, $Anvandare, [string]$Handling) {
    $r = Som $Anvandare "try { $Handling; 'INTE NEKAD' } catch [System.UnauthorizedAccessException] { 'NEKAD' } catch { 'ANNAT: ' + `$_ }"
    if ($r.Kod -eq 255)         { Skriv FAIL $Krav "$Text (inloggningen misslyckades)" }
    elseif ($r.Ut -eq 'NEKAD')  { Skriv PASS $Krav $Text }
    else                        { Skriv FAIL $Krav "$Text ($($r.Ut))" }
}

# Kastar ett fel om den inloggade användaren inte är med i gruppen.
$Grupp = 'function Grupper { [Security.Principal.WindowsIdentity]::GetCurrent().Groups | ForEach-Object { $_.Translate([Security.Principal.NTAccount]).Value } }'

# Kastar ett fel om gruppen saknar Modify på mappen.
$Modify = 'function Har-Modify($s, $g) { if (-not ((Get-Acl $s).Access | Where-Object { $_.IdentityReference.Value -like "*\$g" -and $_.FileSystemRights -match "Modify" })) { throw "$g saknar Modify på $s" } }'

# ---------------------------------------------------------------- B2 -------
Ska-Lyckas B2 'alice är med i g_ledare och g_personal' alice `
    "$Grupp; `$g = Grupper; if (-not (`$g -like '*\g_ledare') -or -not (`$g -like '*\g_personal')) { throw `$g }"
Ska-Lyckas B2 'bob är med i g_personal men inte i g_ledare' bob `
    "$Grupp; `$g = Grupper; if (-not (`$g -like '*\g_personal') -or (`$g -like '*\g_ledare')) { throw `$g }"
Ska-Lyckas B2 'alice är inte administratör' alice `
    "if ([Security.Principal.WindowsIdentity]::GetCurrent().Groups.Value -contains 'S-1-5-32-544') { throw 'alice är administratör' }"
Ska-Lyckas B2 'bob är inte administratör' bob `
    "if ([Security.Principal.WindowsIdentity]::GetCurrent().Groups.Value -contains 'S-1-5-32-544') { throw 'bob är administratör' }"

# ---------------------------------------------------------------- B3 -------
# Arvet från C:\ ska vara brutet på Projekt, annars får Users läsa allt.
Ska-Lyckas B3 'Projekt: arvet från C:\ är brutet' alice `
    "if (-not (Get-Acl $Projekt).AreAccessRulesProtected) { throw 'arvet är kvar' }"
Ska-Lyckas B3 'Gemensamt: g_ledare och g_personal har Modify' alice `
    "$Modify; Har-Modify $Projekt\Gemensamt g_ledare; Har-Modify $Projekt\Gemensamt g_personal"
Ska-Lyckas B3 'Ledning: g_ledare har Modify, ingen annan grupp' alice `
    "$Modify; Har-Modify $Projekt\Ledning g_ledare; if ((Get-Acl $Projekt\Ledning).Access.IdentityReference.Value -match 'g_personal|\\Users$') { throw 'för många rader' }"

# ---------------------------------------------------------------- B4 -------
Ska-Lyckas B4 'alice läser och skriver i Gemensamt' alice `
    "Set-Content $Projekt\Gemensamt\b4-alice.txt 'alice'; Get-Content $Projekt\Gemensamt\b4-alice.txt | Out-Null"
Ska-Lyckas B4 'bob läser och skriver i Gemensamt' bob `
    "Set-Content $Projekt\Gemensamt\b4-bob.txt 'bob'; Get-Content $Projekt\Gemensamt\b4-bob.txt | Out-Null"

# ---------------------------------------------------------------- B6 -------
# alice skapar filen och bob lägger till en rad. Det fungerar för att filen
# ärver mappens rättigheter, där g_personal har Modify. Ingen setgid eller
# umask behövs, som på Linux.
Ska-Lyckas B6 'alice skapar testfilen i Gemensamt' alice `
    "Set-Content $Projekt\Gemensamt\b6-testfil.txt 'alice skrev'"
Ska-Lyckas B6 'bob redigerar samma fil' bob `
    "Add-Content $Projekt\Gemensamt\b6-testfil.txt 'bob skrev'"
Ska-Lyckas B6 'filen innehåller båda raderna' alice `
    "`$t = Get-Content $Projekt\Gemensamt\b6-testfil.txt; if (`$t -notcontains 'alice skrev' -or `$t -notcontains 'bob skrev') { throw (`$t -join '|') }"

# ------------------------------------------------------------ B5, B7 -------
Ska-Lyckas B5 'alice läser och skriver i Ledning' alice `
    "Set-Content $Projekt\Ledning\b5-plan.txt 'hemligt'; Get-Content $Projekt\Ledning\b5-plan.txt | Out-Null"
Ska-Nekas  B7 'bob kan inte lista Ledning' bob `
    "Get-ChildItem $Projekt\Ledning | Out-Null"
Ska-Nekas  B7 'bob kan inte skriva i Ledning' bob `
    "Set-Content $Projekt\Ledning\b7-bob.txt 'bob'"
Ska-Nekas  B7 'bob kan inte läsa en fil i Ledning' bob `
    "Get-Content $Projekt\Ledning\b5-plan.txt | Out-Null"

# --------------------------------------------------------------- B10 -------
# Ägaren blir den som skapar filen, som på Linux. Men alice får ingen egen
# rad i ACL:en för att hon är ägare. Allt filen har är ärvt (I) från
# Gemensamt, och där har båda grupperna Modify.
Ska-Lyckas B10 'alice nya fil: ägare alice, bara ärvda rader' alice `
    "`$f = '$Projekt\Gemensamt\b10-ny.txt'; if (Test-Path `$f) { Remove-Item `$f }; New-Item `$f | Out-Null; `$a = Get-Acl `$f; if (`$a.Owner -notlike '*\alice') { throw `$a.Owner }; if (`$a.Access | Where-Object { -not `$_.IsInherited }) { throw 'egna rader finns' }"

''
'== Bevis för B10'
(Som alice "`$a = Get-Acl $Projekt\Gemensamt\b10-ny.txt; 'Owner: ' + `$a.Owner; 'Group: ' + `$a.Group; icacls $Projekt\Gemensamt\b10-ny.txt | Select-Object -SkipLast 2").Ut

''
if ($script:Fel -eq 0) { 'Alla test PASS' } else { 'Minst ett test FAIL' }
exit $script:Fel
