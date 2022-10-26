data "template_file" "workload_values" {
  count = length(var.tkg.clusters.workloads)
  template = file("templates/values_1.7.2.yaml.template")
  vars = {
    clusterName = var.tkg.clusters.workloads[count.index].name
    cniPlugin = "antrea"

    serviceEngineGroupName = var.tkg.clusters.workloads[count.index].ako_service_engine_group_ref
    controllerVersion = var.avi.controller.version
    controllerHost = cidrhost(var.avi.controller.cidr, var.nsx.config.segments_overlay[count.index].avi_controller)
    tenantName = var.tkg.clusters.workloads[count.index].ako_tenant_ref
    password = var.avi_password


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