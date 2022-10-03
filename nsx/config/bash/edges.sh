#!/bin/bash
#
if [ -f "../../variables.json" ]; then
  jsonFile="../../variables.json"
else
  echo "ERROR: no json file found"
  exit 1
fi
nsx_ip=$(jq -r .vcenter.dvs.portgroup.management.nsx_ip $jsonFile)
vcenter_username=administrator
vcenter_domain=$(jq -r .vcenter.sso.domain_name $jsonFile)
vcenter_fqdn="$(jq -r .vcenter.name $jsonFile).$(jq -r .dns.domain $jsonFile)"
rm -f cookies.txt headers.txt
curl -k -c cookies.txt -D headers.txt -X POST -d 'j_username=admin&j_password='$TF_VAR_nsx_password'' https://$nsx_ip/api/session/create
compute_managers=$(curl -k -s -X GET -b cookies.txt -H "`grep X-XSRF-TOKEN headers.txt`" -H "Content-Type: application/json" https://$nsx_ip/api/v1/fabric/compute-managers)
IFS=$'\n'
for item in $(echo $compute_managers | jq -c -r .results[])
do
  if [[ $(echo $item | jq -r .display_name) == $(jq -r .vcenter.name $jsonFile).$(jq -r .dns.domain $jsonFile) ]] ; then
    vc_id=$(echo $item | jq -r .id)
  fi
done
api_host="$(jq -r .vcenter.name $jsonFile).$(jq -r .dns.domain $jsonFile)"
vcenter_username=administrator
vcenter_domain=$(jq -r .vcenter.sso.domain_name $jsonFile)
vcenter_password=$TF_VAR_vcenter_password
token=$(curl -k -s -X POST -u "$vcenter_username@$vcenter_domain:$vcenter_password" https://$api_host/api/session -H "Content-Type: application/json" | tr -d \")
storage_id=$(curl -k -X GET -H "vmware-api-session-id: $token" -H "Content-Type: application/json" "https://$api_host/api/vcenter/datastore" | jq -r .[0].datastore)
vcenter_networks=$(curl -k -X GET -H "vmware-api-session-id: $token" -H "Content-Type: application/json" "https://$api_host/api/vcenter/network")
data_network_ids=[]
for item in $(echo $vcenter_networks | jq -c -r .[])
do
  if [[ $(echo $item | jq -r .name) == $(jq -r .vcenter.dvs.portgroup.management.name $jsonFile) ]] ; then
    management_network_id=$(echo $item | jq -r .network)
  fi
done
for item in $(echo $vcenter_networks | jq -c -r .[])
do
  if [[ $(echo $item | jq -r .name) == $(jq -r .vcenter.dvs.portgroup.nsx_overlay_edge.name $jsonFile)-pg ]] ; then
    data_network_id=$(echo $item | jq -r .network)
    data_network_ids=$(echo $data_network_ids | jq '. += ["'$data_network_id'"]')
  fi
done
for item in $(echo $vcenter_networks | jq -c -r .[])
do
  if [[ $(echo $item | jq -r .name) == $(jq -r .vcenter.dvs.portgroup.nsx_external.name $jsonFile)-pg ]] ; then
    data_network_id=$(echo $item | jq -r .network)
    data_network_ids=$(echo $data_network_ids | jq '. += ["'$data_network_id'"]')
  fi
done
vcenter_resource_pools=$(curl -k -X GET -H "vmware-api-session-id: $token" -H "Content-Type: application/json" "https://$api_host/api/vcenter/resource-pool")
for item in $(echo $vcenter_resource_pools| jq -c -r .[])
do
  if [[ $(echo $item | jq -r .name) == "Resources" ]] ; then
    compute_id=$(echo $item | jq -r .resource_pool)
  fi
done
for edge_index in $(seq 1 $(jq -r '.vcenter.dvs.portgroup.management.nsx_edge | length' $jsonFile ))
do
  edge_count=$((edge_index-1)) # starts at 0
  name=$(jq -r .nsx.config.edge_node.basename $jsonFile)$edge_index
  fqdn=$(jq -r .nsx.config.edge_node.basename $jsonFile)$edge_index.$(jq -r .dns.domain $jsonFile)
  cpu=$(jq -r .nsx.config.edge_node.cpu $jsonFile)
  memory=$(jq -r .nsx.config.edge_node.memory $jsonFile)
  disk=$(jq -r .nsx.config.edge_node.disk $jsonFile)
  gateway=$(jq -r .vcenter.dvs.portgroup.management.gateway $jsonFile)
  prefix_length=$(jq -r .vcenter.dvs.portgroup.management.prefix $jsonFile)
  ip=$(jq -r .vcenter.dvs.portgroup.management.nsx_edge[$edge_count] $jsonFile)
  host_switch_count=0
  new_json="{\"host_switch_spec\": {\"host_switches\": [], \"resource_type\": \"StandardHostSwitchSpec\"}}"
  for host_switch in $(jq -c -r .nsx.config.edge_node.host_switch_spec.host_switches[] $jsonFile)
  do
    new_json=$(echo $new_json | jq -r -c '.host_switch_spec.host_switches |= .+ ['$host_switch']')
    new_json=$(echo $new_json | jq '.host_switch_spec.host_switches['$host_switch_count'] += {"host_switch_profile_ids": []}')
    new_json=$(echo $new_json | jq '.host_switch_spec.host_switches['$host_switch_count'] += {"transport_zone_endpoints": []}')
    for host_switch_profile_name in $(echo $host_switch | jq -r .host_switch_profile_names[])
    do
      host_switch_profiles=$(curl -k -s -X GET -b cookies.txt -H "`grep X-XSRF-TOKEN headers.txt`" -H "Content-Type: application/json" https://$nsx_ip/api/v1/host-switch-profiles)
      IFS=$'\n'
      for item in $(echo $host_switch_profiles | jq -c -r .results[])
      do
        if [[ $(echo $item | jq -r .display_name) == $host_switch_profile_name ]] ; then
          host_switch_profile_id=$(echo $item | jq -r .id)
        fi
      done
      new_json=$(echo $new_json | jq '.host_switch_spec.host_switches['$host_switch_count'].host_switch_profile_ids += [{"key": "UplinkHostSwitchProfile", "value": "'$host_switch_profile_id'"}]')
    done
    for tz_name in $(echo $host_switch | jq -r .transport_zone_names[])
    do
      transport_zones=$(curl -k -s -X GET -b cookies.txt -H "`grep X-XSRF-TOKEN headers.txt`" -H "Content-Type: application/json" https://$nsx_ip/api/v1/transport-zones)
      IFS=$'\n'
      for item in $(echo $transport_zones | jq -c -r .results[])
      do
        if [[ $(echo $item | jq -r .display_name) == $tz_name ]] ; then
          transport_zone_id=$(echo $item | jq -r .id)
        fi
      done
      new_json=$(echo $new_json | jq '.host_switch_spec.host_switches['$host_switch_count'].transport_zone_endpoints += [{"transport_zone_id": "'$transport_zone_id'"}]')
    done
    if [[ $(echo $new_json | jq '.host_switch_spec.host_switches['$host_switch_count']' | grep ip_pool_name) ]] ; then
      ip_pools=$(curl -k -s -X GET -b cookies.txt -H "`grep X-XSRF-TOKEN headers.txt`" -H "Content-Type: application/json" https://$nsx_ip/policy/api/v1/infra/ip-pools)
      IFS=$'\n'
      for item in $(echo $ip_pools | jq -c -r .results[])
      do
        if [[ $(echo $item | jq -r .display_name) == $(echo $new_json | jq -r '.host_switch_spec.host_switches['$host_switch_count'].ip_pool_name') ]] ; then
          ip_pool_id=$(echo $item | jq -r .realization_id)
        fi
      done
      new_json=$(echo $new_json | jq '.host_switch_spec.host_switches['$host_switch_count'] += {"ip_assignment_spec": {"ip_pool_id": "'$ip_pool_id'", "resource_type": "StaticIpPoolSpec"}}')
      new_json=$(echo $new_json | jq 'del (.host_switch_spec.host_switches['$host_switch_count'].ip_pool_name)' )
    fi
    new_json=$(echo $new_json | jq 'del (.host_switch_spec.host_switches['$host_switch_count'].host_switch_profile_names)' )
    new_json=$(echo $new_json | jq 'del (.host_switch_spec.host_switches['$host_switch_count'].transport_zone_names)' )
    host_switch_count=$((host_switch_count+1))
  done
  new_json=$(echo $new_json | jq '. +=  {"maintenance_mode": "DISABLED"}')
  new_json=$(echo $new_json | jq '. +=  {"display_name":"'$name'"}')
  new_json=$(echo $new_json | jq '. +=  {"node_deployment_info": {"resource_type":"EdgeNode", "deployment_type": "VIRTUAL_MACHINE", "deployment_config": { "vm_deployment_config": {"vc_id": "'$vc_id'", "compute_id": "'$compute_id'", "storage_id": "'$storage_id'", "management_network_id": "'$management_network_id'", "management_port_subnets": [{"ip_addresses": ["'$ip'"], "prefix_length": '$prefix_length'}], "default_gateway_addresses": ["'$gateway'"], "data_network_ids": '$(echo $data_network_ids | jq -r -c .)', "reservation_info": { "memory_reservation" : {"reservation_percentage": 100 }, "cpu_reservation": { "reservation_in_shares": "HIGH_PRIORITY", "reservation_in_mhz": 0 }}, "resource_allocation": {"cpu_count": '$cpu', "memory_allocation_in_mb": '$memory' }, "placement_type": "VsphereDeploymentConfig"}, "form_factor": "MEDIUM", "node_user_settings": {"cli_username": "admin", "root_password": "'$TF_VAR_nsx_password'", "cli_password": "'$TF_VAR_nsx_password'"}}, "node_settings": {"hostname": "'$fqdn'", "enable_ssh": true, "allow_ssh_root_login": true }}}')
  new_edge_node=$(curl -k -s -X POST -b cookies.txt -H "`grep X-XSRF-TOKEN headers.txt`" -H "Content-Type: application/json" -d $(echo $new_json | jq -r -c) https://$nsx_ip/api/v1/transport-nodes)
  new_edge_node_id=$(echo $new_edge_node | jq -r .id)
  retry=40
  pause=60
  attempt=0
  while true ; do
    echo "waiting for transport new edge node state is success"
    compute_manager_runtime=$(curl -k -s -X GET -b cookies.txt -H "`grep X-XSRF-TOKEN headers.txt`" -H "Content-Type: application/json" https://$nsx_ip/policy/api/v1/infra/sites/default/enforcement-points/default/host-transport-nodes/state)
    for item in $(echo $compute_manager_runtime | jq -c -r .results[])
    do
      if [[ $(echo $item | jq -r .transport_node_id) == $new_edge_node_id ]] ; then
        if [[ $(echo $item | jq -r .state) == "success" ]] ; then
          echo "new edge node state is success"
          break 2
        fi
      fi
    done
    if [ $attempt -eq $retry ]; then
      echo "FAILED to get new edge node state success after $retry retries"
      exit 255
    fi
    sleep $pause
    ((attempt++))
  done
done