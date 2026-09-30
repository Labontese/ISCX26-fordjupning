# ============================================================================
# Två virtuella maskiner för VG-uppgiften, båda på driftnätet (VLAN 70).
#
#   321  iscx26-vg-linux   Ubuntu Server 26.04   DHCP
#   322  iscx26-vg-win     Windows Server 2025   DHCP
#
# Båda klonas från färdiga mallar: 9001 (Ubuntu) och 9010 (Windows).
# ============================================================================

# ------------------------------------------------------------ cloud-init ----
# Proxmox egen nätverkskonfiguration döper kortet till eth0, men Ubuntu 26.04
# kallar det ens18. Därför skickas en egen konfiguration med.
#
# ignore_changes på source_raw: cloud-init läser filerna en enda gång, vid
# första uppstart. Utan raden räknar Terraform även en ändrad kommentar som
# skäl att ersätta filen, och därmed hela maskinen.
resource "proxmox_virtual_environment_file" "networkdata" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data      = file("${path.module}/cloud-init/linux-networkdata.yaml")
    file_name = "iscx26vg-linux-networkdata.yaml"
  }

  lifecycle {
    ignore_changes = [source_raw]
  }
}

resource "proxmox_virtual_environment_file" "userdata" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    data = templatefile("${path.module}/cloud-init/linux-userdata.yaml.tftpl", {
      ssh_public_key = var.ssh_public_key
    })
    file_name = "iscx26vg-linux-userdata.yaml"
  }

  lifecycle {
    ignore_changes = [source_raw]
  }
}

# ------------------------------------------------------------ Linuxservern --
resource "proxmox_virtual_environment_vm" "linux" {
  name        = "iscx26-vg-linux"
  description = "ISCX26 VG-uppgiften. Skapad med Terraform."
  node_name   = "pve"
  vm_id       = 321
  tags        = ["iscx26", "vg"]

  clone {
    vm_id = 9001 # mallen ubuntu-2604-cloudinit
    full  = true
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "zfs-pve"
    interface    = "scsi0"
    size         = 20
    discard      = "on"
  }

  # Driftnätet. Blir ens18 i gästen.
  network_device {
    bridge      = var.brygga_drift
    vlan_id     = var.vlan_drift
    mac_address = "BC:24:11:00:D3:21"
  }

  initialization {
    ip_config {
      ipv4 { address = "dhcp" }
    }
    user_data_file_id    = proxmox_virtual_environment_file.userdata.id
    network_data_file_id = proxmox_virtual_environment_file.networkdata.id
  }

  agent {
    enabled = true
    timeout = "3m"
  }

  # Tjänsten iptag.service på Proxmox lägger till maskinens IP-adress som
  # tagg. Utan raden vill Terraform ta bort taggen vid varje plan.
  lifecycle {
    ignore_changes = [tags]
  }
}

# ----------------------------------------------------------- Windowsservern --
# Klonas från mallen 9010: Windows Server 2025, sysprep:ad, med cloudbase-init,
# OpenSSH (bara nyckel), virtio-drivrutiner och gästagenten redan installerade.
#
# Datornamnet sätts inte automatiskt. Proxmox lägger namnet i config drivens
# user_data, men cloudbase-init letar bara i meta_data.json och hittar det
# inte (loggen: "Hostname not found in metadata"). Namnet byts därför efter
# första start med Rename-Computer, se återställningsinstruktionen.
resource "proxmox_virtual_environment_vm" "windows" {
  name        = "iscx26-vg-win"
  description = "ISCX26 VG-uppgiften. Klonad med Terraform från mallen 9010."
  node_name   = "pve"
  vm_id       = 322
  tags        = ["iscx26", "vg"]

  clone {
    vm_id        = 9010 # winserver2025-tpl
    full         = true
    datastore_id = "zfs-pve"
  }

  bios    = "ovmf"
  machine = "q35"

  operating_system {
    type = "win11"
  }

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 8192
  }

  # Proxmox skapar en config drive som cloudbase-init läser.
  initialization {
    datastore_id = "zfs-pve"
    interface    = "ide2"
    ip_config {
      ipv4 { address = "dhcp" }
    }
  }

  network_device {
    bridge      = var.brygga_drift
    vlan_id     = var.vlan_drift
    model       = "e1000e"
    mac_address = "BC:24:11:00:D3:22"
  }

  agent {
    enabled = true
    timeout = "3m"
  }

  # machine står med för att Proxmox löser upp "q35" till en exakt version,
  # till exempel pc-q35-11.0+pve2. Terraform ser det som en skillnad, och ett
  # byte av maskintyp kräver att maskinen stängs av.
  # tags står med av samma skäl som på Linuxservern: iptag.service.
  lifecycle {
    ignore_changes = [machine, tags]
  }
}

# ------------------------------------------------------------------ utdata --
output "maskiner" {
  value = {
    linux   = { vmid = 321, namn = "iscx26-vg-linux", mac = "BC:24:11:00:D3:21" }
    windows = { vmid = 322, namn = "iscx26-vg-win", mac = "BC:24:11:00:D3:22" }
  }
}
