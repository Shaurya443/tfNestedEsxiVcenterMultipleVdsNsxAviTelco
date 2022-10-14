#!/bin/bash
type terraform >/dev/null 2>&1 || { echo >&2 "terraform is not installed - please visit: https://learn.hashicorp.com/tutorials/terraform/install-cli to install it - Aborting." ; exit 255; }
type jq >/dev/null 2>&1 || { echo >&2 "jq is not installed - please install it - Aborting." ; exit 255; }
type govc >/dev/null 2>&1 || { echo >&2 "govc is not installed - please install it - Aborting." ; exit 255; }
type genisoimage >/dev/null 2>&1 || { echo >&2 "genisoimage is not installed - please install it - Aborting." ; exit 255; }
type ansible-playbook >/dev/null 2>&1 || { echo >&2 "ansible-playbook is not installed - please install it - Aborting." ; exit 255; }
if ! ansible-galaxy collection list | grep community.vmware > /dev/null ; then echo "ansible collection community.vmware is not installed - please install it - Aborting." ; exit 255 ; fi
if ! ansible-galaxy collection list | grep ansible_for_nsxt > /dev/null ; then echo "ansible collection vmware.ansible_for_nsxt is not installed - please install it - Aborting." ; exit 255 ; fi
if ! pip3 list | grep  pyvmomi > /dev/null ; then echo "python pyvmomi is not installed - please install it - Aborting." ; exit 255 ; fi
#
# Script to run before TF
#
if [ -f "variables.json" ]; then
  jsonFile="variables.json"
else
  echo "variables.json file not found!!"
  exit 255
fi
#
# Sanity checks
#
# check if the TKG binaries and ova files are present
echo "Checking TKG/Tanzu variables.json parameters..."
if [[ $(jq -c -r .tkg.prep $jsonFile) == true ]] ; then
  echo "==> Checking Tanzu Binaries and OVA..."
  if [ -f $(jq -c -r .tkg.tanzu_bin_location $jsonFile) ]; then
    echo "   +++ $(jq -c -r .tkg.tanzu_bin_location $jsonFile): OK."
  else
    echo "   +++ERROR+++ $(jq -c -r .tkg.tanzu_bin_location $jsonFile) file not found!!"
    exit 255
  fi
  if [ -f $(jq -c -r .tkg.k8s_bin_location $jsonFile) ]; then
    echo "   +++ $(jq -c -r .tkg.k8s_bin_location $jsonFile): OK."
  else
    echo "   +++ERROR+++ $(jq -c -r .tkg.k8s_bin_location) file not found!!"
    exit 255
  fi
  if [ -f $(jq -c -r .tkg.ova_location $jsonFile) ]; then
    echo "   +++ $(jq -c -r .tkg.ova_location $jsonFile): OK."
  else
    echo "   +++ERROR+++ $(jq -c -r .tkg.ova_location) file not found!!"
    exit 255
  fi
fi
#
# check if Avi file is present
if [[ $(jq -c -r .avi.controller.create $jsonFile) == true ]] || [[ $(jq -c -r .avi.content_library.create $jsonFile) == true ]] ; then
  echo "==> Checking Avi OVA..."
    if [ -f $(jq -c -r .avi.content_library.ova_location $jsonFile) ]; then
      echo "   +++ $(jq -c -r .avi.content_library.ova_location $jsonFile): OK."
    else
      echo "   +++ERROR+++ $(jq -c -r .avi.content_library.ova_location $jsonFile) file not found!!"
      exit 255
    fi
fi
#
# check if the amount of external IP is enough for all the interfaces of the tier0
IFS=$'\n'
ip_count_external_tier0=$(jq -c -r '.vcenter.dvs.portgroup.nsx_external.tier0_ips | length' $jsonFile)
tier0_ifaces=0
for tier0 in $(jq -c -r .nsx.config.tier0s[] $jsonFile)
do
#  echo $tier0
  tier0_ifaces=$((tier0_ifaces+$(echo $tier0 | jq -c -r '.interfaces | length')))
