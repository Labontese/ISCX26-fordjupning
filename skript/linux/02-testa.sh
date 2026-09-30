#!/usr/bin/env bash
# ============================================================================
# 02-testa.sh: testar rättigheterna på Linuxservern som alice och bob.
#
# Krav: B2, B3, B4, B5, B6, B7 och B10. Skriver PASS eller FAIL per test och
# avslutar med felkod 1 om något test misslyckades.
#
# Körs från min dator i Git Bash, inte på servern. Testerna loggar in som
# den riktiga användaren med hennes eller hans egen nyckel, så rättigheterna
# prövas mot användarens egna grupper och inte mot ett administratörskonto.
#
#   bash skript/linux/02-testa.sh [adress]
#
# Kör det i Git Bash. Skriver man bash i PowerShell startar Windows WSL i
# stället, en egen Linux utan mina testnycklar, och då blir allt FAIL.
# ============================================================================
set -uo pipefail   # inte -e: ett misslyckat test ska inte stoppa resten

VARD="${1:-10.10.70.120}"
PROJEKT=/srv/Projekt
FEL=0

# Kör ett kommando på servern som en testanvändare. IdentitiesOnly=yes gör
# att ssh bara provar den nyckel jag anger, annars erbjuder agenten min
# vanliga nyckel först och då vet jag inte vilken nyckel som loggade in.
som() {
  local anvandare=$1; shift
  ssh -i "$HOME/.ssh/iscx26_$anvandare" -o IdentitiesOnly=yes -o BatchMode=yes \
    "$anvandare@$VARD" "$@"
}

# PASS om kommandot lyckas.
ska_lyckas() {
  local krav=$1 text=$2; shift 2
  if "$@" >/dev/null 2>&1; then echo "PASS  $krav  $text"
  else echo "FAIL  $krav  $text"; FEL=1; fi
}

# PASS bara om kommandot nekas med Permission denied. Ett annat fel, till
# exempel att inloggningen misslyckas, ska inte räknas som att nekandet
# fungerar. ssh avslutar med 255 när själva anslutningen misslyckas, och
# skriver då också "Permission denied (publickey)", så felkoden kollas först.
ska_nekas() {
  local krav=$1 text=$2 utdata kod; shift 2
  utdata=$("$@" 2>&1); kod=$?
  if [[ $kod -eq 0 ]]; then echo "FAIL  $krav  $text (tilläts)"; FEL=1
  elif [[ $kod -eq 255 ]]; then echo "FAIL  $krav  $text (inloggningen misslyckades)"; FEL=1
  elif grep -q "Permission denied" <<<"$utdata"; then echo "PASS  $krav  $text"
  else echo "FAIL  $krav  $text (annat fel: $utdata)"; FEL=1; fi
}

# ---------------------------------------------------------------- B2 -------
ska_lyckas B2 "alice är med i g_ledare" \
  som alice 'id -nG | grep -qw g_ledare'
ska_lyckas B2 "alice är inte med i g_personal" \
  som alice '! id -nG | grep -qw g_personal'
ska_lyckas B2 "bob är med i g_personal" \
  som bob 'id -nG | grep -qw g_personal'
ska_lyckas B2 "bob är inte med i g_ledare" \
  som bob '! id -nG | grep -qw g_ledare'

# ---------------------------------------------------------------- B3 -------
# Utskriften från stat ska vara exakt så här. s på gruppens x-plats betyder
# att setgid är satt och att gruppen har x.
ska_lyckas B3 "Projekt drwxr-xr-x root root" \
  som alice "[ \"\$(stat -c '%A %U %G' $PROJEKT)\" = 'drwxr-xr-x root root' ]"
ska_lyckas B3 "Gemensamt drwxrws--- root g_personal" \
  som alice "[ \"\$(stat -c '%A %U %G' $PROJEKT/Gemensamt)\" = 'drwxrws--- root g_personal' ]"
ska_lyckas B3 "Ledning drwxrws--- root g_ledare" \
  som alice "[ \"\$(stat -c '%A %U %G' $PROJEKT/Ledning)\" = 'drwxrws--- root g_ledare' ]"
