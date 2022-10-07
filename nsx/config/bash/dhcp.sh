#!/bin/bash
#
if [ -f "../../variables.json" ]; then
  jsonFile="../../variables.json"
else
  echo "ERROR: no json file found"
  exit 1
fi
#
nsx_ip=$(jq -r .vcenter.dvs.portgroup.management.nsx_ip $jsonFile)
IFS=$'\n'
rm -f cookies.txt headers.txt
curl -k -c cookies.txt -D headers.txt -X POST -d 'j_username=admin&j_password='$TF_VAR_nsx_password'' https://$nsx_ip/api/session/create
#
for dhcp_server in $(jq -c -r .nsx.config.dhcp_servers[] $jsonFile)
do
  new_json="{\"display_name\": \"$(echo $dhcp_server | jq -r .name)\", \"server_address\": \"$(echo $dhcp_server | jq -r .server_address)\", \"lease_time\": \"$(echo $dhcp_server | jq -r .lease_time)\"}"
  curl -k -s -X PUT -b cookies.txt -H "`grep X-XSRF-TOKEN headers.txt`" -H "Content-Type: application/json" -d $(echo $new_json) https://$nsx_ip$(jq -c -r .nsx.config.dhcp_servers_api_endpoint $jsonFile)/$(echo $dhcp_server | jq -r .name)
done