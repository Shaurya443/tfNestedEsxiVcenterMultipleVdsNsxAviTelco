resource "null_resource" "generate_avi_cert" {
  connection {
    host        = var.vcenter.dvs.portgroup.management.external_gw_ip
    type        = "ssh"
    agent       = false
    user        = var.external_gw.username
    private_key = file(var.external_gw.private_key_path)
  }

    provisioner "remote-exec" {
      inline = [
        "helm repo add ako ${var.avi.config.ako.helm_url}",
      ]
    }
}