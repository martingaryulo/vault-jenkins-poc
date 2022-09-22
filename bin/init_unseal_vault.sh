#!/bin/bash

oc project hashicorp
POD=$(oc get pods -l app.kubernetes.io/name=vault --no-headers -o custom-columns=NAME:.metadata.name)
echo ${POD}
#oc rsh $POD
oc exec $POD -- vault operator init --tls-skip-verify -key-shares=1 -key-threshold=1 > data
cat data
read -r -s -p $'Press enter to continue...'
key1="$( cat data | grep 'Key 1' | awk -F ':' '{print $2}' | xargs )"
rtkn="$( cat data | grep 'Initial Root Token' | awk -F ':' '{print $2}' | xargs )"
echo ${key1}
echo ${rtkn}
oc exec $pod -- vault operator unseal --tls-skip-verify $key1
export VAULT_TOKEN=$rtkn
export VAULT_ADDR=https://`oc get route | grep -m1 vault | awk '{print $2}'`
vault login -tls-skip-verify $rtkn
rm data
read -r -s -p $'Press enter to continue...'