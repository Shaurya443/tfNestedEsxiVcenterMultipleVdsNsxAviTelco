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
IFS=$'\n'
#
# Sanity checks
#
echo "==> Creqting External gateway routes..."
rm -f external_gw.json
new_routes="[]"
external_gw_json=$(jq -c -r . $jsonFile | jq .)
for segment in $(jq -c -r .nsx.config.segments_overlay[] $jsonFile)
do
  for tier1 in $(jq -c -r .nsx.config.tier1s[] $jsonFile)
  do
    if [[ $(echo $segment | jq -c -r .tier1) == $(echo $tier1 | jq -c -r .display_name) ]] ; then
      count=0
      for tier0 in $(jq -c -r .nsx.config.tier0s[] $jsonFile)
      do
        if [[ $(echo $tier1 | jq -c -r .tier0) == $(echo $tier0 | jq -c -r .display_name) ]] ; then
          new_routes=$(echo $new_routes | jq '. += [{"to": "'$(echo $segment | jq -c -r .cidr)'", "via": "'$(jq -c -r .vcenter.dvs.portgroup.nsx_external.tier0_vips["$count"] $jsonFile)'"}]')
          echo "   +++ Route to '$(echo $segment | jq -c -r .cidr)' via $(jq -c -r .vcenter.dvs.portgroup.nsx_external.tier0_vips["$count"] $jsonFile) added: OK"
        fi
        ((count++))
      done
    fi
  done
done
external_gw_json=$(echo $external_gw_json | jq '.external_gw += {"routes": '$(echo $new_routes)'}')
echo $external_gw_json | jq . | tee external_gw.json > /dev/null
#
#
echo "==> Checking NSX Settings..."
echo "   +++ Checking NSX OVA..."
if [ -f $(jq -c -r .nsx.content_library.ova_location $jsonFile) ]; then
  echo "   ++++++ $(jq -c -r .nsx.content_library.ova_location $jsonFile): OK."
else
  echo "   ++++++ERROR++++++ $(jq -c -r .nsx.content_library.ova_location $jsonFile) file not found!!"
  exit 255
fi
rm -f nsx.json
IFS=$'\n'
nsx_json=""
nsx_segments="[]"
nsx_segment_external=0
echo "   +++ Checking NSX external segments..."
for segment in $(jq -c -r .nsx.config.segments[] $jsonFile)
do
  if [[ $(echo $segment | jq -c -r .nsx_external) == true ]] ; then
    ((nsx_segment_external++))
    cidr=$(jq -c -r .vcenter.dvs.portgroup.nsx_external.cidr $jsonFile)
    echo "   ++++++ Adding CIDR to external segment called $(echo $segment | jq -c -r .name): $(jq -c -r .vcenter.dvs.portgroup.nsx_external.cidr $jsonFile)"
    new_segment=$(echo $segment | jq '. += {"cidr": "'$(echo $cidr)'"}')
  else
    new_segment=$(echo $segment)
  fi
  if [[ $nsx_segment_external -gt 1 ]] ; then
    echo "   ++++++ERROR++++++ only one segment can be nsx_external network in .nsx.config.segments[] - found: $nsx_segment_external !!"
    exit 255
  fi
  nsx_segments=$(echo $nsx_segments | jq '. += ['$(echo $new_segment)']')
done
nsx_json=$(jq -c -r . $jsonFile | jq '. | del (.nsx.config.segments)')
nsx_json=$(echo $nsx_json | jq '.nsx.config += {"segments": '$(echo $nsx_segments)'}')
echo $nsx_json | jq . | tee nsx.json > /dev/null
#
#
echo "   +++ Checking NSX if the amount of external IP(s) are enough for all the interfaces of the tier0(s)..."
ip_count_external_tier0=$(jq -c -r '.vcenter.dvs.portgroup.nsx_external.tier0_ips | length' $jsonFile)
tier0_ifaces=0
for tier0 in $(jq -c -r .nsx.config.tier0s[] $jsonFile)
do
  tier0_ifaces=$((tier0_ifaces+$(echo $tier0 | jq -c -r '.interfaces | length')))
