resource "vsphere_content_library" "cl_tf_dnsntp" {
  count = (var.dns_ntp.create == true ? 1 : 0)
  name            = "cl_tf_dnsntp"
  storage_backing = [data.vsphere_datastore.datastore.id]
}

resource "vsphere_content_library_item" "file_dnsntp" {
  count = (var.dns_ntp.create == true ? 1 : 0)
  name        = basename(var.vcenter_underlay.cl.ubuntu_focal_file_path)
  library_id  = vsphere_content_library.cl_tf_dnsntp[0].id
  file_url = var.vcenter_underlay.cl.ubuntu_focal_file_path
}

data "template_file" "dns_ntp_userdata" {
  count = (var.dns_ntp.create == true ? 1 : 0)
  template = file("${path.module}/userdata/dns_ntp.userdata")
  vars = {
    pubkey        = file(var.dns_ntp.public_key_path)
    username = var.dns_ntp.username
    ipCidr  = "${var.vcenter.dvs.portgroup.management.dns_ntp_ip}/${var.vcenter.dvs.portgroup.management.prefix}"
    ip = var.vcenter.dvs.portgroup.management.dns_ntp_ip
    lastOctet = split(".", var.vcenter.dvs.portgroup.management.dns_ntp_ip)[3]
    defaultGw = var.vcenter.dvs.portgroup.management.gateway
    dns      = join(", ", var.dns_ntp.dns)
    netplanFile = var.dns_ntp.netplanFile
    privateKey = var.dns_ntp.private_key_path
    password      = var.ubuntu_password
    hostname = var.dns_ntp.name
    forwarders = join("; ", var.dns_ntp.bind.forwarders)
    domain = var.dns.domain
    reverse = var.dns_ntp.bind.reverse
    keyName = var.dns_ntp.bind.keyName
    secret = base64encode(var.bind_password)
    ntp = var.dns_ntp.ntp
  }
}

resource "vsphere_virtual_machine" "dns_ntp" {
  count = (var.dns_ntp.create == true ? 1 : 0)
  name             = var.dns_ntp.name
  datastore_id     = data.vsphere_datastore.datastore.id
  resource_pool_id = data.vsphere_resource_pool.pool.id
  folder           = "/${var.vcenter_underlay.dc}/vm/${var.vcenter_underlay.folder}"
  network_interface {
    network_id = data.vsphere_network.vcenter_underlay_network_mgmt[0].id
  }

  num_cpus = var.dns_ntp.cpu
  memory = var.dns_ntp.memory
  guest_id = "ubuntu64Guest"

  disk {
    size             = var.dns_ntp.disk
    label            = "${var.dns_ntp.name}.lab_vmdk"
    thin_provisioned = true
  }

  cdrom {
    client_device = true
  }

  clone {
    template_uuid = vsphere_content_library_item.file_dnsntp[0].id
  }

  vapp {
    properties = {
      hostname    = var.dns_ntp.name
      public-keys = file(var.dns_ntp.public_key_path)
      user-data   = base64encode(data.template_file.dns_ntp_userdata[0].rendered)
    }
  }

  connection {
    host        = var.vcenter.dvs.portgroup.management.dns_ntp_ip
    type        = "ssh"
    agent       = false
    user        = var.dns_ntp.username
    private_key = file(var.dns_ntp.private_key_path)
  }

  provisioner "remote-exec" {
    inline      = [
      "while [ ! -f /tmp/cloudInitDone.log ]; do sleep 1; done"
    ]
  }
}

resource "null_resource" "clear_ssh_key_dnsntp_locally" {
  provisioner "local-exec" {
    command = "ssh-keygen -f \"/home/ubuntu/.ssh/known_hosts\" -R \"${var.vcenter.dvs.portgroup.management.dns_ntp_ip}\" || true"
  }
}