done
if [[ $tier0_ifaces -gt $ip_count_external_tier0 ]] ; then
  echo "Amount of IPs (.vcenter.dvs.portgroup.nsx_external.tier0_ips) cannot cover the amount of tier0 interfaces defined in .nsx.config.tier0s[].interfaces"
  exit 255
fi
# check if the amount of interfaces in vip config is equal to two for each tier0
for tier0 in $(jq -c -r .nsx.config.tier0s[] $jsonFile)
do
  for vip in $(echo $tier0 | jq -c -r .ha_vips[])
  do
    if [[ $(echo $vip | jq -c -r '.interfaces | length') -ne 2 ]] ; then
      echo "Amount of interfaces (.nsx.config.tier0s[].ha_vips[].interfaces) needs to be equal to 2; tier0 called $(echo $tier0 | jq -c -r .display_name) has $(echo $vip | jq -c -r '.interfaces | length') interfaces for its ha_vips"
      exit 255
    fi
  done
done
# check if the amount of external vip is enough for all the vips of the tier0s
vip_count_external_tier0=$(jq -c -r '.vcenter.dvs.portgroup.nsx_external.tier0_vips | length' $jsonFile)
tier0_vips=0
for tier0 in $(jq -c -r .nsx.config.tier0s[] $jsonFile)
do
  for vip in $(echo $tier0 | jq -c -r .ha_vips[])
  do
    tier0_vips=$((tier0_vips+$(echo $tier0 | jq -c -r '.ha_vips | length')))
  done
if [[ $tier0_vips -gt $vip_count_external_tier0 ]] ; then
  echo "Amount of VIPs (.vcenter.dvs.portgroup.nsx_external.tier0_vips) cannot cover the amount of ha_vips defined in .nsx.config.tier0s[].ha_vips"
  exit 255
fi
done
#
tf_init_apply () {
  # $1 messsage to display
  # $2 is the folder to init/apply tf
  # $3 is the log path file for tf stdout
  # $4 is the log path file for tf error
  # $5 is var-file to feed TF with variables
  echo "-----------------------------------------------------"
  echo $1
  echo "Starting timestamp: $(date)"
  cd $2
  terraform init > $3 2>$4
  if [ -s "$4" ] ; then
    echo "TF Init ERRORS:"
    cat $4
    exit 1
  else
    rm $3 $4
  fi
  terraform apply -auto-approve -var-file=$5 > $3 2>$4
  if [ -s "$4" ] ; then
    echo "TF Apply ERRORS:"
    cat $4
#    echo "Waiting for 30 seconds - retrying TF Apply..."
#    sleep 10
#    rm -f $3 $4
#    terraform apply -auto-approve -var-file=$5 > $3 2>$4
#    if [ -s "$4" ] ; then
#      echo "TF Apply ERRORS:"
#      cat $4
#      exit 1
#    fi
    exit 1
  fi
  echo "Ending timestamp: $(date)"
  cd - > /dev/null
}
#
# Build of a folder on the underlay infrastructure
#
tf_init_apply "Build of a folder on the underlay infrastructure - This should take less than a minute" vsphere_underlay_folder ../logs/tf_vsphere_underlay_folder.stdout ../logs/tf_vsphere_underlay_folder.errors ../$jsonFile
#
# Build of a DNS/NTP server on the underlay infrastructure
#
if [[ $(jq -c -r .dns_ntp.create $jsonFile) == true ]] ; then
  tf_init_apply "Build of a DNS/NTP server on the underlay infrastructure - This should take less than 5 minutes" dns_ntp ../logs/tf_dns_ntp.stdout ../logs/tf_dns_ntp.errors ../$jsonFile
