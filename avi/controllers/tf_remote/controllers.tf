resource "vsphere_folder" "avi" {
  count            = var.avi.controller.create == true ? 1 : 0
  path          = "avi-controllers"
  type          = "vm"
  datacenter_id = data.vsphere_datacenter.dc_nested[0].id
}

resource "vsphere_virtual_machine" "controller" {
  count = var.avi.controller.create == true ? 1 : 0
  name             = "${var.avi.controller.basename}-${count.index + 1}"
  datastore_id     = data.vsphere_datastore.datastore_nested[0].id
  resource_pool_id = data.vsphere_resource_pool.resource_pool_nested[0].id
  folder           = vsphere_folder.avi[0].path

  network_interface {
    network_id = data.vsphere_network.vcenter_network_mgmt_nested[0].id
  }

  num_cpus = var.avi.controller.cpu
  memory = var.avi.controller.memory
  wait_for_guest_net_timeout = 4
  guest_id = "guestid-controller-${count.index + 1}"

  disk {
    size             = var.avi.controller.disk
    label            = "controller--${count.index + 1}.lab_vmdk"
    thin_provisioned = true
  }

  clone {
    template_uuid = vsphere_content_library_item.nested_library_avi_item[0].id
  }

  vapp {
    properties = {
      "mgmt-ip"     = cidrhost(var.nsx.config.segments_overlay[0].cidr, var.nsx.config.segments_overlay[count.index].avi_controller)
      "mgmt-mask"   = cidrnetmask(var.nsx.config.segments_overlay[0].cidr)
      "default-gw"  = cidrhost(var.nsx.config.segments_overlay[0].cidr, var.nsx.config.segments_overlay[0].gw)
   }
 }
}

resource "null_resource" "wait_https_controller" {
  depends_on = [vsphere_virtual_machine.controller]
  count = var.avi.controller.create == true ? 1 : 0

  provisioner "local-exec" {
    command = "until $(curl --output /dev/null --silent --head -k https://${cidrhost(var.nsx.config.segments_overlay[0].cidr, var.nsx.config.segments_overlay[count.index].avi_controller)}); do echo 'Waiting for Avi Controllers to be ready'; sleep 60 ; done"
  }
}

data "template_file" "v3-ext" {
  template = file("templates/v3.ext.template")
  vars = {
    avi_controller_ip = cidrhost(var.nsx.config.segments_overlay[0].cidr, var.nsx.config.segments_overlay[count.index].avi_controller)
  }
}

resource "null_resource" "generate_avi_cert" {
  connection {
    host        = var.vcenter.dvs.portgroup.management.external_gw_ip
    type        = "ssh"
    agent       = false
    user        = var.external_gw.username
    private_key = file(var.external_gw.private_key_path)
  }

  provisioner "file" {
    content = data.template_file.v3-ext.rendered
    destination = "v3.ext"
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir ssl_avi",
      "cd ssl_avi",
      "openssl genrsa -out ca.key 4096",
      "openssl req -x509 -new -nodes -sha512 -days 3650 -subj \"/C=US/ST=CA/L=Palo Alto/O=VMWARE/OU=IT/CN=controller-avi.${var.dns.domain}\" -key ca.key -out ca.crt",
      "openssl genrsa -out avi.key 4096",
      "openssl req -sha512 -new -subj \"/C=US/ST=CA/L=Palo Alto/O=VMWARE/OU=IT/CN=controller-avi.${var.dns.domain}\" -key avi.key -out avi.csr",
      "openssl x509 -req -sha512 -days 3650 -extfile v3.ext -CA ca.crt -CAkey ca.key -CAcreateserial -in avi.csr -out avi.crt"
    ]
  }
}