done
if [[ $tier0_ifaces -gt $ip_count_external_tier0 ]] ; then
  echo "   ++++++ERROR++++++ Amount of IPs (.vcenter.dvs.portgroup.nsx_external.tier0_ips) cannot cover the amount of tier0 interfaces defined in .nsx.config.tier0s[].interfaces"
  exit 255
fi
echo "   ++++++ Amount of tier0(s) interfaces: $tier0_ifaces, Amount of of IP(s): $ip_count_external_tier0, OK"
#
#
echo "   +++ Checking NSX if if the amount of interfaces in vip config is equal to two for each tier0..."
for tier0 in $(jq -c -r .nsx.config.tier0s[] $jsonFile)
do
  for vip in $(echo $tier0 | jq -c -r .ha_vips[])
  do
    if [[ $(echo $vip | jq -c -r '.interfaces | length') -ne 2 ]] ; then
      echo "   ++++++ERROR++++++ Amount of interfaces (.nsx.config.tier0s[].ha_vips[].interfaces) needs to be equal to 2; tier0 called $(echo $tier0 | jq -c -r .display_name) has $(echo $vip | jq -c -r '.interfaces | length') interfaces for its ha_vips"
      exit 255
    fi
    echo "   ++++++ Amount of interfaces for $(echo $tier0 | jq -c -r .display_name): $(echo $vip | jq -c -r '.interfaces | length'), OK"
  done
done
#
#
echo "   +++ Checking NSX if the amount of external vip is enough for all the vips of the tier0s..."
tier0_vips=0
for tier0 in $(jq -c -r .nsx.config.tier0s[] $jsonFile)
do
  for vip in $(echo $tier0 | jq -c -r .ha_vips[])
  do
    tier0_vips=$((tier0_vips+$(echo $tier0 | jq -c -r '.ha_vips | length')))
  done
  if [[ $tier0_vips -gt $(jq -c -r '.vcenter.dvs.portgroup.nsx_external.tier0_vips | length' $jsonFile) ]] ; then
    echo "   ++++++ERROR++++++ Amount of VIPs (.vcenter.dvs.portgroup.nsx_external.tier0_vips) cannot cover the amount of ha_vips defined in .nsx.config.tier0s[].ha_vips"
    exit 255
  fi
done
echo "   ++++++ Amount of external vip is $(jq -c -r '.vcenter.dvs.portgroup.nsx_external.tier0_vips | length' $jsonFile), amount of vip needed: $tier0_vips, OK"


# check Avi Parameters
## check Avi OVA
rm -f avi.json
IFS=$'\n'
avi_json=""
avi_networks="[]"
echo "==> Checking Avi Settings..."
echo "   +++ Checking Avi OVA"
if [ -f $(jq -c -r .avi.content_library.ova_location $jsonFile) ]; then
  echo "   ++++++ $(jq -c -r .avi.content_library.ova_location $jsonFile): OK."
else
  echo "   ++++++ERROR++++++ $(jq -c -r .avi.content_library.ova_location $jsonFile) file not found!!"
  exit 255
fi
# check Avi Controller Network
# copying segment info (ip, cidr, and gw keys) to avi.controller
echo "   +++ Checking Avi Controller network settings"
avi_controller_network=0
for segment in $(jq -c -r .nsx.config.segments_overlay[] $jsonFile)
do
  if [[ $(echo $segment | jq -r .display_name) == $(jq -c -r .avi.controller.network_ref $jsonFile) ]] ; then
    avi_controller_network=1
    echo "   ++++++ Avi Controller segment found: $(echo $segment | jq -r .display_name), OK"
    echo "   ++++++ Avi Controller CIDR is: $(echo $segment | jq -r .cidr), OK"
    echo "   ++++++ Avi Controller IP is: $(echo $segment | jq -r .avi_controller), OK"
    avi_json=$(jq -c -r . $jsonFile | jq '.avi.controller += {"ip": '$(echo $segment | jq .avi_controller)'}' | jq '.avi.controller += {"cidr": '$(echo $segment | jq .cidr)'}' | jq '.avi.controller += {"gw": '$(echo $segment | jq .gw)'}')
  fi
