#!/bin/bash
if [ -f "variables.json" ]; then
  jsonFile="variables.json"
else
  echo "variables.json file not found!!"
  exit 255
fi
rm avi.json
IFS=$'\n'
avi_json=""
avi_networks="[]"
# copy cidr from nsx.config.segments_overlay to avi.config.cloud.networks
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