fi
#
# Build of an external GW server on the underlay infrastructure
#
if [[ $(jq -c -r .external_gw.create $jsonFile) == true ]] ; then
  tf_init_apply "Build of an external GW server on the underlay infrastructure - This should take less than 5 minutes" external_gw ../logs/tf_external_gw.stdout ../logs/tf_external_gw.errors ../$jsonFile
fi
#
# Build of the nested ESXi/vCenter infrastructure
#
tf_init_apply "Build of the nested ESXi/vCenter infrastructure - This should take less than 45 minutes" nested_esxi_vcenter ../logs/tf_nested_esxi_vcenter.stdout ../logs/tf_nested_esxi_vcenter.errors ../$jsonFile
echo "waiting for 20 minutes to finish the vCenter config..."
sleep 1200
#
# Build of the NSX Nested Networks
#
if [[ $(jq -c -r .nsx.networks.create $jsonFile) == true ]] ; then
  tf_init_apply "Build of NSX Nested Networks - This should take less than a minute" nsx/networks ../../logs/tf_nsx_networks.stdout ../../logs/tf_nsx_networks.errors ../../$jsonFile
fi
#
# Build of the nested NSXT Manager
#
if [[ $(jq -c -r .nsx.manager.create $jsonFile) == true ]] || [[ $(jq -c -r .nsx.content_library.create $jsonFile) == true ]] ; then
  tf_init_apply "Build of the nested NSXT Manager - This should take less than 20 minutes" nsx/manager ../../logs/tf_nsx.stdout ../../logs/tf_nsx.errors ../../$jsonFile
  if [[ $(jq -c -r .nsx.manager.create $jsonFile) == true ]] ; then
    echo "waiting for 5 minutes to finish the NSXT bootstrap..."
    sleep 300
  fi
fi
#
# Build of the config of NSX-T
#
if [[ $(jq -c -r .nsx.config.create $jsonFile) == true ]] ; then
  tf_init_apply "Build of the config of NSX-T - This should take less than 60 minutes" nsx/config ../../logs/tf_nsx_config.stdout ../../logs/tf_nsx_config.errors ../../$jsonFile
fi
#
# Build of the Nested Avi Controllers
#
if [[ $(jq -c -r .avi.controller.create $jsonFile) == true ]] || [[ $(jq -c -r .avi.content_library.create $jsonFile) == true ]] ; then
  #
  # Add Routes to join overlay network
  #
#  for route in $(jq -c -r .external_gw.routes[] $jsonFile)
#  do
#    sudo ip route add $(echo $route | jq -c -r '.to') via $(jq -c -r .vcenter.dvs.portgroup.management.external_gw_ip $jsonFile)
#  done
  tf_init_apply "Build of Nested Avi Controllers - This should take around 15 minutes" avi/controllers ../../logs/tf_avi_controller.stdout ../../logs/tf_avi_controller.errors ../../$jsonFile
  tf_init_apply "Build of Avi Cert for TKG - This should take less than a minute" avi/tkg_cert ../../logs/tf_avi_tkg_cert.stdout ../../logs/tf_avi_tkg_cert.errors ../../$jsonFile
  #
  # Remove Routes to join overlay network
  #
#  for route in $(jq -c -r .external_gw.routes[] $jsonFile)
#  do
#    sudo ip route del $(echo $route | jq -c -r '.to') via $(jq -c -r .vcenter.dvs.portgroup.management.external_gw_ip $jsonFile)
#  done
fi
#
# Build of the Nested Avi App
#
if [[ $(jq -c -r .avi.app.create $jsonFile) == true ]] ; then
  #
  # Add Routes to join overlay network
  #
#  for route in $(jq -c -r .external_gw.routes[] $jsonFile)
#  do
#    sudo ip route add $(echo $route | jq -c -r '.to') via $(jq -c -r .vcenter.dvs.portgroup.management.external_gw_ip $jsonFile)
#  done
  tf_init_apply "Build of Nested Avi App - This should take less than 10 minutes" avi/app ../../logs/tf_avi_app.stdout ../../logs/tfavi_app.errors ../../$jsonFile
  #
  # Remove Routes to join overlay network
  #
