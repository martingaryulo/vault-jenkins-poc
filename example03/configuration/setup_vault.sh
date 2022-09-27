#!/bin/bash
# Setup AppRole for PoC Jenkins+Vault Example03 escenario

VAULT_ADDR=$1
VAULT_TOKEN=$2

#1.Enable the AppRole auth method by invoking the Vault API.
curl -k -s --header "X-Vault-Token: $VAULT_TOKEN" --request POST --data '{"type": "approle"}' $VAULT_ADDR/v1/sys/auth/approle

#2. Adding Policy able to list a read mongodb and docker push secrets
curl -k -s\
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request PUT \
    --data '{"policy":"# Jenkins to grant permissions:\npath \"secret/mongodb\" {\n  capabilities = [\"read\", \"list\"]\n}\n\npath \"secret/docker/push\" {\n  capabilities = [\"read\", \"list\"]\n}\n"}' \
    $VAULT_ADDR/v1/sys/policies/acl/jenkins-policy

#3. The following command specifies that the tokens issued under the AppRole jenkins-role should be associated with jenkins-policy.
curl -k -s\
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST \
    --data '{"policies": ["jenkins-policy"]}' \
    $VAULT_ADDR/v1/auth/approle/role/jenkins-role

#4. The following command fetches the RoleID of the role named jenkins-role.
ROLE_ID=$(curl -k -s --header "X-Vault-Token:$VAULT_TOKEN" $VAULT_ADDR/v1/auth/approle/role/jenkins-role/role-id | jq -j '.data.role_id')
echo $ROLE_ID

#5. This command creates a new SecretID under the jenkins-role.
SECRET_ID=$(curl -k -s --header "X-Vault-Token: $VAULT_TOKEN" --request POST $VAULT_ADDR/v1/auth/approle/role/jenkins-role/secret-id | jq -j '.data.secret_id')
echo $SECRET_ID

#8. Getting approle session token
VAULT_APP_TOKEN=$(curl -k -s -X POST -d '{"role_id": "'$ROLE_ID'","secret_id": "'$SECRET_ID'"}' $VAULT_ADDR/v1/auth/approle/login | jq -j '.auth.client_token')
echo $VAULT_APP_TOKEN

#7. Adding Environment Variables to mongodb secret in order to show Vault as a parameter store as well
curl -k -s\
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request PUT \
    --data '{  "mongodb_root_password": "rootpassword", "mongodb_password": "password", "mongodb_username": "admin", "mongodb_database": "sampledb", "ip": "mongodb",  "port": "27017", "proppath": "./application.properties" }' \
    $VAULT_ADDR/v1/secret/mongodb

#8. Adding destination private registry secrets to "/secret/docker/push"
curl -k -s\
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --request PUT \
    --data '{  "dockeruser": "semperti", "dockerpass": "semperti1" }' \
    $VAULT_ADDR/v1/secret/docker/push

#BONUS
#vault read auth/approle/role/jenkins-role
#vault write auth/approle/role/jenkins-role secret_id_ttl=10m token_num_uses=2 token_ttl=15m token_max_ttl=20m