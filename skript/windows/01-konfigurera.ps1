# ============================================================================
# 01-konfigurera.ps1: grupper, användare och mappar på Windowsservern (VM 322).
#
# Krav: B1 grupperna, B2 användarna, B3 mapparna, B4/B5/B7 rättigheterna.
# NTFS-ACL med icacls, som B8 kräver.
#
# Körs som administratör på servern. Skriptet tål att köras flera gånger: det
# som redan finns skapas inte igen, men rättigheterna på mapparna sätts om.
#
#   scp -r skript Administrator@10.10.70.118:C:/Windows/Temp/
#   ssh Administrator@10.10.70.118 "powershell -ExecutionPolicy Bypass -File C:\Windows\Temp\skript\windows\01-konfigurera.ps1"
#
# Nycklarna är samma som på Linux och ligger i skript/linux/nycklar.
# ============================================================================
#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

# Utskriften går tillbaka över ssh. Utan raden skickas å, ä och ö i
# serverns gamla teckentabell och blir fel i min terminal, som läser UTF-8.
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$Nyckelmapp = Join-Path $PSScriptRoot '..\linux\nycklar'
$Projekt    = 'C:\Projekt'

# Inbyggda grupper anges med SID, som är samma på alla Windows oavsett språk.
# Namnet kan vara Users eller Användare, men SID:en är alltid densamma.
$SID_SYSTEM = '*S-1-5-18'
$SID_ADMINS = '*S-1-5-32-544'
$SID_USERS  = '*S-1-5-32-545'

# icacls är ett vanligt program och kastar inget fel i PowerShell. Därför
# kontrolleras felkoden efter varje anrop.
function Icacls {
    & icacls.exe @args | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls $args gav felkod $LASTEXITCODE" }
}

function Lagg-Till-Medlem($Grupp, $Medlem) {
    $finns = Get-LocalGroupMember -Name $Grupp | Where-Object { $_.Name -like "*\$Medlem" }
    if (-not $finns) { Add-LocalGroupMember -Name $Grupp -Member $Medlem }
}

# ---------------------------------------------------------------- B1 -------
foreach ($grupp in 'g_ledare', 'g_personal') {
    if (-not (Get-LocalGroup -Name $grupp -ErrorAction SilentlyContinue)) {
        New-LocalGroup -Name $grupp | Out-Null
    }
}

# ---------------------------------------------------------------- B2 -------
# Windows godtar inget konto utan lösenord för inloggning över nätverket.
# Kontot får ett slumpat lösenord som ingen känner till, så det går bara att
# logga in med nyckel, som på Linux.
foreach ($anvandare in 'alice', 'bob') {
    if (-not (Get-LocalUser -Name $anvandare -ErrorAction SilentlyContinue)) {
        $losen = ConvertTo-SecureString ([guid]::NewGuid().ToString() + 'Aa1!') -AsPlainText -Force
        New-LocalUser -Name $anvandare -Password $losen -PasswordNeverExpires | Out-Null
    }
}

# New-LocalUser lägger inte kontot i Users, så det görs här. alice och bob ska
# vara vanliga användare, inte administratörer.
$users = (Get-LocalGroup -SID 'S-1-5-32-545').Name
foreach ($anvandare in 'alice', 'bob') { Lagg-Till-Medlem $users $anvandare }

# alice är med i g_ledare och bob i g_personal, som uppgiften anger.
Lagg-Till-Medlem 'g_ledare'   'alice'
Lagg-Till-Medlem 'g_personal' 'bob'

# En tidigare version lade alice även i g_personal. Det tas bort här, så att
# hennes åtkomst till Gemensamt bara kommer via g_ledare.
if (Get-LocalGroupMember -Name 'g_personal' | Where-Object { $_.Name -like '*\alice' }) {
    Remove-LocalGroupMember -Name 'g_personal' -Member 'alice'
}

# Mallens sshd_config har AllowGroups administrators "openssh users". Utan
# den här gruppen stoppas alice och bob innan nyckeln ens prövas.
foreach ($anvandare in 'alice', 'bob') { Lagg-Till-Medlem 'OpenSSH Users' $anvandare }

