#resource "null_resource" "ansible_hosts_avi_header_1" {
#  provisioner "local-exec" {
#    command = "echo '---' | tee hosts_avi; echo 'all:' | tee -a hosts_avi ; echo '  children:' | tee -a hosts_avi; echo '    controller:' | tee -a hosts_avi; echo '      hosts:' | tee -a hosts_avi"
#  }
#}
#
#resource "null_resource" "ansible_hosts_avi_controllers" {
#  depends_on = [null_resource.ansible_hosts_avi_header_1]
#  provisioner "local-exec" {
#    command = "echo '        ${cidrhost(var.nsx.config.segments_overlay[0].cidr, var.nsx.config.segments_overlay[0].avi_controller)}:' | tee -a hosts_avi "
#  }
#}

resource "null_resource" "copy_avi_cert_locally" {
  provisioner "local-exec" {
    command = "scp -i ${var.external_gw.private_key_path} -o StrictHostKeyChecking=no ${var.external_gw.username}@${var.vcenter.dvs.portgroup.management.external_gw_ip}:/home/${var.external_gw.username}/ssl_avi/avi.cert ${path.root}/avi.cert"
  }
}

resource "null_resource" "copy_avi_key_locally" {
  provisioner "local-exec" {
    command = "scp -i ${var.external_gw.private_key_path} -o StrictHostKeyChecking=no ${var.external_gw.username}@${var.vcenter.dvs.portgroup.management.external_gw_ip}:/home/${var.external_gw.username}/ssl_avi/avi.key ${path.root}/avi.key"
  }
}

data "template_file" "values" {
  template = file("templates/values.yml.template")
  vars = {
    avi_version = var.avi.controller.version
    controllerPrivateIp = cidrhost(var.nsx.config.segments_overlay[0].cidr, var.nsx.config.segments_overlay[0].avi_controller)
    avi_old_password =  jsonencode(var.avi_old_password)
    avi_password = jsonencode(var.avi_password)
    avi_username = jsonencode(var.avi_username)
    ntp = var.ntp.server
    dns = var.dns.nameserver
    nsx_password = var.nsx_password
    nsx_server = var.vcenter.dvs.portgroup.management.nsx_ip
    domain = var.dns.domain
    cloud_name = var.avi.config.cloud.name
    cloud_obj_name_prefix = var.avi.config.cloud.obj_name_prefix
    transport_zone_name = var.avi.config.transport_zone_name
    network_management = jsonencode(var.avi.config.network_management)
    networks_data = jsonencode(var.avi.config.networks_data)
    sso_domain = var.vcenter.sso.domain_name
    vcenter_password = var.vcenter_password
    vcenter_ip = var.vcenter.dvs.portgroup.management.vcenter_ip
    content_library = var.avi.config.content_library_avi
    service_engine_groups = jsonencode(var.avi.config.service_engine_groups)
    pools = jsonencode(var.avi.config.pools)
    virtual_services = jsonencode(var.avi.config.virtual_services)
  }
}

data "template_file" "avi_values" {
  template = file("templates/avi_vcenter_yaml_values.yml.template")
  vars = {
    controllerPrivateIp = cidrhost(var.nsx.config.segments_overlay[0].cidr, var.nsx.config.segments_overlay[0].avi_controller)
    ntp = var.dns.nameserver
    dns = var.dns.nameserver
    avi_old_password =  jsonencode(var.avi_old_password)
    avi_password = jsonencode(var.avi_password)
    avi_username = jsonencode(var.avi_username)
    avi_version = var.avi.controller.version
    vsphere_username = "administrator@${var.vcenter.sso.domain_name}"
    vsphere_password = var.vcenter_password
    vsphere_server = "${var.vcenter.name}.${var.dns.domain}"
    sslkeyandcertificate = var.avi.config.sslkeyandcertificate
    portal_configuration = var.avi.config.portal_configuration
    tenants = var.avi.config.tenants
    domain = var.dns.domain
    ipam = var.avi.config.ipam
    cloud_name = var.avi.config.cloud.name
    networks = var.avi.config.cloud.networks
    service_engine_groups = jsonencode(var.avi.config.service_engine_groups)
    virtual_services = jsonencode(var.avi.config.virtual_services)
  }
}


resource "null_resource" "ansible_avi" {
  depends_on = [null_resource.copy_avi_cert_locally, null_resource.copy_avi_key_locally]

  connection {
    host = var.vcenter.dvs.portgroup.management.external_gw_ip
    type = "ssh"
    agent = false
    user        = var.external_gw.username
    private_key = file(var.external_gw.private_key_path)
  }

  provisioner "file" {
    source = "hosts_avi"
    destination = "hosts_avi"
  }

  provisioner "file" {
    content = data.template_file.values.rendered
    destination = "values.yml"
  }

  provisioner "remote-exec" {
    inline = [
      "git clone ${var.avi.config.avi_config_repo} --branch ${var.avi.config.avi_config_tag}",
      "cd ${split("/", var.avi.config.avi_config_repo)[4]}",
      "ansible-playbook -i ../hosts_avi vcenter.yml --extra-vars @../values.yml"
    ]
  }
}