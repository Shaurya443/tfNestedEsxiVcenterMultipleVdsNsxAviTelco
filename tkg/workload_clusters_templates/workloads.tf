resource "null_resource" "retrieve_vcenter_finger_print" {
  provisioner "local-exec" {
    command = "rm -f vcenter_finger_print.txt ; echo | openssl s_client -connect ${var.vcenter.name}.${var.dns.domain}:443 |& openssl x509 -fingerprint -noout |  cut -d\"=\" -f2 | tee vcenter_finger_print.txt"
  }
}


data "template_file" "workload" {
  depends_on = [null_resource.retrieve_vcenter_finger_print]
  count = length(var.tkg.clusters.workloads)
  template = file("templates/workload_clusters.yml.template")
  vars = {
    name = var.tkg.clusters.workloads[count.index].name
    antrea_node_port_local = var.tkg.clusters.workloads[count.index].antrea_node_port_local
    cluster_cidr = var.tkg.clusters.workloads[count.index].cluster_cidr
    avi_control_plane_ha_provider = var.tkg.clusters.workloads[count.index].avi_control_plane_ha_provider
    service_cidr = var.tkg.clusters.workloads[count.index].service_cidr
    datacenter = var.vcenter.datacenter
    vcenter_folder = var.tkg.clusters.workloads[count.index].vcenter_folder
    cluster = var.vcenter.cluster
    vcenter_resource_pool = var.tkg.clusters.workloads[count.index].vcenter_resource_pool
    vcenter_password_base64 = base64encode(var.vcenter_password)
    vsphere_network = var.tkg.clusters.workloads[count.index].vsphere_network
    vsphere_server = "${var.vcenter.name}.${var.dns.domain}"
    vsphere_username = "administrator@${var.vcenter.sso.domain_name}"
    worker_disk = var.tkg.clusters.workloads[count.index].worker_disk
    worker_memory = var.tkg.clusters.workloads[count.index].worker_memory
    worker_cpu = var.tkg.clusters.workloads[count.index].worker_cpu
    worker_count = var.tkg.clusters.workloads[count.index].worker_count
    control_plane_disk = var.tkg.clusters.workloads[count.index].control_plane_disk
    control_plane_memory = var.tkg.clusters.workloads[count.index].control_plane_memory
    control_plane_cpu = var.tkg.clusters.workloads[count.index].control_plane_cpu
    control_plane_count = var.tkg.clusters.workloads[count.index].control_plane_count
    ssh_public_key = file(var.tkg.clusters.workloads[count.index].public_key_path)
    vsphere_tls_thumbprint = file("vcenter_finger_print.txt")
  }
}

data "template_file" "govc_bash_script_workloads" {
  count = length(var.tkg.clusters.workloads)
  template = file("templates/govc.sh.template")
  vars = {
    dc = var.vcenter.datacenter
    cluster = var.vcenter.cluster
    vsphere_url = "administrator@${var.vcenter.sso.domain_name}:${var.vcenter_password}@${var.vcenter.name}.${var.dns.domain}"
    vcenter_folder = var.tkg.clusters.workloads[count.index].vcenter_folder
    vcenter_resource_pool = var.tkg.clusters.workloads[count.index].vcenter_resource_pool
  }
}

resource "null_resource" "transfer_templates" {
  count = length(var.tkg.clusters.workloads)
  connection {
    host        = var.vcenter.dvs.portgroup.management.external_gw_ip
    type        = "ssh"
    agent       = false
    user        = var.external_gw.username
    private_key = file(var.external_gw.private_key_path)
  }

  provisioner "file" {
    content = data.template_file.workload[count.index].rendered
    destination = "govc_workload${count.index + 1 }.sh"
  }

  provisioner "file" {
    content = data.template_file.govc_bash_script_workloads[count.index].rendered
    destination = "workload${count.index + 1 }.yml"
  }

}