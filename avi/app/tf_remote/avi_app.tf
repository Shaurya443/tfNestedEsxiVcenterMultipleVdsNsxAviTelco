data "template_file" "avi_app_userdata" {
  count = length(var.nsx.config.segments_overlay[1].avi_app_server_ips)
  template = file("${path.module}/userdata/avi_app.userdata")
  vars = {
    username     = var.avi.app.username
    hostname     = "${var.avi.app.basename}${count.index}"
    password      = var.ubuntu_password
    pubkey       = file("../${basename(var.avi.app.public_key_path)}")
    netplan_file  = var.avi.app.netplan_file
    prefix = split("/", var.nsx.config.segments_overlay[1].cidr)[1]
    ip = var.nsx.config.segments_overlay[1].avi_app_server_ips[count.index]
    mtu = var.avi.app.mtu
    default_gw = cidrhost(var.nsx.config.segments_overlay[1].cidr, var.nsx.config.segments_overlay[1].gw)
    dns = var.dns.nameserver
    docker_registry_username = var.docker_registry_username
    docker_registry_password = var.docker_registry_password
    avi_app_docker_image = var.avi.app.avi_app_docker_image
    avi_app_tcp_port = var.avi.app.avi_app_tcp_port
    hackazon_docker_image = var.avi.app.hackazon_docker_image
    hackazon_tcp_port = var.avi.app.hackazon_tcp_port
  }
}

resource "vsphere_virtual_machine" "avi_app" {
  count = length(var.nsx.config.segments_overlay[1].avi_app_server_ips)
  name             = "${var.avi.app.basename}${count.index}"
  datastore_id     = data.vsphere_datastore.datastore_nested.id
  resource_pool_id = data.vsphere_resource_pool.resource_pool_nested.id

  network_interface {
    network_id = data.vsphere_network.vcenter_network.id
  }

  num_cpus = var.avi.app.cpu
  memory = var.avi.app.memory
  guest_id = "avi_app-${count.index}"
  wait_for_guest_net_timeout = 10

  disk {
    size             = var.avi.app.disk
    label            = "${var.avi.app.basename}${count.index}.lab_vmdk"
    thin_provisioned = true
  }

  cdrom {
    client_device = true
  }

  clone {
    template_uuid = vsphere_content_library_item.nested_library_item_avi_app.id
  }

  vapp {
    properties = {
      hostname    = "${var.avi.app.basename}${count.index}"
      public-keys = file("../${basename(var.avi.app.public_key_path)}")
      user-data   = base64encode(data.template_file.avi_app_userdata[count.index].rendered)
    }
  }

  connection {
    host        = var.nsx.config.segments_overlay[1].avi_app_server_ips[count.index]
    type        = "ssh"
    agent       = false
    user        = var.avi.app.username
    private_key = file("../${basename(var.avi.app.private_key_path)}")
  }

  provisioner "remote-exec" {
    inline      = [
      "while [ ! -f /tmp/cloudInitDone.log ]; do sleep 1; done"
    ]
  }
}