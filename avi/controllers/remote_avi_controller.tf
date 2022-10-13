data "template_file" "environment_variables" {
  template = file("templates/environment_variables.json.template")
  vars = {
    vcenter_password = var.vcenter_password
    avi_password = var.avi_password
  }
}

resource "null_resource" "tf_avi_controller" {

  connection {
    host = var.vcenter.dvs.portgroup.management.external_gw_ip
    type = "ssh"
    agent = false
    user = var.external_gw.username
    private_key = file(var.external_gw.private_key_path)
  }

  provisioner "file" {
    source = var.avi.content_library.ova_location
    destination = basename(var.avi.content_library.ova_location)
  }

  provisioner "file" {
    source = "../../variables.json"
    destination = "variables.json"
  }

  provisioner "file" {
    source = "tf_remote"
    destination = "tf_remote_avi_controller"
  }

  provisioner "file" {
    content = data.template_file.environment_variables.rendered
    destination = ".environment_variables.json"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -",
      "sudo apt-add-repository \"deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main\"",
      "sudo apt-get update && sudo apt-get install terraform",
      "cd tf_remote_avi_controller",
      "terraform init",
      "terraform apply -auto-approve -var-file=../variables.json -var-file=../.environment_variables.json",
      "rm -f ../.environment_variables.json",
      "rm -f ../variables.json"
    ]
  }
}

data "template_file" "v3-ext" {
  template = file("templates/v3.ext.template")
  vars = {
    avi_controller_ip = cidrhost(var.nsx.config.segments_overlay[0].cidr, var.nsx.config.segments_overlay[0].avi_controller)
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
      "mv v3.ext ssl_avi/",
      "cd ssl_avi",
      "openssl genrsa -out ca.key 4096",
      "openssl req -x509 -new -nodes -sha512 -days 3650 -subj \"/C=US/ST=CA/L=Palo Alto/O=VMWARE/OU=IT/CN=controller-avi.${var.dns.domain}\" -key ca.key -out ca.crt",
      "openssl genrsa -out ${var.avi.controller.ssl_key_name} 4096",
      "openssl req -sha512 -new -subj \"/C=US/ST=CA/L=Palo Alto/O=VMWARE/OU=IT/CN=controller-avi.${var.dns.domain}\" -key avi.key -out avi.csr",
      "openssl x509 -req -sha512 -days 3650 -extfile v3.ext -CA ca.crt -CAkey ca.key -CAcreateserial -in avi.csr -out ${var.avi.controller.ssl_cert_name}"
    ]
  }
}