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
if [[ $(jq -c -r .avi.controller.create $jsonFile) == true ]] && [[ $(jq -c -r .avi.config.create $jsonFile) == true ]] ; then
  tf_init_apply "Build of the config of Avi - This should take less than 20 minutes" avi/config ../../logs/tf_avi_config.stdout ../../logs/tf_avi_config.errors ../../$jsonFile
fi
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