done
if [[ $avi_controller_network -eq 0 ]] ; then
  echo "   ++++++ERROR++++++ $(jq -c -r .avi.controller.network_ref $jsonFile) segment not found!!"
  exit 255
fi
# check Avi Cloud Networks against NSX segments
# copy cidr from nsx.config.segments_overlay to avi.config.cloud.networks (useful for vCenter cloud as we can't retrieve the CIDR through API)
echo "   +++ Checking Avi Cloud networks settings"
avi_cloud_network_mgmt=0
for network in $(jq -c -r .avi.config.cloud.networks[] $jsonFile)
do
  network_name=$(echo $network | jq -c -r .name)
  avi_cloud_network=0
  for segment in $(jq -c -r .nsx.config.segments_overlay[] $jsonFile)
  do
    if [[ $(echo $segment | jq -r .display_name) == $(echo $network | jq -c -r .name) ]] ; then
      avi_cloud_network=1
      echo "   ++++++ Avi cloud network found: $(echo $segment | jq -r .display_name), OK"
      cidr=$(echo $segment | jq -r .cidr)
    fi
  done
  for segment in $(jq -c -r .nsx.config.segments[] nsx.json)
  do
    if [[ $(echo $segment | jq -r .name) == $(echo $network | jq -c -r .name) ]] ; then
      avi_cloud_network=1
      echo "   ++++++ Avi cloud network found: $(echo $segment | jq -r .name), OK"
      cidr=$(echo $segment | jq -r .cidr)
    fi
  done
  if [[ $avi_cloud_network -eq 0 ]] ; then
    echo "   ++++++ERROR++++++ $(echo $network | jq -c -r .name) segment not found!!"
    exit 255
  fi
  new_network=$(echo $network | jq '. += {"cidr": "'$(echo $cidr)'"}')
  avi_networks=$(echo $avi_networks | jq '. += ['$(echo $new_network)']')
  if [[ $(echo $network | jq -c -r .management) == true ]] ; then
    ((avi_cloud_network_mgmt++))
  fi
  if [[ $avi_cloud_network_mgmt -gt 1 ]] ; then
    echo "   ++++++ERROR++++++ only one network can be management network in .avi.config.cloud.networks[] - found: $avi_cloud_network_mgmt !!"
    exit 255
  fi
done
avi_json=$(echo $avi_json | jq '. | del (.avi.config.cloud.networks)')
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
echo $avi_json | jq . | tee avi.json > /dev/null
## check Avi IPAM Networks against Avi Cloud Networks segments
echo "   +++ Checking Avi IPAM networks settings"
for network_ipam in $(jq -c -r .avi.config.ipam.networks[] $jsonFile)
do
  avi_ipam_network=0
  for network in $(jq -c -r .avi.config.cloud.networks[] $jsonFile)
  do
    if [[ $(echo $network_ipam) == $(echo $network | jq -c -r .name) ]] ; then
      avi_ipam_network=1
      echo "   ++++++ Avi IPAM network found: $(echo $network | jq -c -r .name), OK"
    fi
  done
  if [[ $avi_ipam_network -eq 0 ]] ; then
    echo "   ++++++ERROR++++++ $(echo $network_ipam) segment not found!!"
    exit 255
  fi
done

# check TKG Parameters
if [[ $(jq -c -r .tkg.prep $jsonFile) == true ]] ; then
  echo "==> Checking TKG Settings..."
  echo "   +++ Checking TKG Binaries"
  if [ -f $(jq -c -r .tkg.tanzu_bin_location $jsonFile) ]; then
    echo "   ++++++ $(jq -c -r .tkg.tanzu_bin_location $jsonFile): OK."
  else
    echo "   ++++++ERROR++++++ $(jq -c -r .tkg.tanzu_bin_location $jsonFile) file not found!!"
    exit 255
  fi
  if [ -f $(jq -c -r .tkg.k8s_bin_location $jsonFile) ]; then
    echo "   ++++++ $(jq -c -r .tkg.k8s_bin_location $jsonFile): OK."
  else
    echo "   ++++++ERROR++++++ $(jq -c -r .tkg.k8s_bin_location $jsonFile) file not found!!"
    exit 255
  fi
  if [ -f $(jq -c -r .tkg.ova_location $jsonFile) ]; then
    echo "   ++++++ $(jq -c -r .tkg.ova_location $jsonFile): OK."
  else
    echo "   ++++++ERROR++++++ $(jq -c -r .tkg.ova_location $jsonFile) file not found!!"
    exit 255
  fi
