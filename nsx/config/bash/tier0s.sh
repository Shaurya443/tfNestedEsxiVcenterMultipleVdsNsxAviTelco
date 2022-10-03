#!/bin/bash
#
if [ -f "../../variables.json" ]; then
  jsonFile="../../variables.json"
else
  echo "ERROR: no json file found"
  exit 1
fi
IFS=$'\n'
nsx_ip=$(jq -r .vcenter.dvs.portgroup.management.nsx_ip $jsonFile)
rm -f cookies.txt headers.txt
curl -k -c cookies.txt -D headers.txt -X POST -d 'j_username=admin&j_password='$TF_VAR_nsx_password'' https://$nsx_ip/api/session/create
#
# check the json syntax for tier0s (.nsx.config.tier0s)
#
if [[ $(jq 'has("nsx")' $jsonFile) && $(jq '.nsx | has("config")' $jsonFile) && $(jq '.nsx.config | has("tier0s")' $jsonFile) == "false" ]] ; then
  echo "no json valid entry for nsx.config.tier0s"
  exit
fi
#
# tier 0 creation
#
new_json={}
for tier0 in $(jq -c -r .nsx.config.tier0s[] $jsonFile)
do
  new_json=$(echo $tier0 | jq -c -r '. | del (.edge_cluster_name)')
  new_json=$(echo $new_json | jq -c -r '. | del (.interfaces)')
  new_json=$(echo $new_json | jq -c -r '. | del (.static_routes)')
  new_json=$(echo $new_json | jq -c -r '. | del (.ha_vips)')
  echo "creating the tier0 called $(echo $tier0 | jq -r -c .display_name)"
  curl -k -s -X PUT -b cookies.txt -H "`grep X-XSRF-TOKEN headers.txt`" -H "Content-Type: application/json" -d $(echo $new_json) https://$nsx_ip/policy/api/v1/infra/tier-0s/$(echo $tier0 | jq -r -c .display_name)
