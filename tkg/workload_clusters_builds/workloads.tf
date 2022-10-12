
resource "null_resource" "builds" {
  count = length(var.tkg.clusters.workloads)
  connection {
    host        = var.vcenter.dvs.portgroup.management.external_gw_ip
    type        = "ssh"
    agent       = false
    user        = var.external_gw.username
    private_key = file(var.external_gw.private_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "/bin/bash govc_workload${count.index + 1 }.sh"
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "tanzu cluster create ${var.tkg.clusters.workloads[count.index].name} -f workload${count.index + 1 }.yml -v 6"
    ]
  }
}