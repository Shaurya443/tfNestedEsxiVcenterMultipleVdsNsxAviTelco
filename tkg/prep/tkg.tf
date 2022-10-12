resource "null_resource" "prep_tkg_transfer" {

  connection {
    host        = var.vcenter.dvs.portgroup.management.external_gw_ip
    type        = "ssh"
    agent       = false
    user        = var.external_gw.username
    private_key = file(var.external_gw.private_key_path)
  }

  provisioner "file" {
    source      = var.tkg.tanzu_bin_location
    destination = basename(var.tkg.tanzu_bin_location)
  }

  provisioner "file" {
    source      = var.tkg.k8s_bin_location
    destination = basename(var.tkg.tanzu_bin_location)
  }

  provisioner "file" {
    source      = var.tkg.ova_location
    destination = basename(var.tkg.ova_location)
  }

  provisioner "remote-exec" {
    inline = [
      "tar -xf basename(${var.tkg.tanzu_bin_location})",
      "cd cli",
      "sudo install core/v0.25.0/tanzu-core-linux_amd64 /usr/local/bin/tanzu",
      "tanzu init",
      "tanzu plugin sync",
      "cd ~",
      "tar -xf basename(${var.tkg.k8s_bin_location})",
      "chmod ugo+x kubectl-linux-v1.23.8+vmware.2",
      "sudo install kubectl-linux-v1.23.8+vmware.2 /usr/local/bin/kubectl",
      "cd ~/cli",
      "gunzip ytt-linux-amd64-v0.41.1+vmware.1.gz",
      "chmod ugo+x ytt-linux-amd64-v0.41.1+vmware.1",
      "sudo mv ./ytt-linux-amd64-v0.41.1+vmware.1 /usr/local/bin/ytt",
      "gunzip kapp-linux-amd64-v0.49.0+vmware.1.gz",
      "sudo mv ./kapp-linux-amd64-v0.49.0+vmware.1 /usr/local/bin/kapp",
      "gunzip kbld-linux-amd64-v0.34.0+vmware.1.gz",
      "chmod ugo+x kbld-linux-amd64-v0.34.0+vmware.1",
      "sudo mv ./kbld-linux-amd64-v0.34.0+vmware.1 /usr/local/bin/kbld",
      "gunzip imgpkg-linux-amd64-v0.29.0+vmware.1.gz",
      "chmod ugo+x imgpkg-linux-amd64-v0.29.0+vmware.1",
      "mv ./imgpkg-linux-amd64-v0.29.0+vmware.1 /usr/local/bin/imgpkg"
    ]
  }
}

resource "null_resource" "prep_tkg_docker_install" {

  connection {
    host        = var.vcenter.dvs.portgroup.management.external_gw_ip
    type        = "ssh"
    agent       = false
    user        = var.external_gw.username
    private_key = file(var.external_gw.private_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y ca-certificates curl gnupg lsb-release",
      "sudo mkdir -p /etc/apt/keyrings",
      "sudo rm -f /etc/apt/keyrings/docker.gpg",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg",
      "sudo rm -f /etc/apt/sources.list.d/docker.list",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "sudo apt-get update",
      "sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin",
      "sudo groupadd docker",
      "sudo usermod -aG docker $USER"
    ]
  }
}

resource "null_resource" "prep_tkg_kind_install" {
  depends_on = [null_resource.prep_tkg_docker_install]
  connection {
    host        = var.vcenter.dvs.portgroup.management.external_gw_ip
    type        = "ssh"
    agent       = false
    user        = var.external_gw.username
    private_key = file(var.external_gw.private_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.15.0/kind-linux-amd64",
      "chmod +x ./kind",
      "sudo mv ./kind /usr/local/bin/kind"
    ]
  }
}

resource "null_resource" "govc_install" {

  connection {
    host        = var.vcenter.dvs.portgroup.management.external_gw_ip
    type        = "ssh"
    agent       = false
    user        = var.external_gw.username
    private_key = file(var.external_gw.private_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "curl -L -o - \"https://github.com/vmware/govmomi/releases/latest/download/govc_$(uname -s)_$(uname -m).tar.gz\" | sudo tar -C /usr/local/bin -xvzf - govc"
    ]
  }
}

resource "null_resource" "jq_install" {
  depends_on = [null_resource.prep_tkg_kind_install]
  connection {
    host        = var.vcenter.dvs.portgroup.management.external_gw_ip
    type        = "ssh"
    agent       = false
    user        = var.external_gw.username
    private_key = file(var.external_gw.private_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt install -y jq"
    ]
  }
}

data "template_file" "govc_bash_script" {
  template = file("templates/govc.sh.template")
  vars = {
    dc = var.vcenter.datacenter
    vsphere_url = "administrator@${var.vcenter.sso.domain_name}:${var.vcenter_password}@${var.vcenter.name}.${var.dns.domain}"
    ova_folder_template = var.tkg.ova_folder_template
    ova_basename = basename(var.tkg.ova_location)
    ova_network = var.tkg.ova_network
    cluster = var.vcenter.cluster
  }
}

resource "null_resource" "govc_run" {
  depends_on = [null_resource.govc_install, null_resource.prep_tkg_transfer]
  connection {
    host        = var.vcenter.dvs.portgroup.management.external_gw_ip
    type        = "ssh"
    agent       = false
    user        = var.external_gw.username
    private_key = file(var.external_gw.private_key_path)
  }

  provisioner "file" {
    content = data.template_file.govc_bash_script.rendered
    destination = "govc_mgmt.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "/bin/bash govc_mgmt.sh"
    ]
  }
}