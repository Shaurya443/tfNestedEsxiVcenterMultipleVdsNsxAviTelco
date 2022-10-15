
resource "null_resource" "transfer_files" {

  connection {
    host        = var.vcenter.dvs.portgroup.management.external_gw_ip
    type        = "ssh"
    agent       = false
    user        = var.external_gw.username
    private_key = file(var.external_gw.private_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "/bin/bash govc_mgmt.sh"
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "tanzu management-cluster create ${var.tkg.clusters.management.name} -f tkg-cluster-mgmt.yml -v 6"
    ]
  }

}