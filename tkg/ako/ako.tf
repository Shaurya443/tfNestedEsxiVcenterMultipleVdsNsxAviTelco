data "template_file" "workload_values" {
  count = length(var.tkg.clusters.workloads)
  template = file("templates/values_1.7.2.yaml.template")
  vars = {
    clusterName = var.tkg.clusters.workloads[count.index].name
    cniPlugin = "antrea"
    default_peer_label = var.tkg.clusters.ako_default_bgp_peer_label_ref
    networkName = var.tkg.clusters.ako_vip_network_name_ref
    cidr = var.tkg.clusters.ako_vip_network_cidr # added by apply.sh
    serviceEngineGroupName = var.tkg.clusters.ako_service_engine_group_ref
    controllerVersion = var.avi.controller.version
    controllerHost = cidrhost(var.tkg.avi_cidr, var.tkg.avi_ip)
    tenantName = var.tkg.clusters.ako_tenant_ref
    password = var.avi_password
  }
}

data "template_file" "infra_settings" {
  count = length(var.tkg.clusters.ako_bgp_labels)
  template = file("templates/AviInfraSetting.yml.template")
  vars = {
    name = "infra-setting-${count.index + 1}"
    serviceEngineGroupName = var.tkg.clusters.ako_service_engine_group_ref
    networkName = var.tkg.clusters.ako_vip_network_name_ref
    cidr = var.tkg.clusters.ako_vip_network_cidr # added by apply.sh
    peer_bgp_label = var.tkg.clusters.ako_bgp_labels[count.index]
  }
}

data "template_file" "svcs" {
  count = length(var.tkg.clusters.ako_bgp_labels)
  template = file("templates/svc.yml.template")
  vars = {
    name = "svc-vrf-${count.index + 1}"
    aviinfrasetting = "infra-setting-${count.index + 1}"
    selector_app = "cnf"
  }
}


resource "null_resource" "transfer_ako_values_files" {
  count = length(var.tkg.clusters.workloads)

  connection {
    host        = var.vcenter.dvs.portgroup.management.external_gw_ip
    type        = "ssh"
    agent       = false
    user        = var.external_gw.username
    private_key = file(var.external_gw.private_key_path)
  }

  provisioner "file" {
    content = data.template_file.workload_values[count.index].rendered
    destination = "ako-values-workload${count.index + 1}.yml"
  }
}

resource "null_resource" "transfer_ako_values_files" {
  count = length(var.tkg.clusters.ako_bgp_labels)

  connection {
    host        = var.vcenter.dvs.portgroup.management.external_gw_ip
    type        = "ssh"
    agent       = false
    user        = var.external_gw.username
    private_key = file(var.external_gw.private_key_path)
  }

  provisioner "file" {
    content = data.template_file.infra_settings[count.index].rendered
    destination = "avi-infra-settings-workload-vrf${count.index + 1}.yml"
  }

  provisioner "file" {
    content = data.template_file.svcs[count.index].rendered
    destination = "avi-svc-vrf${count.index + 1}.yml"
  }
}
