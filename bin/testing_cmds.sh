#!/bin/bash

CONTEXT_DIR_PIPELINE=$1
VAULT_ADDR=$2
VAULT_APP_TOKEN=$3

#vault login $VAULT_ADDR $VAULT_TOKEN 

#chmod +x ${CONTEXT_DIR_PIPELINE}/configuration/setup_vault.sh
#APPROLE=$( ${CONTEXT_DIR_PIPELINE}/configuration/setup_vault.sh ${VAULT_ADDR} ${VAULT_TOKEN} )
#ROLE_ID=$( echo $APPROLE |  awk -F ' ' '{print $1}' )
#SECRET_ID=$( echo $APPROLE | awk -F ' ' '{print $2}' )
#VAULT_APP_TOKEN=$( echo $APPROLE | awk -F ' ' '{print $3}' )

echo "apiVersion: v1
kind: ConfigMap
metadata:
  name: jenkins-configuration-as-code
data:
  configuration-as-code.yaml: |
    unclassified:
      hashicorpVault:
        configuration:
          vaultCredentialId: "vault_app_token"
          vaultUrl: "${VAULT_ADDR}"

    credentials:
      system:
        domainCredentials:
          - credentials:
              - vaultTokenCredential:
                  description: "root Token"
                  id: "vault_app_token"
                  scope: GLOBAL
                  token: "${VAULT_APP_TOKEN}"" | oc create -f - -n vault-jenkins