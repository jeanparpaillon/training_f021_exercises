terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.7.6"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

resource "libvirt_pool" "default" {
  name = "default"
  type = "dir"
  path = "/var/lib/libvirt/images"
}

# Volume de base (image cloud-init Ubuntu)
resource "libvirt_volume" "ubuntu_base" {
  name   = "ubuntu_base"
  pool   = "default"
  source = "noble-server-cloudimg-amd64.img"
  format = "qcow2"
}
resource "libvirt_volume" "vm_disk" {
  count          = var.node_count
  name           = "node${count.index + 1}.qcow2"
  base_volume_id = libvirt_volume.ubuntu_base.id
}

resource "libvirt_domain" "node" {
  count  = var.node_count
  name   = "node${count.index + 1}"
  memory = 2048
  vcpu   = 1
  # In case KVM is not available
  # type   = "qemu"

  network_interface {
    network_name = "default"
  }

  disk {
    volume_id = libvirt_volume.vm_disk[count.index].id
  }

  console {
    type        = "pty"
    target_port = "0"
  }
}