#  for route in $(jq -c -r .external_gw.routes[] $jsonFile)
#  do
#    sudo ip route del $(echo $route | jq -c -r '.to') via $(jq -c -r .vcenter.dvs.portgroup.management.external_gw_ip $jsonFile)
#  done
fi
#
# Build of the config of Avi
#
rm avi.json
IFS=$'\n'
avi_json=""
avi_networks="[]"
# copy cidr from nsx.config.segments_overlay to avi.config.cloud.networks (useful for vCenter cloud as we can't retrieve the CIDR through API)
for network in $(jq -c -r .avi.config.cloud.networks[] $jsonFile)
do
  network_name=$(echo $network | jq -c -r .name)
  for segment in $(jq -c -r .nsx.config.segments_overlay[] $jsonFile)
  do
    if [[ $(echo $segment | jq -r .display_name) == $(echo $network_name) ]] ; then
      cidr=$(echo $segment | jq -r .cidr)
    fi
  done
  new_network=$(echo $network | jq '. += {"cidr": "'$(echo $cidr)'"}')
  avi_networks=$(echo $avi_networks | jq '. += ['$(echo $new_network)']')
done
avi_json=$(jq -c -r . $jsonFile | jq '. | del (.avi.config.cloud.networks)')
avi_json=$(echo $avi_json | jq '.avi.config.cloud += {"networks": '$(echo $avi_networks)'}')
# copy cidr from avi.config.cloud.networks to avi.config.virtual_services.http
if [[ $(echo $avi_json | jq -c -r '.avi.config.virtual_services.http | length') -gt 0 ]] ; then
  avi_http_vs=[]
  for vs in $(echo $avi_json | jq -c -r .avi.config.virtual_services.http[])
  do
    for network in $(echo $avi_json | jq -c -r .avi.config.cloud.networks[])
    do
      if [[ $(echo $network | jq -c -r .name) == $(echo $vs | jq -c -r '.network_ref') ]] ; then
        cidr=$(echo $network | jq -r .cidr)
      fi
      if [[ $(echo $network | jq -c -r .name) == $(echo $vs | jq -c -r '.network_ref') ]] ; then
        type=$(echo $network | jq -r .type)
      fi
    done
    new_vs_http=$(echo $vs | jq '. += {"cidr": "'$(echo $cidr)'", "type": "'$(echo $type)'"}')
    avi_http_vs=$(echo $avi_dns_vs | jq '. += ['$(echo $new_vs_http)']')
  done
fi
# copy cidr from avi.config.cloud.networks to avi.config.virtual_services.dns
if [[ $(echo $avi_json | jq -c -r '.avi.config.virtual_services.dns | length') -gt 0 ]] ; then
  avi_dns_vs=[]
  for vs in $(echo $avi_json | jq -c -r .avi.config.virtual_services.dns[])
  do
    for network in $(echo $avi_json | jq -c -r .avi.config.cloud.networks[])
    do
      if [[ $(echo $network | jq -c -r .name) == $(echo $vs | jq -c -r '.network_ref') ]] ; then
        cidr=$(echo $network | jq -r .cidr)
      fi
      if [[ $(echo $network | jq -c -r .name) == $(echo $vs | jq -c -r '.network_ref') ]] ; then
        type=$(echo $network | jq -r .type)
      fi
    done
    new_vs_dns=$(echo $vs | jq '. += {"cidr": "'$(echo $cidr)'", "type": "'$(echo $type)'"}')
    avi_dns_vs=$(echo $avi_dns_vs | jq '. += ['$(echo $new_vs_dns)']')
  done
