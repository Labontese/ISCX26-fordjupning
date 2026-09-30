# Återställ och driv miljön

Den här instruktionen bygger upp VG-miljön från noll: Linuxservern (VM 321)
och Windowsservern (VM 322) med samma behörighetsstruktur. Den visar också
hur miljön kontrolleras och sköts. Vad som finns och vad miljön är beroende
av står i [Miljön: referens](../referens/miljon.md).

Alla kommandon körs från administratörens Windows-dator om inget annat
anges. Det står vid varje steg vilket skal som ska användas: **PowerShell**
eller **Git Bash**. Det spelar roll, se felsökningen.

## Innan du börjar

### Det här behöver du ha

| Vad | Kontrollera med |
|---|---|
| Terraform 1.14 eller senare | `terraform version` |
| Git for Windows, som ger Git Bash | Git Bash finns i Startmenyn |
| OpenSSH-klienten i Windows | `ssh -V` i PowerShell |
| Nätåtkomst till 10.10.0.3 (Proxmox) och 10.10.70.0/24 | `ping 10.10.0.3` |
| Beroendena i referensen: Proxmox, mallarna 9001 och 9010, pfSense och DNS | se [referensen](../referens/miljon.md#beroenden) |

### Det här ska lämnas över separat

Hemligheter finns inte i repot. Den som tar över miljön ska få:

1. API-token för `terraform@pve!provider` (id och hemlighet).
2. Maskinnyckeln för SSH mot Proxmox, eller rätt att lägga in en egen nyckel
   för root på Proxmox-noden.
3. Administratörsnyckeln som finns i mallen 9010, eller lösenordet till
   Administrator i mallen så att en egen nyckel kan läggas in i
   `C:\ProgramData\ssh\administrators_authorized_keys`.

### Hämta repot

Repot är privat, så du behöver läsbehörighet på GitHub. PowerShell:

```powershell
git clone https://github.com/Labontese/ISCX26-fordjupning.git
cd ISCX26-fordjupning
```

### Skapa testnycklarna

alice och bob loggar in med egna nycklar. Om du inte har fått de privata
nycklarna, skapa nya och byt ut de publika i repot. PowerShell:

```powershell
ssh-keygen -t ed25519 -f $HOME\.ssh\iscx26_alice -C "alice@iscx26-vg" -N '""'
ssh-keygen -t ed25519 -f $HOME\.ssh\iscx26_bob   -C "bob@iscx26-vg"   -N '""'
Copy-Item $HOME\.ssh\iscx26_alice.pub skript\linux\nycklar\alice.pub
Copy-Item $HOME\.ssh\iscx26_bob.pub   skript\linux\nycklar\bob.pub
```

Nycklarna har ingen lösenfras, eftersom de bara används för testerna.

## 1. Skapa maskinerna med Terraform

PowerShell:

```powershell
cd terraform
Copy-Item terraform.tfvars.exempel terraform.tfvars
notepad terraform.tfvars
```

Fyll i API-token, din publika SSH-nyckel (den blir inloggningen för daniel på
321) och sökvägen till maskinnyckeln mot Proxmox. Kör sedan:

```powershell
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

Planen ska visa `4 to add, 0 to change, 0 to destroy`: två cloud-init-filer
och två maskiner. apply tar några minuter, eftersom Windows-disken på 80 GB
klonas i sin helhet.

Kontrollera att allt stämmer:

```powershell
terraform plan
```

Rätt resultat är `No changes. Your infrastructure matches the configuration.`

Ta reda på adresserna. De syns som taggar på maskinerna i Proxmox. Normalt
är de 10.10.70.120 (321) och 10.10.70.118 (322). Använd de adresser du ser
om de skiljer sig, i alla steg nedan.

## 2. Linuxservern

Vänta tills cloud-init är klart, ungefär en minut efter apply. PowerShell:

```powershell
ssh daniel@10.10.70.120 "cloud-init status --wait"
```

Rätt resultat är `status: done`.

Kör konfigurationsskriptet. Det skapar grupper, användare, nycklar och
mappar. PowerShell, i repots rot:

```powershell
scp -r skript\linux daniel@10.10.70.120:/tmp/
ssh daniel@10.10.70.120 "sudo bash /tmp/linux/01-konfigurera.sh; rm -r /tmp/linux"
```

Utskriften ska sluta med ACL:en på Gemensamt och innehålla raden
`group:g_ledare:rwx`.

## 3. Windowsservern

Windows går igenom sysprep vid första starten. Vänta tills SSH svarar,
ungefär två minuter efter apply. PowerShell:

```powershell
ssh Administrator@10.10.70.118 hostname
```

Svaret är ett slumpat namn som `WIN-202S2SS3GD2`. Byt namn, eftersom
cloudbase-init inte sätter namnet från Proxmox:

```powershell
ssh Administrator@10.10.70.118 "Rename-Computer -NewName iscx26-vg-win -Restart -Force"
```

Vänta en halv minut och kontrollera:

```powershell
ssh Administrator@10.10.70.118 hostname
```

Rätt resultat är `iscx26-vg-win`.

Kör konfigurationsskriptet. Skriptet behöver hela mappen `skript`, eftersom
det hämtar nycklarna från `skript/linux/nycklar`. PowerShell, i repots rot:

```powershell
scp -r skript Administrator@10.10.70.118:C:/Windows/Temp/
ssh Administrator@10.10.70.118 "powershell -ExecutionPolicy Bypass -File C:\Windows\Temp\skript\windows\01-konfigurera.ps1"
ssh Administrator@10.10.70.118 "Remove-Item -Recurse C:\Windows\Temp\skript"
```

Utskriften ska visa alice i g_ledare, bob i g_personal och båda i OpenSSH
Users, och sedan rättigheterna på de tre mapparna.

## 4. Kontrollera att allt fungerar

Testskripten loggar in som alice och bob och provar varje krav. De skriver
PASS eller FAIL per test.

Linux, i **Git Bash** (inte PowerShell), i repots rot:

```bash
bash skript/linux/02-testa.sh 10.10.70.120
```

Windows, i **PowerShell**, i repots rot:

```powershell
powershell -ExecutionPolicy Bypass -File skript\windows\02-testa.ps1 -Vard 10.10.70.118
```

Båda ska sluta med `Alla test PASS`. Om något visar FAIL, se felsökningen.

Miljön är nu återställd.

## Drift

### Kontrollera miljön

Kör testskripten i steg 4. De ändrar inget utom testfilerna i Gemensamt och
Ledning, och kan köras hur ofta som helst.

### Lägga till en ny medarbetare

Rättigheterna ges till grupperna, inte till personer. En ny chef läggs i
g_ledare och en ny medarbetare i g_personal. Exempel med en ny chef, carol.

Linux, som daniel på 321:

```bash
sudo useradd -m -s /bin/bash carol
sudo usermod -aG g_ledare carol
```

carol loggar in med nyckel, som alice och bob. Lägg hennes publika nyckel i
`/home/carol/.ssh/authorized_keys` med samma rättigheter som i
`01-konfigurera.sh`: 700 på mappen, 600 på filen och carol som ägare.

Windows, som Administrator på 322:

```powershell
$pw = Read-Host -AsSecureString "Lösenord för carol"
New-LocalUser carol -Password $pw
Add-LocalGroupMember -SID S-1-5-32-545 -Member carol
Add-LocalGroupMember g_ledare -Member carol
```

Om carol ska kunna logga in med SSH på Windows måste hon också läggas i
OpenSSH Users. En ändring av gruppmedlemskap gäller från nästa inloggning.

### Bygga om en maskin

Om en maskin är trasig kan den byggas om från grunden. Exempel för 321,
PowerShell i `terraform`:

```powershell
terraform apply -replace="proxmox_virtual_environment_vm.linux"
```

För 322 är resursnamnet `proxmox_virtual_environment_vm.windows`. Gör sedan
steg 2 eller 3 och steg 4 igen. Maskinen får en ny värdnyckel för SSH, se
felsökningen.

### Riva miljön

PowerShell i `terraform`:

```powershell
terraform destroy
```

Det tar bort båda maskinerna och cloud-init-filerna. Mallarna på Proxmox
rörs inte.

## Felsökning

| Det här syns | Orsak | Gör så här |
|---|---|---|
| Alla Linuxtester FAIL, med `Identity file /home/... not accessible` | `bash` skrevs i PowerShell, och då startar Windows WSL i stället för Git Bash | Kör testet i Git Bash |
| `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!` | Maskinen är ombyggd och har en ny värdnyckel | `ssh-keygen -R 10.10.70.120` (eller .118), anslut igen och godkänn den nya nyckeln |
| `Connection reset` direkt efter apply mot 322 | Windows kör fortfarande sysprep vid första starten | Vänta en till två minuter |
| Datornamnet på 322 är `WIN-...` | cloudbase-init hittar inte namnet i Proxmox config drive | Byt namn enligt steg 3 |
| alice eller bob får `Permission denied (publickey)` mot 322 | De är inte med i OpenSSH Users. Loggen visar `not allowed because none of user's groups are listed in AllowGroups` | Kör `01-konfigurera.ps1` igen. Loggen läses med `Get-WinEvent -LogName OpenSSH/Operational -MaxEvents 10` |
| `Software caused connection abort` mot 321 efter misslyckade inloggningar | sshd stänger ute en adress en stund efter misslyckade inloggningar | Vänta en minut och försök igen. `journalctl -u ssh` på 321 visar `penalty: failed authentication` |
| `terraform plan` vill ändra `tags` | iptag.service på Proxmox sätter IP-adressen som tagg | Ska inte hända, taggarna ignoreras i `main.tf`. Om det ändå syns, kontrollera `lifecycle` i `main.tf` |
| å, ä och ö blir fel i Windows-skripten | Skriptet sparades utan BOM, och Windows PowerShell 5.1 läser det då som ANSI | Spara `.ps1`-filerna som UTF-8 med BOM |
