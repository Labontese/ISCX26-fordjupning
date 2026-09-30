#!/usr/bin/env bash
# ============================================================================
# 01-konfigurera.sh: grupper, användare och mappar på Linuxservern (VM 321).
#
# Krav: B1 grupperna, B2 användarna, B3 mapparna, B4/B5/B7 rättigheterna.
# Bara POSIX-behörigheter med chmod och chown, som B8 kräver. Ingen ACL.
#
# Körs som root på servern. Skriptet tål att köras flera gånger: det som
# redan finns skapas inte igen, men ägare och rättigheter sätts om varje gång.
#
#   scp -r skript/linux daniel@10.10.70.117:/tmp/
#   ssh daniel@10.10.70.117 "sudo bash /tmp/linux/01-konfigurera.sh"
#
# De publika nycklarna ligger i nycklar/ bredvid skriptet. En annan tekniker
# byter ut dem mot sina egna testnycklar.
# ============================================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Kör skriptet som root, till exempel med sudo." >&2
  exit 1
fi

KATALOG="$(cd "$(dirname "$0")" && pwd)"
PROJEKT=/srv/Projekt

# ---------------------------------------------------------------- B1 -------
for grupp in g_ledare g_personal; do
  getent group "$grupp" >/dev/null || groupadd "$grupp"
done

# ---------------------------------------------------------------- B2 -------
# alice är med i både g_ledare och g_personal. B2 säger att hon är med i
# g_ledare men förbjuder inte fler grupper, och med bara chmod/chown kan en
# mapp bara ha en grupp. Hon måste vara med i g_personal för att komma åt
# Gemensamt. En ledare räknas också som personal.
#
# -m skapar hemkatalogen, som behövs för ~/.ssh. Inget lösenord sätts, så
# kontot kan bara nås med nyckel.
for anvandare in alice bob; do
  id "$anvandare" >/dev/null 2>&1 || useradd -m -s /bin/bash "$anvandare"
done

# -a betyder lägg till. Utan -a byts alla extra grupper ut, och alice
# skulle åka ur g_ledare.
usermod -aG g_ledare,g_personal alice
usermod -aG g_personal bob

# En egen nyckel per testanvändare, så att det syns vem som gjorde vad.
# 700 på mappen och 600 på filen, annars vägrar sshd nyckeln (StrictModes).
# .hushlogin stänger av välkomsttexten så att testutskrifterna blir rena.
for anvandare in alice bob; do
  install -d -m 700 -o "$anvandare" -g "$anvandare" "/home/$anvandare/.ssh"
  install -m 600 -o "$anvandare" -g "$anvandare" \
    "$KATALOG/nycklar/$anvandare.pub" "/home/$anvandare/.ssh/authorized_keys"
  install -m 644 -o "$anvandare" -g "$anvandare" /dev/null "/home/$anvandare/.hushlogin"
done

# ---------------------------------------------------------------- B3 -------
# /srv för att det är lätt att hålla isär delade filer för administration
# och backup, och lätt att veta var känslig data ligger. Enligt FHS är /srv
# data som servern delar ut.
mkdir -p "$PROJEKT/Gemensamt" "$PROJEKT/Ledning"

# 755 på Projekt: alla kan se att Gemensamt och Ledning finns, men bara
# gruppens medlemmar kommer in i dem. 711 hade dolt namnen också, men det
# behövs inte här.
chown root:root "$PROJEKT"
chmod 755 "$PROJEKT"

# ------------------------------------------------------- B4, B5 och B7 -----
# Den första siffran styr specialbitarna: 4 = setuid, 2 = setgid, 1 = sticky.
# 2:an sätter setgid på mappen. Då får nya filer och undermappar som skapas
# där mappens grupp i stället för skaparens primära grupp.
#
# 7 ger ägaren (root) rwx, nästa 7 ger gruppen rwx, och 0 ger övriga
# ingenting. Det är för att bara gruppens medlemmar ska komma åt mappen.
#
# bob är inte ägare och inte med i g_ledare, så han räknas som övriga i
# Ledning och får Permission denied. Rättigheterna på mappen kontrolleras
# före rättigheterna på filerna, så det spelar ingen roll vad filerna
# inuti har för rättigheter.
chown root:g_personal "$PROJEKT/Gemensamt"
chmod 2770 "$PROJEKT/Gemensamt"

chown root:g_ledare "$PROJEKT/Ledning"
chmod 2770 "$PROJEKT/Ledning"

# ---------------------------------------------------------- utskrift -------
echo "== Grupper och användare"
getent group g_ledare g_personal
id alice
id bob
echo "== Mappar"
ls -ld "$PROJEKT" "$PROJEKT"/*