done
#
# tier 0 edge cluster association
#
new_json={}
for tier0 in $(jq -c -r .nsx.config.tier0s[] $jsonFile)
do
  if [[ $(echo $tier0 | jq 'has("edge_cluster_name")') == "true" ]] ; then
    for cluster in $(curl -k -s -X GET -b cookies.txt -H "`grep X-XSRF-TOKEN headers.txt`" -H "Content-Type: application/json" https://$nsx_ip/api/v1/edge-clusters | jq -c -r .results[])
    do
      if [[ $(echo $cluster | jq -r .display_name) == $(echo $tier0 | jq -r -c .edge_cluster_name) ]] ; then
          edge_cluster_id=$(echo $cluster | jq -r .id)
      fi
    done
    new_json="{\"edge_cluster_path\": \"/infra/sites/default/enforcement-points/default/edge-clusters/$edge_cluster_id\"}"
    echo "associate the tier0 called $(echo $tier0 | jq -r -c .display_name) with edge cluster name $(echo $tier0 | jq -r -c .edge_cluster_name)"
    curl -k -s -X PUT -b cookies.txt -H "`grep X-XSRF-TOKEN headers.txt`" -H "Content-Type: application/json" -d $(echo $new_json) https://$nsx_ip/policy/api/v1/infra/tier-0s/$(echo $tier0 | jq -r -c .display_name)/locale-services/default
  fi
done
#
# tier 0 iface config
#
ip_index=0
for tier0 in $(jq -c -r .nsx.config.tier0s[] $jsonFile)
do
  if [[ $(echo $tier0 | jq 'has("interfaces")') == "true" ]] ; then
    for interface in $(echo $tier0 | jq -c -r .interfaces[])
    do
      new_json="{\"subnets\" : [ {\"ip_addresses\": [\"$(jq -c -r '.vcenter.dvs.portgroup.nsx_external.tier0_ips['$ip_index']' $jsonFile)\"], \"prefix_len\" : $(jq -c -r '.vcenter.dvs.portgroup.nsx_external.prefix' $jsonFile)}]}"
      ip_index=$((ip_index+1))
      new_json=$(echo $new_json | jq .)
      new_json=$(echo $new_json | jq '. += {"display_name": "'$(echo $interface | jq -r .display_name)'"}')
      for segment in $(curl -k -s -X GET -b cookies.txt -H "`grep X-XSRF-TOKEN headers.txt`" -H "Content-Type: application/json" https://$nsx_ip/policy/api/v1/infra/segments | jq -c -r .results[])
      do
        if [[ $(echo $segment | jq -r .display_name) == $(echo $interface | jq -r -c .segment_name) ]] ; then
          segment_path=$(echo $segment | jq -r .path)
        fi
      done
      new_json=$(echo $new_json | jq '. += {"segment_path": "'$segment_path'"}')
      for cluster in $(curl -k -s -X GET -b cookies.txt -H "`grep X-XSRF-TOKEN headers.txt`" -H "Content-Type: application/json" https://$nsx_ip/api/v1/edge-clusters | jq -c -r .results[])
      do
        if [[ $(echo $cluster | jq -r .display_name) == $(echo $tier0 | jq -r -c .edge_cluster_name) ]] ; then
          edge_cluster_id=$(echo $cluster | jq -r .id)
          for edge_node in $(echo $cluster | jq -r -c .members[])
          do
            if [[ $(echo $edge_node | jq -r .display_name) == $(echo $interface | jq -r -c .edge_name) ]] ; then
              edge_node_id=$(echo $edge_node | jq -r .member_index)
            fi
          done
        fi
      done
      new_json=$(echo $new_json | jq '. += {"edge_path": "/infra/sites/default/enforcement-points/default/edge-clusters/'$(echo $edge_cluster_id)'/edge-nodes/'$(echo $edge_node_id)'"}')
      echo "adding interface to the tier0 called $(echo $tier0 | jq -r -c .display_name)"
      curl -k -s -X PATCH -b cookies.txt -H "`grep X-XSRF-TOKEN headers.txt`" -H "Content-Type: application/json" -d $(echo $new_json) https://$nsx_ip/policy/api/v1/infra/tier-0s/$(echo $tier0 | jq -r -c .display_name)/locale-services/default/interfaces/$(echo $interface | jq -r -c .display_name)
    done
  fi
done
#
# tier 0 static routes
#
for tier0 in $(jq -c -r .nsx.config.tier0s[] $jsonFile)
do
  if [[ $(echo $tier0 | jq 'has("static_routes")') == "true" ]] ; then
    for route in $(echo $tier0 | jq -c -r .static_routes[])
    do
      echo "Adding route: $route to the tier0 called $(echo $tier0 | jq -r -c .display_name)"
      curl -k -s -X PATCH -b cookies.txt -H "`grep X-XSRF-TOKEN headers.txt`" -H "Content-Type: application/json" -d $(echo $route) https://$nsx_ip/policy/api/v1/infra/tier-0s/$(echo $tier0 | jq -r -c .display_name)/static-routes/$(echo $route | jq -r -c .display_name)
    done
  fi
done
#
# tier 0 ha-vip config
#
ip_index=0
new_json="{\"display_name\": \"default\", \"ha_vip_configs\": []}"
for tier0 in $(jq -c -r .nsx.config.tier0s[] $jsonFile)
do
  if [[ $(echo $tier0 | jq 'has("ha_vips")') == "true" ]] ; then
    for cluster in $(curl -k -s -X GET -b cookies.txt -H "`grep X-XSRF-TOKEN headers.txt`" -H "Content-Type: application/json" https://$nsx_ip/api/v1/edge-clusters | jq -c -r .results[])
    do
      if [[ $(echo $cluster | jq -r .display_name) == $(echo $tier0 | jq -r -c .edge_cluster_name) ]] ; then
          edge_cluster_id=$(echo $cluster | jq -r .id)
      fi
    done
    new_json=$(echo $new_json | jq '. += {"edge_cluster_path": "/infra/sites/default/enforcement-points/default/edge-clusters/'$edge_cluster_id'"}')
    for vip in $(echo $tier0 | jq -c -r .ha_vips[])
    do
      interfaces=[]
      for interface in $(echo $vip | jq -c -r .interfaces[])
      do
        interfaces=$(echo $interfaces | jq -c -r '. += ["/infra/tier-0s/'$(echo $tier0 | jq -r -c .display_name)'/locale-services/default/interfaces/'$interface'"]')
      done
      new_json=$(echo $new_json | jq -c -r '.ha_vip_configs += [{"enabled": true, "vip_subnets": [{"ip_addresses": [ "'$(jq -c -r '.vcenter.dvs.portgroup.nsx_external.tier0_vips['$ip_index']' $jsonFile)'" ], "prefix_len": '$(jq -c -r '.vcenter.dvs.portgroup.nsx_external.prefix' $jsonFile)'}], "external_interface_paths": '$interfaces'}]')
      ip_index=$((ip_index+1))
    done
    echo "adding HA to the tier0 called $(echo $tier0 | jq -r -c .display_name)"
    curl -k -s -X PATCH -b cookies.txt -H "`grep X-XSRF-TOKEN headers.txt`" -H "Content-Type: application/json" -d $(echo $new_json) https://$nsx_ip/policy/api/v1/infra/tier-0s/$(echo $tier0 | jq -r -c .display_name)/locale-services/default
  fi
done