fi
avi_json=$(echo $avi_json | jq '. | del (.avi.config.virtual_services.dns)')
avi_json=$(echo $avi_json | jq '.avi.config.virtual_services += {"dns": '$(echo $avi_dns_vs)'}')
echo $avi_json | jq . | tee avi.json
#
if [[ $(jq -c -r .avi.controller.create $jsonFile) == true ]] && [[ $(jq -c -r .avi.config.create $jsonFile) == true ]] ; then
  tf_init_apply "Build of the config of Avi - This should take less than 20 minutes" avi/config ../../logs/tf_avi_config.stdout ../../logs/tf_avi_config.errors ../../avi.json
fi
#
# TKG prep
#
if [[ $(jq -c -r .tkg.prep $jsonFile) == true ]] && [[ $(jq -c -r .external_gw.create $jsonFile) == true ]] ; then
  tf_init_apply "Prep of TKG - This should take less than 20 minutes" tkg/prep ../../logs/tf_tkg_prep.stdout ../../logs/tf_tkg_prep.errors ../../$jsonFile
fi
#
# Templating of TKG mgmt-cluster
#
if [[ $(jq -c -r .external_gw.create $jsonFile) == true ]] && [[ $(jq -c -r .tkg.clusters.management_template $jsonFile) == true ]] ; then
  tf_init_apply "Templating of TKG mgmt cluster - This should take less than one minute" tkg/mgmt_cluster_template ../../logs/tf_mgmt_cluster_template.stdout ../../logs/tf_mgmt_cluster_template.errors ../../$jsonFile
fi
#
# Build of TKG mgmt-cluster
#
if [[ $(jq -c -r .external_gw.create $jsonFile) == true ]] && [[ $(jq -c -r .tkg.clusters.management_template $jsonFile) == true ]] && [[ $(jq -c -r .tkg.clusters.management_build $jsonFile) == true ]] ; then
  tf_init_apply "Templating of TKG mgmt cluster - This should take less than 15 minutes" tkg/mgmt_cluster_build ../../logs/tf_mgmt_cluster_build.stdout ../../logs/tf_mgmt_cluster_build.errors ../../$jsonFile
fi
#
# Templating of TKG workload-clusters
#
if [[ $(jq -c -r .external_gw.create $jsonFile) == true ]] && [[ $(jq -c -r .tkg.clusters.workload_template $jsonFile) == true ]] ; then
  tf_init_apply "Templating of TKG workload cluster(s) - This should take less than one minute" tkg/workload_clusters_templates ../../logs/tf_workload_clusters_templates.stdout ../../logs/tf_workload_clusters_templates.errors ../../$jsonFile
fi
#
# Build of TKG workload-clusters
#
if [[ $(jq -c -r .external_gw.create $jsonFile) == true ]] && [[ $(jq -c -r .tkg.clusters.workload_template $jsonFile) == true ]] && [[ $(jq -c -r .tkg.clusters.workload_build $jsonFile) == true ]] ; then
  tf_init_apply "Templating of TKG workload cluster(s) - This should take less than 15 minutes" tkg/workload_clusters_builds ../../logs/tf_workload_clusters_builds.stdout ../../logs/tf_workload_clusters_builds.errors ../../$jsonFile
fi
#
#
# Output message
#
echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo "Configure your local DNS by using $(jq -c -r .dns.nameserver $jsonFile)"
echo "vCenter url: https://$(jq -c -r .vcenter.name $jsonFile).$(jq -c -r .dns.domain $jsonFile)"
echo "NSX url: https://$(jq -c -r .nsx.manager.basename $jsonFile).$(jq -c -r .dns.domain $jsonFile)"
echo "To access Avi UI:"
echo "  - configure $(jq -c -r .vcenter.dvs.portgroup.management.external_gw_ip $jsonFile) as a socks proxy"
echo "  - Avi url: https://$(jq -c -r .nsx.config.segments_overlay[0].cidr $jsonFile | cut -d'/' -f1 | cut -d'.' -f1-3).$(jq -c -r .nsx.config.segments_overlay[0].avi_controller $jsonFile)"