#
#
  echo "   +++ Checking TKG network(s)"
  tkg_mgmt_network=0
  for segment in $(jq -c -r .nsx.config.segments_overlay[] $jsonFile)
  do
    if [[ $(echo $segment | jq -r .display_name) == $(jq -c -r .tkg.clusters.management.vsphere_network $jsonFile) ]] ; then
      tkg_mgmt_network=1
      echo "   ++++++ TKG mgmt segment found: $(echo $segment | jq -r .display_name), OK"
    fi
  done
  if [[ $tkg_mgmt_network -eq 0 ]] ; then
    echo "   ++++++ERROR++++++ $(jq -c -r .tkg.clusters.management.vsphere_network $jsonFile) segment not found!!"
    exit 255
  fi
  for cluster in $(jq -c -r .tkg.clusters.workloads[] $jsonFile)
  do
    tkg_workload_network=0
    for segment in $(jq -c -r .nsx.config.segments_overlay[] $jsonFile)
    do
      if [[ $(echo $segment | jq -r .display_name) == $(echo $cluster | jq -c -r .vsphere_network) ]] ; then
        tkg_workload_network=1
        echo "   ++++++ TKG workload segment found: $(echo $segment | jq -r .display_name), OK"
      fi
    done
    if [[ $tkg_workload_network -eq 0 ]] ; then
      echo "   ++++++ERROR++++++ $(echo $cluster | jq -c -r .vsphere_network) segment not found!!"
      exit 255
    fi
  done
#
#
  echo "   +++ Checking TKG SSH key(s) for the mgmt cluster"
  if [ -f $(jq -c -r .tkg.clusters.management.public_key_path $jsonFile) ]; then
    echo "   ++++++ $(jq -c -r .tkg.clusters.management.public_key_path $jsonFile): OK."
  else
    echo "   ++++++ERROR++++++ $(jq -c -r .tkg.clusters.management.public_key_path $jsonFile) file not found!!"
    exit 255
  fi
  echo "   +++ Checking TKG SSH key(s) for the workload cluster(s)"
  for cluster in $(jq -c -r .tkg.clusters.workloads[] $jsonFile)
  do
    if [ -f $(echo $cluster | jq -c -r .public_key_path) ]; then
      echo "   ++++++ cluster $(echo $cluster | jq -c -r .name), key file $(echo $cluster | jq -c -r .public_key_path): OK."
    else
      echo "   ++++++ERROR++++++ cluster $(echo $cluster | jq -c -r .name), key file $(echo $cluster | jq -c -r .public_key_path) file not found!!"
      exit 255
    fi
  done
fi


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
  tf_init_apply "Build of an external GW server on the underlay infrastructure - This should take less than 5 minutes" external_gw ../logs/tf_external_gw.stdout ../logs/tf_external_gw.errors ../external_gw.json
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
  tf_init_apply "Build of Nested Avi Controllers - This should take around 15 minutes" avi/controllers ../../logs/tf_avi_controller.stdout ../../logs/tf_avi_controller.errors ../../avi.json
  tf_init_apply "Build of Avi Cert for TKG - This should take less than a minute" avi/tkg_cert ../../logs/tf_avi_tkg_cert.stdout ../../logs/tf_avi_tkg_cert.errors ../../avi.json
fi
#
# Build of the Nested Avi App
#
if [[ $(jq -c -r .avi.app.create $jsonFile) == true ]] ; then
  tf_init_apply "Build of Nested Avi App - This should take less than 10 minutes" avi/app ../../logs/tf_avi_app.stdout ../../logs/tfavi_app.errors ../../$jsonFile
