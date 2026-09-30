# Återställningsprov

Uppgiften frågar: "Kan en extern tekniker ta över och återställa miljön
enbart utifrån detta dokument utan att behöva ställa frågor?" För att pröva
det revs Linuxservern och byggdes upp igen enbart genom att följa
[Återställ och driv miljön](../instruktion/aterstall-miljon.md), avsnittet
Bygga om en maskin och steg 2 och 4.

## Prov 1, 30 september 2026

Linuxservern (VM 321) revs och byggdes om med
`terraform apply -replace="proxmox_virtual_environment_vm.linux"`.
Konfigurationsskriptet och testskriptet kördes enligt instruktionen.

Resultat: `Alla test PASS`, 20 av 20. Två brister hittades.

| Brist | Orsak | Åtgärd |
|---|---|---|
| Maskinen fick 10.10.70.121 i stället för 10.10.70.117 | Ubuntu identifierar sig för DHCP med ett id som räknas fram ur machine-id (`CLIENTID=ffca5309…`). En ombyggd maskin får ett nytt machine-id, och DHCP ger då en ny adress, trots samma MAC-adress | `dhcp-identifier: mac` i `terraform/cloud-init/linux-networkdata.yaml` |
| `cloud-init status` gav `error` | Paketet `dnsutils` finns inte i Ubuntu 26.04. Det heter `bind9-dnsutils` | Paketnamnet bytt i `terraform/cloud-init/linux-userdata.yaml.tftpl` |

Instruktionen fångade den första bristen: den säger att adressen ska läsas
av i Proxmox, och testet kördes mot den adress som syntes där. Den andra
bristen hade funnits sedan första bygget, men syntes först när steg 2
förväntade sig `status: done`.

## Prov 2 och 3, 30 september 2026

Efter åtgärderna byggdes Linuxservern om två gånger till.

Prov 2 gav 10.10.70.120. Klienten identifierade sig nu med MAC-adressen,
som DHCP såg som en ny klient:

```text
ADDRESS=10.10.70.120
CLIENTID=01bc241100d321
```

Prov 3 gav samma adress trots ett nytt machine-id, och cloud-init blev
klart utan fel:

```text
status: done
ADDRESS=10.10.70.120
CLIENTID=01bc241100d321
bdaebb6ce5f3470096b63b537963dd10
```

Konfigurationsskriptet och testskriptet kördes igen: `Alla test PASS`.

## Windowsservern

Windowsservern byggdes inte om i provet, eftersom den inte har ändrats.
Den byggdes första gången med samma steg som står i instruktionen, steg 1
och 3, och klarar `02-testa.ps1` med 19 av 19 PASS.
