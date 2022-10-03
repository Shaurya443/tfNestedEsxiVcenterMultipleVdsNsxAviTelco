#!/bin/bash
#
if [ -f "../../variables.json" ]; then
  jsonFile="../../variables.json"
else
  echo "ERROR: no json file found"
  exit 1
fi
nsx_ip=$(jq -r .vcenter.dvs.portgroup.management.nsx_ip $jsonFile)
rm -f cookies.txt headers.txt
curl -k -c cookies.txt -D headers.txt -X POST -d 'j_username=admin&j_password='$TF_VAR_nsx_password'' https://$nsx_ip/api/session/create
IFS=$'\n'
#
# check the json syntax for tier0s (.nsx.config.edge_clusters)
#
if [[ $(jq 'has("nsx")' $jsonFile) && $(jq '.nsx | has("config")' $jsonFile) && $(jq '.nsx.config | has("edge_clusters")' $jsonFile) == "false" ]] ; then
  echo "no json valid entry for nsx.config.edge_clusters"
  exit
fi
#
# edge cluster creation
#
new_json=[]
edge_cluster_count=0
for edge_cluster in $(jq -c -r .nsx.config.edge_clusters[] $jsonFile)
do
  new_json=$(echo $new_json | jq -r -c '. |= .+ ['$edge_cluster']')
  new_json=$(echo $new_json | jq '.['$edge_cluster_count'] += {"members": []}')
  for name_edge_cluster in $(echo $edge_cluster | jq -r .members_name[])
  do
    edge_node_ids=$(curl -k -s -X GET -b cookies.txt -H "`grep X-XSRF-TOKEN headers.txt`" -H "Content-Type: application/json" https://$nsx_ip/api/v1/transport-nodes)
    IFS=$'\n'
    for item in $(echo $edge_node_ids | jq -c -r .results[])
    do
      if [[ $(echo $item | jq -r .display_name) == $name_edge_cluster ]] ; then
        edge_node_id=$(echo $item | jq -r .id)
      fi
    done
    new_json=$(echo $new_json | jq '.['$edge_cluster_count'].members += [{"transport_node_id": "'$edge_node_id'", "display_name": "'$name_edge_cluster'"}]')
  done
  new_json=$(echo $new_json | jq 'del (.['$edge_cluster_count'].members_name)' )
  edge_cluster_count=$((edge_cluster_count+1))
done
for edge_cluster in $(echo $new_json | jq .[] -c -r)
do
  echo "edge cluster creation"
  curl -k -s -X POST -b cookies.txt -H "`grep X-XSRF-TOKEN headers.txt`" -H "Content-Type: application/json" -d $(echo $edge_cluster) https://$nsx_ip/api/v1/edge-clusters
done
