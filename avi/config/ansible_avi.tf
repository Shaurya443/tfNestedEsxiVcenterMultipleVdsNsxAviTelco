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

data "template_file" "avi_values" {
  template = file("templates/avi_vcenter_yaml_values.yml.template")
  vars = {
    controllerPrivateIp = jsonencode(cidrhost(var.nsx.config.segments_overlay[0].cidr, var.nsx.config.segments_overlay[0].avi_controller))
    ntp = jsonencode(var.dns.nameserver)
    dns = jsonencode(var.dns.nameserver)
    avi_old_password =  jsonencode(var.avi_old_password)
    avi_password = jsonencode(var.avi_password)
    avi_username = jsonencode(var.avi_username)
    avi_version = var.avi.controller.version
    vsphere_username = "administrator@${var.vcenter.sso.domain_name}"
    vsphere_password = var.vcenter_password
    vsphere_server = "${var.vcenter.name}.${var.dns.domain}"
    sslkeyandcertificate = jsonencode(var.avi.config.sslkeyandcertificate)
    portal_configuration = jsonencode(var.avi.config.portal_configuration)
    tenants = jsonencode(var.avi.config.tenants)
    users = jsonencode(var.avi.config.users)
    domain = jsonencode(var.dns.domain)
    dc = var.vcenter.datacenter
    ipam = jsonencode(var.avi.config.ipam)
    cloud_name = var.avi.config.cloud.name
    networks = jsonencode(var.avi.config.cloud.networks)
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
    content = data.template_file.avi_values.rendered
    destination = "avi_values.yml"
  }

  provisioner "remote-exec" {
    inline = [
      "git clone ${var.avi.config.avi_config_repo} --branch ${var.avi.config.avi_config_tag}",
      "cd ${split("/", var.avi.config.avi_config_repo)[4]}",
      "ansible-playbook vcenter.yml --extra-vars @../avi_values.yml"
    ]
  }
}