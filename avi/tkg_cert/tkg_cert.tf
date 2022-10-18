
#data "template_file" "v3-ext" {
#  template = file("templates/v3.ext.template")
#  vars = {
#    avi_controller_ip = cidrhost(var.nsx.config.segments_overlay[0].cidr, var.nsx.config.segments_overlay[0].avi_controller)
#  }
#}

resource "null_resource" "generate_avi_cert" {
  connection {
    host        = var.vcenter.dvs.portgroup.management.external_gw_ip
    type        = "ssh"
    agent       = false
    user        = var.external_gw.username
    private_key = file(var.external_gw.private_key_path)
  }

#  provisioner "file" {
#    content = data.template_file.v3-ext.rendered
#    destination = "v3.ext"
#  }

#  provisioner "remote-exec" {
#    inline = [
#      "mkdir ssl_avi",
#      "mv v3.ext ssl_avi/",
#      "cd ssl_avi",
#      "openssl genrsa -out ca.key 2048",
#      "openssl req -x509 -new -nodes -sha512 -days 365 -subj \"/C=US/ST=CA/L=Palo Alto/O=VMWARE/OU=IT/CN=controller-avi.${var.dns.domain}\" -key ca.key -out ca.crt",
#      "openssl genrsa -out ${var.avi.controller.ssl_key_name} 2048",
#      "openssl req -sha512 -new -subj \"/C=US/ST=CA/L=Palo Alto/O=VMWARE/OU=IT/CN=controller-avi.${var.dns.domain}\" -key avi.key -out avi.csr",
#      "openssl x509 -req -sha512 -days 365 -extfile v3.ext -CA ca.crt -CAkey ca.key -CAcreateserial -in avi.csr -out ${var.avi.controller.ssl_cert_name}"
#    ]
#  }

  provisioner "file" {
    content = 'ssl_avi'
    destination = 'ssl_avi'
  }

}