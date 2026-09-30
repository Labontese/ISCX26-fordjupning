# Miljön: referens

Den här sidan beskriver vad som finns i VG-miljön och vad den är beroende av.
Hur miljön byggs upp står i
[Återställ och driv miljön](../instruktion/aterstall-miljon.md).

## Maskiner

Båda maskinerna skapas av Terraform i [`terraform/main.tf`](../../terraform/main.tf).

| | Linuxservern | Windowsservern |
|---|---|---|
| VM-id | 321 | 322 |
| Namn | iscx26-vg-linux | iscx26-vg-win |
| Operativsystem | Ubuntu Server 26.04 | Windows Server 2025 Standard Evaluation |
| Mall på Proxmox | 9001 ubuntu-2604-cloudinit | 9010 winserver2025-tpl |
| CPU, minne, disk | 2 kärnor, 2 GB, 20 GB | 4 kärnor, 8 GB, 80 GB |
| MAC-adress | BC:24:11:00:D3:21 | BC:24:11:00:D3:22 |
| IP-adress | 10.10.70.120 (DHCP) | 10.10.70.118 (DHCP) |
| Nätkort | virtio, heter ens18 i gästen | e1000e |
| Första start | cloud-init | cloudbase-init |

IP-adresserna kommer från DHCP. MAC-adressen är fast i Terraform, och
Linuxservern identifierar sig för DHCP med MAC-adressen
(`dhcp-identifier: mac` i
[`linux-networkdata.yaml`](../../terraform/cloud-init/linux-networkdata.yaml)).
Därför får den samma adress när den byggs om. Utan den raden skickar Ubuntu
ett id som räknas fram ur machine-id, och det blir nytt vid varje ombyggnad.
Aktuell adress syns som tagg på maskinen i Proxmox, eller med
`qm guest cmd <vmid> network-get-interfaces` på Proxmox-värden.

DHCP är ett val för labben, eftersom det är enklast. I en riktig
infrastruktur har servrar fasta adresser, antingen inställda på servern
eller som en DHCP-reservation som knyter MAC-adressen till en viss adress
(static mapping i pfSense). DHCP med vanliga lån är till för klienter.

## Nät

| | Värde |
|---|---|
| Nät | driftnätet, VLAN 70, 10.10.70.0/24 |
| Brygga på Proxmox | vmbr1 |
| Gateway | pfSense, 10.10.70.1 |
| DNS | Technitium, 10.10.0.4 (i 10.10.0.0/24, nås via gatewayen) |
| DHCP | pfSense, ger adress, gateway och DNS |

## Beroenden

Det här lämnas inte över, men måste finnas för att miljön ska gå att bygga.

| Beroende | Vad som krävs |
|---|---|
| Proxmox VE, noden `pve` på 10.10.0.3 | API på port 8006, SSH som root för att ladda upp cloud-init-filer |
| API-token | `terraform@pve!provider`, med rätt att klona mallar och skapa maskiner |
| Lagring | `zfs-pve` för diskar, `local` för cloud-init-filer (snippets) |
| Mall 9001 | Ubuntu 26.04 med cloud-init |
| Mall 9010 | Windows Server 2025, sysprep:ad, med cloudbase-init, OpenSSH, virtio-drivrutiner och gästagenten |
| Licensen på Windowsservern | Mallen är en utvärderingsversion (Evaluation) som slutar fungera 180 dagar efter installationen. Då måste mallen 9010 byggas om, eller servern aktiveras med en riktig licens |
| pfSense | routing mellan VLAN 70 och övriga nät, DHCP på VLAN 70 och NAT ut mot internet |
| Technitium DNS | 10.10.0.4, slår upp namn på internet |
| iptag.service på Proxmox | sätter IP-adressen som tagg på maskinerna. Terraform ignorerar taggarna |

## Konton

| System | Konto | Används till | Inloggning |
|---|---|---|---|
| 321 | daniel | administration, har sudo utan lösenord | SSH-nyckel från `ssh_public_key` i Terraform |
| 322 | Administrator | administration | SSH-nyckel som finns i mallen 9010 |
| 321 och 322 | alice | testanvändare, medlem i g_ledare | egen SSH-nyckel |
| 321 och 322 | bob | testanvändare, medlem i g_personal | egen SSH-nyckel |

alice och bob har inget lösenord som någon känner till. På Windows är de också
medlemmar i Users och OpenSSH Users, eftersom mallens `sshd_config` bara
släpper in medlemmar i Administrators och OpenSSH Users.

## Nycklar och hemligheter

Inga hemligheter finns i repot. De ligger på administratörens dator.

| Vad | Var | I repot? |
|---|---|---|
| API-token och sökvägar | `terraform/terraform.tfvars` | Nej, gitignorerad. Mall: [`terraform.tfvars.exempel`](../../terraform/terraform.tfvars.exempel) |
| Maskinnyckel mot Proxmox | `~/.ssh/id_terraform_pve` | Nej |
| Testnycklar, privata | `~/.ssh/iscx26_alice` och `~/.ssh/iscx26_bob` | Nej |
| Testnycklar, publika | [`skript/linux/nycklar/`](../../skript/linux/nycklar/) | Ja, används av båda systemen |
| Terraform-tillstånd | `terraform/terraform.tfstate` | Nej, gitignorerat |

## Behörighetsstrukturen

| Mapp | Linux | Windows | g_personal | g_ledare |
|---|---|---|---|---|
| Projekt | `/srv/Projekt`, 755 root:root | `C:\Projekt`, arvet brutet, Users RX | se mapparna | se mapparna |
| Gemensamt | 2770 root:g_personal, ACL för g_ledare | Modify för båda grupperna | läsa och skriva | läsa och skriva |
| Ledning | 2770 root:g_ledare | Modify för g_ledare | ingen åtkomst | läsa och skriva |

Varför det ser ut så förklaras i
[Rättigheter i Linux och Windows](../forklaring/rattigheter-linux-windows.md).

## Repot

| Sökväg | Innehåll |
|---|---|
| [`terraform/`](../../terraform/) | Maskinerna som kod |
| [`skript/linux/01-konfigurera.sh`](../../skript/linux/01-konfigurera.sh) | Grupper, användare, nycklar och mappar på 321 |
| [`skript/linux/02-testa.sh`](../../skript/linux/02-testa.sh) | Testar rättigheterna på 321 som alice och bob |
| [`skript/windows/01-konfigurera.ps1`](../../skript/windows/01-konfigurera.ps1) | Samma sak på 322 |
| [`skript/windows/02-testa.ps1`](../../skript/windows/02-testa.ps1) | Testar rättigheterna på 322 som alice och bob |
| [`dokumentation/`](../) | Instruktion, referens och förklaringar |