fi
#
# Build of the config of Avi
#
if [[ $(jq -c -r .avi.controller.create $jsonFile) == true ]] && [[ $(jq -c -r .avi.config.create $jsonFile) == true ]] ; then
  tf_init_apply "Build of the config of Avi - This should take less than 20 minutes" avi/config ../../logs/tf_avi_config.stdout ../../logs/tf_avi_config.errors ../../avi.json
fi
#
# Add AKO repo in helm
#
if [[ $(jq -c -r .avi.config.ako.add_ako_repo $jsonFile) == true ]] ; then
  tf_init_apply "Add AKO repo to helm - This should take less than a minute" avi/avi_helm_ako ../../logs/tf_avi_helm_ako.stdout ../../logs/tf_avi_helm_ako.errors ../../avi.json
fi
#
# Creation of TKG json file
#
# copy of the Avi IP and AVI CIDR
rm tkg.json
IFS=$'\n'
tkg_json=$(jq -c -r . $jsonFile)
for segment in $(jq -c -r .nsx.config.segments_overlay[] $jsonFile)
do
  if [[ $(echo $segment | jq -r .display_name) == $(jq -c -r .avi.controller.network_ref $jsonFile) ]] ; then
    tkg_json=$(echo $tkg_json | jq '.tkg += {"avi_cidr": '$(echo $segment | jq .cidr)'}' | jq '.tkg += {"avi_ip": '$(echo $segment | jq .avi_controller)'}')
  fi
done
echo $tkg_json | jq . | tee tkg.json > /dev/null
#
# TKG prep
#
if [[ $(jq -c -r .tkg.prep $jsonFile) == true ]] && [[ $(jq -c -r .external_gw.create $jsonFile) == true ]] ; then
  tf_init_apply "Prep of TKG - This should take less than 20 minutes" tkg/prep ../../logs/tf_tkg_prep.stdout ../../logs/tf_tkg_prep.errors ../../tkg.json
fi
#
# Templating of TKG mgmt-cluster
#
if [[ $(jq -c -r .external_gw.create $jsonFile) == true ]] && [[ $(jq -c -r .tkg.clusters.management_template $jsonFile) == true ]] ; then
  tf_init_apply "Templating of TKG mgmt cluster - This should take less than one minute" tkg/mgmt_cluster_template ../../logs/tf_mgmt_cluster_template.stdout ../../logs/tf_mgmt_cluster_template.errors ../../tkg.json
fi
#
# Build of TKG mgmt-cluster
#
if [[ $(jq -c -r .external_gw.create $jsonFile) == true ]] && [[ $(jq -c -r .tkg.clusters.management_template $jsonFile) == true ]] && [[ $(jq -c -r .tkg.clusters.management_build $jsonFile) == true ]] ; then
  tf_init_apply "Building TKG mgmt cluster - This should take less than 25 minutes" tkg/mgmt_cluster_build ../../logs/tf_mgmt_cluster_build.stdout ../../logs/tf_mgmt_cluster_build.errors ../../tkg.json
fi
#
# Templating of TKG workload-clusters
#
if [[ $(jq -c -r .external_gw.create $jsonFile) == true ]] && [[ $(jq -c -r .tkg.clusters.workload_template $jsonFile) == true ]] ; then
  tf_init_apply "Templating of TKG workload cluster(s) - This should take less than one minute" tkg/workload_clusters_templates ../../logs/tf_workload_clusters_templates.stdout ../../logs/tf_workload_clusters_templates.errors ../../tkg.json
fi
#
# Build of TKG workload-clusters
#
if [[ $(jq -c -r .external_gw.create $jsonFile) == true ]] && [[ $(jq -c -r .tkg.clusters.workload_template $jsonFile) == true ]] && [[ $(jq -c -r .tkg.clusters.workload_build $jsonFile) == true ]] ; then
  tf_init_apply "Building TKG workload cluster(s) - This should take less than 40 minutes - for 2 clusters" tkg/workload_clusters_builds ../../logs/tf_workload_clusters_builds.stdout ../../logs/tf_workload_clusters_builds.errors ../../tkg.json
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
echo "  - Avi url: https://$(jq -c -r .avi.controller.cidr avi.json | cut -d'/' -f1 | cut -d'.' -f1-3).$(jq -c -r .avi.controller.ip avi.json)"
