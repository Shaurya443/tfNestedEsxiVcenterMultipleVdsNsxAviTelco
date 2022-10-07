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
curl -k -s -X GET -b cookies.txt -H "`grep X-XSRF-TOKEN headers.txt`" -H "Content-Type: application/json" https://$nsx_ip/policy/api/v1/global-infra/5f0b1c64-16a2-4be3-897b-ecfe3eb92f31/segments

/infra/tier-1s/5f0b1c64-16a2-4be3-897b-ecfe3eb92f31/segments/03009579-a6eb-47b4-98bc-69f4d39e74e4