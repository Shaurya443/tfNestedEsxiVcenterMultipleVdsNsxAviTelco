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
# retrieve current exclusion list members
members=$(curl -k  -X GET -b cookies.txt -H "`grep X-XSRF-TOKEN headers.txt`" -H "Content-Type: application/json" https://$nsx_ip$(jq -c -r .nsx.config.exclusion_list_api_endpoint $jsonFile) | jq -c -r .members)
for member in $(jq -c -r .nsx.config.exclusion_list_groups[] $jsonFile)
do
  members=$(echo $members | jq '. += ["/infra/domains/default/groups/'$(echo $member)'"]')
done
# update new exclusion list members
curl -k -s -X PATCH -b cookies.txt -H "`grep X-XSRF-TOKEN headers.txt`" -H "Content-Type: application/json" -d '{"members": '$(echo $members | jq -c -r .)'}' https://$nsx_ip$(jq -c -r .nsx.config.exclusion_list_api_endpoint $jsonFile)