# ------------------------------------------------------------- nycklar -----
# C:\Users\alice finns inte förrän alice har loggat in en gång, och hon kan
# inte logga in utan nyckel. Därför får testanvändarna en egen nyckelmapp
# under ProgramData\ssh. Filerna ärver skyddet därifrån: bara SYSTEM och
# Administrators får skriva, annars vägrar sshd filen.
foreach ($anvandare in 'alice', 'bob') {
    $mapp = "C:\ProgramData\ssh\testanvandare\$anvandare"
    New-Item -ItemType Directory -Force -Path $mapp | Out-Null
    Copy-Item "$Nyckelmapp\$anvandare.pub" "$mapp\authorized_keys" -Force
}

# Match User gäller bara alice och bob. %u byts mot användarnamnet, så en rad
# räcker för båda. Blocket måste ligga sist i filen.
$config = 'C:\ProgramData\ssh\sshd_config'
if (-not (Select-String -Path $config -Pattern '^Match User alice,bob' -Quiet)) {
    Copy-Item $config "$config.fore-testanvandare" -Force
    Add-Content -Path $config -Value "`r`nMatch User alice,bob`r`n    AuthorizedKeysFile __PROGRAMDATA__/ssh/testanvandare/%u/authorized_keys"

    # Testa konfigurationen innan omstarten. Är den trasig startar sshd inte,
    # och då stänger man ute sig själv.
    $sshd = (Get-CimInstance Win32_Service -Filter "Name='sshd'").PathName.Trim('"')
    & $sshd -t
    if ($LASTEXITCODE -ne 0) {
        Copy-Item "$config.fore-testanvandare" $config -Force
        throw 'sshd_config blev ogiltig, den gamla filen är återställd'
    }
    Restart-Service sshd
}

# ---------------------------------------------------------------- B3 -------
# En ny mapp ärver allt från C:\. Där får Users läsa allt och skapa filer
# och mappar längre ner, och CREATOR OWNER får full kontroll över det man
# skapar. bob hade då kunnat läsa allt i Ledning. Därför bryts arvet på
# Projekt, och rättigheterna sätts uttryckligen.
New-Item -ItemType Directory -Force -Path $Projekt | Out-Null

# /inheritance:r tar bort det ärvda. /remove tar bort egna rader som blivit
# kvar från när mappen skapades, så att resultatet blir detsamma varje gång.
Icacls $Projekt /inheritance:r /remove:g $SID_ADMINS $SID_SYSTEM $SID_USERS

# SYSTEM och Administrators får full kontroll, och det ärvs nedåt (OI = filer,
# CI = mappar). Users får RX utan OI och CI, alltså bara på Projekt självt:
# alla kan se att Gemensamt och Ledning finns men inte komma in. Som 755 på
# /srv/Projekt.
Icacls $Projekt /grant:r "${SID_SYSTEM}:(OI)(CI)F" "${SID_ADMINS}:(OI)(CI)F" "${SID_USERS}:RX"

# ------------------------------------------------------- B4, B5 och B7 -----
# /reset ger undermappen bara det den ärver från Projekt, så att gamla rader
# försvinner. Sedan läggs grupperna till.
#
# M (Modify) betyder läsa, skriva och radera, som rwx för gruppen på Linux.
#
# I Gemensamt får båda grupperna rättigheter direkt. Det gick inte med chmod
# på Linux, där en mapp bara kan ha en grupp, därför används en ACL
# (setfacl) där.
foreach ($mapp in 'Gemensamt', 'Ledning') {
    New-Item -ItemType Directory -Force -Path "$Projekt\$mapp" | Out-Null
    Icacls "$Projekt\$mapp" /reset
}
Icacls "$Projekt\Gemensamt" /grant 'g_ledare:(OI)(CI)M' 'g_personal:(OI)(CI)M'

# Ledning: bara g_ledare. bob finns inte i någon rad och nekas därför allt.
Icacls "$Projekt\Ledning" /grant 'g_ledare:(OI)(CI)M'

# ---------------------------------------------------------- utskrift -------
'== Grupper och användare'
foreach ($grupp in 'g_ledare', 'g_personal', 'OpenSSH Users') {
    "{0}: {1}" -f $grupp, ((Get-LocalGroupMember -Name $grupp).Name -join ', ')
}
'== Mappar'
foreach ($mapp in $Projekt, "$Projekt\Gemensamt", "$Projekt\Ledning") { icacls.exe $mapp }