ska_lyckas B3 "Gemensamt har ACL-rad och standard-ACL för g_ledare" \
  som alice "getfacl -p $PROJEKT/Gemensamt | grep -qx 'group:g_ledare:rwx' && getfacl -p $PROJEKT/Gemensamt | grep -qx 'default:group:g_ledare:rwx'"

# ---------------------------------------------------------------- B4 -------
ska_lyckas B4 "alice läser och skriver i Gemensamt" \
  som alice "echo alice > $PROJEKT/Gemensamt/b4-alice.txt && cat $PROJEKT/Gemensamt/b4-alice.txt"
ska_lyckas B4 "bob läser och skriver i Gemensamt" \
  som bob "echo bob > $PROJEKT/Gemensamt/b4-bob.txt && cat $PROJEKT/Gemensamt/b4-bob.txt"

# ---------------------------------------------------------------- B6 -------
# alice skapar filen och bob lägger till en rad. setgid ger filen gruppen
# g_personal, och standard-ACL:en på Gemensamt ger både g_personal och
# g_ledare skrivrätt på nya filer. Filen tas bort först, så att den skapas
# på nytt och får rättigheterna från standard-ACL:en.
ska_lyckas B6 "alice skapar testfilen i Gemensamt" \
  som alice "rm -f $PROJEKT/Gemensamt/b6-testfil.txt && echo 'rad från alice' > $PROJEKT/Gemensamt/b6-testfil.txt"
ska_lyckas B6 "bob redigerar samma fil" \
  som bob "echo 'rad från bob' >> $PROJEKT/Gemensamt/b6-testfil.txt"
ska_lyckas B6 "filen innehåller båda raderna" \
  som alice "grep -q 'rad från alice' $PROJEKT/Gemensamt/b6-testfil.txt && grep -q 'rad från bob' $PROJEKT/Gemensamt/b6-testfil.txt"

# Åt andra hållet: bob skapar och alice redigerar. alice är inte med i
# g_personal, så det fungerar bara tack vare raden för g_ledare i
# standard-ACL:en.
ska_lyckas B6 "bob skapar en fil som alice redigerar" \
  som bob "rm -f $PROJEKT/Gemensamt/b6-bob.txt && echo 'rad från bob' > $PROJEKT/Gemensamt/b6-bob.txt"
ska_lyckas B6 "alice redigerar bobs fil" \
  som alice "echo 'rad från alice' >> $PROJEKT/Gemensamt/b6-bob.txt"

# ------------------------------------------------------------ B5, B7 -------
ska_lyckas B5 "alice läser och skriver i Ledning" \
  som alice "echo hemligt > $PROJEKT/Ledning/b5-plan.txt && cat $PROJEKT/Ledning/b5-plan.txt"
ska_nekas  B7 "bob kan inte lista Ledning" \
  som bob "ls $PROJEKT/Ledning"
ska_nekas  B7 "bob kan inte skriva i Ledning" \
  som bob "echo bob > $PROJEKT/Ledning/b7-bob.txt"
ska_nekas  B7 "bob kan inte läsa en fil i Ledning" \
  som bob "cat $PROJEKT/Ledning/b5-plan.txt"

# --------------------------------------------------------------- B10 -------
# Ägaren blir den som skapar filen. Gruppen blir normalt skaparens primära
# grupp, den som står vid gid=, alltså alice. Men setgid på Gemensamt gör
# att filen får mappens grupp, g_personal. Standard-ACL:en ger dessutom
# filen en rad för g_ledare, och övriga får ingenting.
ska_lyckas B10 "alice nya fil: ägare alice, grupp g_personal, rad för g_ledare" \
  som alice "rm -f $PROJEKT/Gemensamt/b10-ny.txt && touch $PROJEKT/Gemensamt/b10-ny.txt && [ \"\$(stat -c '%A %U %G' $PROJEKT/Gemensamt/b10-ny.txt)\" = '-rw-rw---- alice g_personal' ] && getfacl -p $PROJEKT/Gemensamt/b10-ny.txt | grep -q '^group:g_ledare:rw'"

echo
echo "== Bevis för B10"
som alice "ls -l $PROJEKT/Gemensamt/b10-ny.txt; getfacl -p $PROJEKT/Gemensamt/b10-ny.txt"

echo
if [[ $FEL -eq 0 ]]; then echo "Alla test PASS"; else echo "Minst ett test FAIL"; fi
exit $FEL
