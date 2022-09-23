#!/bin/bash
# Setup Jenkins Project
if [ "$#" -ne 5 ]; then
    echo "Usage:"
    echo "  $0 REPO_PIPELINE CONTEXT_DIR_PIPELINE VAULT_ADDR VAULT_TOKEN OCP_TOKEN"
    #====================
    # To Be Implemented  
    #echo "  Use VAULT_ADDR=0, VAULT_TOKEN=0 and ROLE=0 to deploy Vault Server in OCP_TOKEN"
    #====================
    exit 1
fi

REPO_PIPELINE=$1
CONTEXT_DIR_PIPELINE=$2
VAULT_ADDR=$3
VAULT_TOKEN=$4
OCP_TOKEN=$5

#====================
# To Be Implemented  
# check vault server ready (check $3-5 and vault pod unsealed), check login with VAULT_TOKEN -> if not ready do deploy using stage1_ready.sh
# check if vault-jenkins project exists, if so delete it, else create it
#====================

echo "Setting up Jenkins in project vault-jenkins from Git Repo ${REPO_PIPELINE} Context Dir ${CONTEXT_DIR_PIPELINE}"
# Set up Jenkins with sufficient resources
$OCP_TOKEN
oc new-project vault-jenkins --display-name="from Git Repo ${REPO_PIPELINE} Context Dir ${CONTEXT_DIR_PIPELINE}"

# Create custom agent container image with skopeo.
oc new-build --strategy=docker -D $'FROM registry.access.redhat.com/ubi8/go-toolset:latest as builder\n
ENV SKOPEO_VERSION=v1.0.0\n
RUN git clone -b $SKOPEO_VERSION https://github.com/containers/skopeo.git && cd skopeo/ && make binary-local DISABLE_CGO=1\n
FROM image-registry.openshift-image-registry.svc:5000/openshift/jenkins-agent-maven:v4.0 as final\n
USER root\n
RUN mkdir /etc/containers\n
COPY --from=builder /opt/app-root/src/skopeo/default-policy.json /etc/containers/policy.json\n
COPY --from=builder /opt/app-root/src/skopeo/skopeo /usr/bin\n
USER 1001' --name=maven-skopeo-agent -n vault-jenkins 

# Make sure that Jenkins Agent Build Pod has finished building
while : ; do
  echo "Checking if Jenkins Agent Build Pod has finished building..."
  AVAILABLE_REPLICAS=$(oc get pod maven-skopeo-agent-1-build -n vault-jenkins -o=jsonpath='{.status.phase}')
  if [[ "$AVAILABLE_REPLICAS" == "Succeeded" ]]; then
    echo "...Yes. Jenkins Agent Build Pod has finished."
    break
  fi
  echo "...no. Sleeping 10 seconds."
  sleep 10
done

# Set up ConfigMap with Jenkins Skopeo Agent and JCasC definitions
oc create -f ./manifests/agent-cm.yaml -n vault-jenkins 

#====================
# To Be Implemented
# GitHub Vault Auth + Cubbyhole (engine) Response Wrapping 
#====================

# Setup Vault for ${CONTEXT_DIR_PIPELINE}-pipeline using Vault Http API
# Enable Approle auth method which will be used by Jenkins 
# Create Secret with the credentials to get access to the private docker push repository
chmod +x ${CONTEXT_DIR_PIPELINE}/configuration/setup_vault.sh
APPROLE=$( ${CONTEXT_DIR_PIPELINE}/configuration/setup_vault.sh ${VAULT_ADDR} ${VAULT_TOKEN} )
ROLE_ID=$( echo $APPROLE |  awk -F ' ' '{print $1}' )
SECRET_ID=$( echo $APPROLE | awk -F ' ' '{print $2}' )
VAULT_APP_TOKEN=$( echo $APPROLE | awk -F ' ' '{print $3}' )

#oc create -f ./manifests/casc-jenkins-cm.yaml -n vault-jenkins 
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
                  description: "AppRole Session Token"
                  id: "vault_app_token"
                  scope: GLOBAL
                  token: "${VAULT_APP_TOKEN}"" | oc create -f - -n vault-jenkins

#Deploy Jenkins Ephemeral
oc new-app jenkins-ephemeral --param JENKINS_IMAGE_STREAM_TAG=jenkins:latest -e CASC_JENKINS_CONFIG=/var/jenkins_config/ PLUGINS_FORCE_UPGRADE=true INSTALL_PLUGINS=hashicorp-vault-plugin -n vault-jenkins
oc rollout pause dc jenkins -n vault-jenkins
oc patch dc jenkins --patch='{ "spec": { "strategy": { "type": "Recreate" }}}' -n vault-jenkins
oc set volume dc/jenkins --add --overwrite --name=casc-jenkins --mount-path=/var/jenkins_config/ --type configmap --configmap-name jenkins-configuration-as-code -n vault-jenkins
oc rollout resume dc jenkins -n vault-jenkins

# Make sure that Jenkins is fully up and running before proceeding!
while : ; do
  echo "Checking if Jenkins is Ready..."
  AVAILABLE_REPLICAS=$(oc get dc jenkins -n vault-jenkins -o=jsonpath='{.status.availableReplicas}')
  if [[ "$AVAILABLE_REPLICAS" == "1" ]]; then
    echo "...Yes. Jenkins is ready."
    break
  fi
  echo "...no. Sleeping 10 seconds."
  sleep 10
done

# Create pipeline build config pointing to the ${REPO_PIPELINE} with contextDir `${CONTEXT_DIR_PIPELINE}`
echo "apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  labels:
    app: ${CONTEXT_DIR_PIPELINE}-pipeline
    app.kubernetes.io/component: ${CONTEXT_DIR_PIPELINE}-pipeline
    app.kubernetes.io/instance: ${CONTEXT_DIR_PIPELINE}-pipeline
  name: ${CONTEXT_DIR_PIPELINE}-pipeline
spec:
  runPolicy: Serial
  source:
    contextDir: ${CONTEXT_DIR_PIPELINE}
    git:
      ref: main
      uri: ${REPO_PIPELINE}
    type: Git
  strategy:
    jenkinsPipelineStrategy:
      jenkinsfilePath: Jenkinsfile
      env:
      - name: VAULT_ADDR
        value: ${VAULT_ADDR}
    type: JenkinsPipeline" | oc create -f - -n vault-jenkins
#oc create secret generic vault-token --from-literal=token=${VAULT_APP_TOKEN}
#oc set build-secret --source bc/${CONTEXT_DIR_PIPELINE}-pipeline vault-token

echo    "+==============================================================+"
echo    "|  Next Steps:                                                 |"
echo    "|  (*) Add Hashicorp Vault Plugin in Jenkins AND/OR ...        |"
echo    "|  (*) Configure AppRole Vault Credentials in Jenkins          |"
echo    "|  (*) Press Crtl+C to run another example (TBA)               |"
echo    "+==============================================================+"
echo    "|  ROLE_ID:   ${ROLE_ID}"                                               
echo    "|  SECRET_ID: ${SECRET_ID}"
echo    "+==============================================================+"

read -r -s -p $"Press enter to run ${CONTEXT_DIR_PIPELINE}-pipeline: "
oc start-build ${CONTEXT_DIR_PIPELINE}-pipeline -n vault-jenkins
#oc start-build example03-pipeline -n vault-jenkins