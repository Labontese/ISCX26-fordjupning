# ISCX26: Individuell fördjupning (VG-underlag)

Kurs: Introduktion till yrkesrollen och grunderna i IT-infrastruktur
(MYH 2025/4008). Kursmål 2, 3 och 8.

Det här repot är min rapport. Den bygger vidare på labbmiljön från kursens
inlämningsuppgift, där labbmiljön byggdes med Terraform på Proxmox. Här
skapas två nya maskiner med samma arbetssätt: en Linuxserver och en
Windowsserver på samma driftnät. Kurs 1-maskinerna står orörda.

Arbetet är gjort individuellt.

## Rapporten

| Moment | Kursmål | Dokument |
|---|---|---|
| A: Nätverksanalys och trafikflöden | 3 | [Trafikflödet från klient till internet](dokumentation/forklaring/trafikflode.md) |
| B: OS- och behörighetsanalys | 2 | [Rättigheter i Linux och Windows](dokumentation/forklaring/rattigheter-linux-windows.md) |
| B: Uppsättning av behörighetsstrukturen | 2 | [Återställ och driv miljön](dokumentation/instruktion/aterstall-miljon.md), steg 2 till 4 |
| C: Spårbarhet och överlämning | 8 | [Miljön: referens](dokumentation/referens/miljon.md), [Återställ och driv miljön](dokumentation/instruktion/aterstall-miljon.md) och [Återställningsprov](dokumentation/referens/aterstallningsprov.md) |

Dokumentationen är ordnad efter Diátaxis: förklaringar (varför), instruktioner
(hur man gör) och referens (vad som finns).

## Kod och skript

| Sökväg | Innehåll |
|---|---|
| [`terraform/`](terraform/) | Maskinerna som kod: VM 321 (Linux) och VM 322 (Windows) |
| [`skript/linux/01-konfigurera.sh`](skript/linux/01-konfigurera.sh) | Grupper, användare och mappar i Linux |
| [`skript/linux/02-testa.sh`](skript/linux/02-testa.sh) | Testar rättigheterna i Linux som alice och bob |
| [`skript/windows/01-konfigurera.ps1`](skript/windows/01-konfigurera.ps1) | Grupper, användare och mappar i Windows |
| [`skript/windows/02-testa.ps1`](skript/windows/02-testa.ps1) | Testar rättigheterna i Windows som alice och bob |

## Kravnumren i testerna

Testskripten märker varje test med ett nummer. Numren är mina egna och hör
till specifikationen för Moment B så här:

| Nummer | Krav i uppgiften |
|---|---|
| B1 | Grupperna g_ledare och g_personal |
| B2 | alice är medlem i g_ledare, bob i g_personal |
| B3 | Projekt med undermapparna Gemensamt och Ledning |
| B4 | Gemensamt: båda grupperna läsa och skriva |
| B5 | Ledning: g_ledare läsa och skriva |
| B6 | En testfil i Gemensamt som båda kan redigera |
| B7 | g_personal nekas tillträde till Ledning |
| B8 | POSIX-behörigheter i Linux, NTFS-ACL i Windows |
| B9 | Analysen av skillnaderna |
| B10 | Vilken grupp och ägare en ny fil får (arv vid nya filer) |

## AI-användning

Jag har använt en AI-assistent (Claude) som stöd för lärandet, på det sätt
kursen beskriver. Så här fördelades arbetet:

| Jag | AI-assistenten |
|---|---|
| Byggde behörighetsstrukturen för hand i båda systemen och gjorde mätningarna för Moment A | Förklarade mekanismerna steg för steg och ställde kontrollfrågor |
| Tog besluten, till exempel ACL på Gemensamt och fast adress med `dhcp-identifier: mac` | Föreslog alternativ med för- och nackdelar |
| Skrev resonemangen i förklaringarna | Faktagranskade dem mot mätningarna och källorna och påpekade fel |
| Granskade och körde skripten och gjorde det första återställningsprovet enligt instruktionen | Skrev utkast till skripten, instruktionen och referensen |
| Hämtade länkarna till källorna | Föreslog källor och kontrollerade att länkarna fungerar och säger det som påstås |
| | Körde också kommandon i labbmiljön: `terraform apply`, testskripten, ett test av sökvägskontroll i båda systemen och de två sista ombyggnaderna av Linuxservern |

Alla påståenden i rapporten är kontrollerade mot en mätning i labbmiljön
eller en primärkälla (man-sida, RFC eller Microsoft Learn).
