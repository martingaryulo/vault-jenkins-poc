#Vault Server Stand alone deployment
oc new-project hashicorp
oc create sa vault-auth
oc adm policy add-cluster-role-to-user system:auth-delegator -z vault-auth
oc apply -f ./vault/standalone/install/
read -r -s -p $'Once deployed press enter to continue with Vault Inizalitation...'

#Vault Server UNSEAL (Inizilitation)
POD=$(oc get pods -l app.kubernetes.io/name=vault --no-headers -o custom-columns=NAME:.metadata.name)
echo ${POD}
oc exec $POD -- vault operator init --tls-skip-verify -key-shares=1 -key-threshold=1 > data
cat data
read -r -s -p $'Press enter to continue...'
key1="$( cat data | grep 'Key 1' | awk -F ':' '{print $2}' | xargs )"
rtkn="$( cat data | grep 'Initial Root Token' | awk -F ':' '{print $2}' | xargs )"
echo ${key1}
echo ${rtkn}
oc exec $POD -- vault operator unseal --tls-skip-verify $key1