#!/bin/bash
#
if [ -f "../../variables.json" ]; then
  jsonFile="../../variables.json"
else
  echo "ERROR: no json file found"
  exit 1
fi
# create NSX API session
nsx_ip=$(jq -r .vcenter.dvs.portgroup.management.nsx_ip $jsonFile)
IFS=$'\n'
rm -f cookies.txt headers.txt
curl -k -c cookies.txt -D headers.txt -X POST -d 'j_username=admin&j_password='$TF_VAR_nsx_password'' https://$nsx_ip/api/session/create
# create NSX group
for group in $(jq -c -r .nsx.config.groups[] $jsonFile)
do
  curl -k -s -X PUT -b cookies.txt -H "`grep X-XSRF-TOKEN headers.txt`" -H "Content-Type: application/json" -d $(echo $group) https://$nsx_ip$(jq -c -r .nsx.config.groups_api_endpoint $jsonFile)/$(echo $group | jq -r .display_name)
done
