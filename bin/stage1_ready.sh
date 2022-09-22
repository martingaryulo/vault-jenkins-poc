#!/bin/bash
# Setup OCP-Vault-POC Stage #1 with example 02 running and ready
if [ "$#" -ne 3 ]; then
    echo "Usage:"
    echo "  $0 REPO CONTEXT_DIR OCP_LOGIN_TOKEN"
    echo "  Example: $0 https://github.com/ferluko/ocp-vault-poc.git appointment {OCP_LOGIN_TOKEN}"
    echo "  Example of {OCP_LOGIN_TOKEN} = oc login --token=GpyksdEsyDZ58MM47lcE1R6YzzMOwMJZxezTzVZehC8 --server=https://api.shared-na4.na4.openshift.opentlc.com:6443"
    exit 1
fi

REPO=$1
CONTEXT_DIR=$2
OCP_LOGIN_TOKEN=$3

echo "Setting up OCP-Vault-POC Stage #1 with example 02 up and running"
echo "Cloning Repository: ${REPO}"
git clone ${REPO} ocp-vault-poc && cd $_
echo "Loggin in OCP..."
$OCP_LOGIN_TOKEN
oc new-project vault-app
oc create -f mongodb/010-deploy-secret-mongodb-service.yaml 
oc new-build $REPO --context-dir $CONTEXT_DIR --name vault-app-api
oc create -f example00/020-deployConfig-api.yaml
oc expose svc vault-app-api
#while : ; do
#  echo "Checking if Vault-app is Ready..."
#  AVAILABLE_REPLICAS=$(oc get dc vault-app-api -n vault-app -o=jsonpath='{.status.availableReplicas}')
#  if [[ "$AVAILABLE_REPLICAS" == "1" ]]; then
#    echo "...Yes. Vault-app is ready."
#    break
#  fi
#  echo "...no. Sleeping 10 seconds."
#  sleep 10
#done
read -r -s -p $'Press enter to POST sample appointments to Vault-App-Api...'
curl -X GET "http://`oc get route | grep -m1 vault-app-api | awk '{print $2}'`/appointment" -H "accept: application/json" >/dev/null
curl -X POST "http://`oc get route | grep -m1 vault-app-api | awk '{print $2}'`/appointment" -H "accept: application/json" -d "" >/dev/null
curl -X POST "http://`oc get route | grep -m1 vault-app-api | awk '{print $2}'`/appointment" -H "accept: application/json" -d "" >/dev/null
curl -X POST "http://`oc get route | grep -m1 vault-app-api | awk '{print $2}'`/appointment" -H "accept: application/json" -d "" >/dev/null
curl -X GET "http://`oc get route | grep -m1 vault-app-api | awk '{print $2}'`/appointment" -H "accept: application/json" >/dev/null

read -r -s -p $'Press enter to Install Vault Server...'
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

#Testing Vault CLI
export VAULT_SKIP_VERIFY=true
export VAULT_TOKEN=$rtkn
export VAULT_ADDR=https://`oc get route -n hashicorp| grep -m1 vault | awk '{print $2}'`
vault login -tls-skip-verify $rtkn
rm data
read -r -s -p $'Press enter to configure k8s Auth...'

#Setup K8s Auth
secret=`oc describe sa vault-auth | grep 'Tokens:' | awk '{print $2}'`
token=`oc describe secret $secret | grep 'token:' | awk '{print $2}'`
oc exec $POD -- cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt > ca.crt
vault auth enable -tls-skip-verify kubernetes
vault write -tls-skip-verify auth/kubernetes/config token_reviewer_jwt=$token kubernetes_host=https://kubernetes.default.svc:443 kubernetes_ca_cert=@ca.crt
vault read -tls-skip-verify auth/kubernetes/config
rm ca.crt

read -r -s -p $'Press enter to Clean Escenario 0...'
oc project vault-app
oc delete all -l app=vault-app-api 

#Escenario 1
vault secrets enable -tls-skip-verify -version=1 -path=secret kv
vault policy write -tls-skip-verify policy-example ./policy/policy-example.hcl
vault write -tls-skip-verify auth/kubernetes/role/demo bound_service_account_names=default bound_service_account_namespaces='*' policies=policy-example ttl=24h
vault read -tls-skip-verify auth/kubernetes/role/demo
vault write -tls-skip-verify secret/mongodb user="$(oc get secret/mongodb -o jsonpath="{.data.MONGODB_USERNAME}" | base64 -d )" password="$(oc get secret/mongodb -o jsonpath="{.data.MONGODB_PASSWORD}" | base64 -d )"
vault read -tls-skip-verify secret/mongodb

secret=`oc describe sa default | grep 'Tokens:' | awk '{print $2}'`
token=`oc describe secret $secret | grep 'token:' | awk '{print $2}'`
vault write -tls-skip-verify auth/kubernetes/login role=demo jwt=$token

sed -i -e 's|VAULT_ADDR|'$VAULT_ADDR'|g' ./example01/020-deployConfig-api.yaml 
oc apply -f example01/020-deployConfig-api.yaml
oc expose svc vault-app-api

sleep 15
pod=`oc get pods -L app=vault-app-api --field-selector status.phase=Running --no-headers -o custom-columns=NAME:.metadata.name | grep vault`
oc logs $pod
oc logs $pod -c vault-init
read -r -s -p $'Press enter to continue Cleaning up Escenario 1...'

oc delete dc vault-app-api
oc delete all -l app=vault-app-api
oc get all
read -r -s -p $'Press enter to continue with Escenario 2 installing Vault Agent Injector...'

#Escenario 2
oc project hashicorp
oc apply -f vault/injector/install/

read -r -s -p $'Press enter to configure Vault for Escenario 2...'
oc project vault-app
vault secrets enable -tls-skip-verify database

vault write -tls-skip-verify database/config/vault-app-mongodb \
   plugin_name=mongodb-database-plugin \
   allowed_roles="vault-app-mongodb-role" \
   connection_url="mongodb://{{username}}:{{password}}@mongodb.vault-app.svc.cluster.local:27017/admin" \
   username="admin" \
   password="$(oc get secret/mongodb -o jsonpath="{.data.MONGODB_ROOT_PASSWORD}" | base64 -d )"
vault read -tls-skip-verify database/config/vault-app-mongodb

vault write -tls-skip-verify database/roles/vault-app-mongodb-role \
   db_name=vault-app-mongodb \
   creation_statements='{ "db": "sampledb", "roles": [{"role": "readWrite", "db": "sampledb"}] }' \
   default_ttl="1h" \
   max_ttl="24h" \
   revocation_statements='{ "db": "sampledb" }'
vault read -tls-skip-verify database/roles/vault-app-mongodb-role

vault policy write -tls-skip-verify vault-app-policy-dynamic policy/vault-app-dynamic-secrets-policy.hcl

vault write -tls-skip-verify auth/kubernetes/role/vault-app-mongodb-role bound_service_account_names=default bound_service_account_namespaces='*' policies=vault-app-policy-dynamic ttl=24h
vault read -tls-skip-verify auth/kubernetes/role/vault-app-mongodb-role

read -r -s -p $'Press enter to Label webhook=enebled then re deploy with Vault Agent Injector...'
oc project vault-app
oc label namespace vault-app vault.hashicorp.com/agent-webhook=enabled
oc create -f example02/020-deployConfig-Vault-app-api-Inject.yaml
oc expose svc vault-app-api