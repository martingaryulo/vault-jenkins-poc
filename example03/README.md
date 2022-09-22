# ESCENARIO 03 - Recrear el escenario original [vault-app-api](https://github.com/ferluko/ocp-vault-poc)
Prueba de Concepto para la integración de Hashicorp Vault en pipelines CI/CD de Jenkins con compilación y despliegue en Openshift de una aplicación API, la misma utilizada en el [OCP-Vault-PoC Stage #1](https://github.com/ferluko/ocp-vault-poc).

## Descripción del escenario
Representación del escenario original de la PoC anterior pero con la utilización de pipelines CI/CD. Es decir, la construcción y despliegue de la aplicación `vault-app-api`, una aplicación en *Node.js* que trata de una API HTTP sencilla para el registro a citas y persistirlas en una base de datos *MondoDB*. 

En un primer Stage del pipeline, las credenciales para la inicialización de la base de datos *MongoDB* son obtenidas con el plugin [Hashicorp Vault para Jenkins](https://plugins.jenkins.io/hashicorp-vault-plugin) e introducidas osfuscadas en base64 al despliegue de mongodb en Openshift como secretos nativos de Kubernetes. Para este despliegue se utilizará el plugin llamado [OpenShift Jenkins Pipeline (DSL) Plugin](https://github.com/openshift/jenkins-client-plugin#openshift-jenkins-pipeline-dsl-plugin). Con la utilización de este plugin podemos armar pipelines más sencillos y con una sintaxis más amigable sin utilización de clientes adicionales.

Luego se construye y despliega la aplicación [vault-app-api](https://github.com/ferluko/ocp-vault-poc/tree/master/appointment#appointment) en Openshift con los secretos obtenidos desde Vault e inyectados al código de la aplicación de forma tradicional, es decir vía de variables de entorno.

Por último, utilizaremos el Agente de Skopeo para copiar la imágen de la aplicación construida a un repositorio privado externo, en nuestro caso Dockerhub. Las credenciales del repositorio privado también serán obtenidas de Vault.

## Objetivo general del escenario
Cubrir escenarios comunes que nos podemos encontrar en un pipeline de Jenkins para la construcción y despliegue de aplicaciones pero adaptando Vault como un almacén de secretos con mínimas modificaciones a los *Jenkinsfile* pre existentes. 

## Objetivos particulares del escenario
* Comprender y validar el alcance de API Http de Vault
* Entendimiento de AppRole Auth Method, KV Engine, Token de Sesión
* Consumo y utilización de secretos de Vault en un pipeline Jenkins estándar
* Entendimiento y configuración de plugin de Vault para Jenkins
* Utilización de Plugins de Jenkins: Openshift DLS, Openshift Sync, Kubernetes y Credentials
* Entendimiento y configuración Jenkins Configuration as a Code


## Configuración de Vault para el Escenario 3 (example03)
El método de autenticación [AppRole](https://www.vaultproject.io/docs/auth/approle.html) será el utilizado por el Jenkins Master para conectarse a Vault con el plugin y obtener los secretos. Para ello debemos habilitar previamente este método en el servidor de Vault, crear las políticas y roles que asociadas a Jenkins, y finalmente obtener el *Role_ID*, *Secret_ID* y el token de sesión.

Luego, al pipeline de Jenkins solo se le estará pasando el token de sesión (*VAULT_APP_TOKEN*), necesario para la obtención de secretos, de esta forma podemos controlar el TTL y la cantidad de veces que se podrá usar este token, entre otras cosas.

**[example03/configuration/setup_vault.sh](https://gitlab.semperti.com/fernando.gonzalez/jenkins-vault-poc/blob/master/example03/configuration/setup_vault.sh)**
Script de configuración de Vault Server para *example03* vía HTTP.

```
export CONTEXT_DIR_PIPELINE="example03"
export VAULT_ADDR="<URL del Vault server>"
export VAULT_TOKEN="<token con privilegios de acceso a Vault>"
chmod +x example03/configuration/setup_vault.sh
APPROLE=$( example03/configuration/setup_vault.sh ${VAULT_ADDR} ${VAULT_TOKEN} )
echo -n "El Role_ID es: " && echo $APPROLE |  awk -F ' ' '{print $1}'
echo -n "El Secret_ID es: " && echo $APPROLE | awk -F ' ' '{print $2}'
VAULT_APP_TOKEN=$( echo $APPROLE | awk -F ' ' '{print $3}' )
```
A continuación creamos el ConfigMap de Jenkins propio para este escenario. Básicamente le estaremos montando un volumen con el archivo de instrucciones para que el plugin Configuration as a Code cree la credencial con el token de sessión.

```
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
```

Por último previo al despliegue de Jenkins, definimos un Buildconfig en Openshift con la estrategia *Pipeline* apuntando al repositorio y el contexto donde se encuentra nuestro [Jenkinsfile](https://gitlab.semperti.com/fernando.gonzalez/jenkins-vault-poc/blob/master/example03/Jenkinsfile) y los archivos de configuración/manifiestos al ser utilizados por el propio pipeline.

```
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
      ref: master
      uri: ${REPO_PIPELINE}
    type: Git
  strategy:
    jenkinsPipelineStrategy:
      jenkinsfilePath: Jenkinsfile
      env:
      - name: VAULT_ADDR
        value: ${VAULT_ADDR}
    type: JenkinsPipeline" | oc create -f - -n vault-jenkins
```

Una vez terminado la preparación del escenario volvemos al [README.md master](https://gitlab.semperti.com/fernando.gonzalez/jenkins-vault-poc/#configuraci%C3%B3n-y-despliegue-de-jenkins-para-todos-los-escenarios) para la ejecución del pipeline observando su progreso y logs en la consola de GUI de Openshift.

## Análisis del [```Jenkinsfile```](https://gitlab.semperti.com/fernando.gonzalez/jenkins-vault-poc/blob/master/example03/Jenkinsfile)
```
// NOTE, the "pipeline" directive/closure from the declarative pipeline syntax needs to include, or be nested outside,
// and "openshift" directive/closure from the OpenShift Client Plugin for Jenkins.  Otherwise, the declarative pipeline engine
// will not be fully engaged.
// import io.jenkins.plugins.casc.ConfigurationAsCode;
// Set Project Name
def project = "vault-jenkins"

def secret_mongodb = [
  [path: 'secret/mongodb', engineVersion: 1, secretValues: [
    [envVar: 'MONGODB_DATABASE', vaultKey: 'mongodb_database'],
    [envVar: 'MONGODB_USERNAME', vaultKey: 'mongodb_username'],
    [envVar: 'IP', vaultKey: 'ip'],
    [envVar: 'MONGODB_PASSWORD', vaultKey: 'mongodb_password'],
    [envVar: 'MONGODB_ROOT_PASSWORD', vaultKey: 'mongodb_root_password'],
    [envVar: 'PORT', vaultKey: 'port'],
    [envVar: 'PROPPATH', vaultKey: 'proppath']]]]
def secret_docker = [
  [path: 'secret/docker/push', engineVersion: 1, secretValues:[
    [envVar: 'DOCKERUSER', vaultKey: 'dockeruser'],
    [envVar: 'DOCKERPASS', vaultKey: 'dockerpass']]]]

//def PRUEBA =ConfigurationAsCode.get().configure("/var/tmp/jenkins.yaml")

pipeline {
    agent {
      node {
        // spin up a maven-skopeo-agent slave pod to run this build on
        label 'maven-skopeo-agent'
      }
    }
    options {
        // set a timeout of 20 minutes for this pipeline
        timeout(time: 20, unit: 'MINUTES')
    }  
    stages{  
      stage('Cleanup') {
            steps {
                script {
                    openshift.withCluster() {
                        openshift.withProject("$project") {
                            echo "Using project: ${openshift.project()}"
                            openshift.selector("all", [ app : 'vault-mongodb' ]).delete()
                            openshift.selector("secret", [ app : 'vault-mongodb' ]).delete()
                            openshift.selector("all", [ app : 'vault-app-api' ]).delete()
                        }
                    }
                }
            }
        }
      stage('Deploy Mongodb') {
            steps {
                script {
                    withVault([configuration: [skipSslVerification: true, vaultUrl: "$VAULT_ADDR", vaultCredentialId: 'vault_app_token', engineVersion: 2], vaultSecrets: secret_mongodb]){
                        dir('example03'){
                            sh "sed -i s/mongodb_root_pwd_b64/`echo -n ${MONGODB_ROOT_PASSWORD} | base64 -w 0`/g ./configuration/010-deploy-secret-mongodb-service.yaml"
                            sh '''
                                set +x
                                sed -i s/mongodb_db_b64/`echo -n ${MONGODB_DATABASE} | base64 -w 0`/g ./configuration/010-deploy-secret-mongodb-service.yaml
                                set -x 
                            '''
                            sh "sed -i s/mongodb_pwd_b64/`echo -n ${MONGODB_PASSWORD} | base64 -w 0`/g ./configuration/010-deploy-secret-mongodb-service.yaml"
                            sh "sed -i s/mongodb_user_b64/`echo -n ${MONGODB_USERNAME} | base64 -w 0`/g ./configuration/010-deploy-secret-mongodb-service.yaml"
                            echo "sed ok"
                            openshift.withCluster() {
                              openshift.withProject("$project") {
                                openshift.raw('create', '-f ./configuration/010-deploy-secret-mongodb-service.yaml')
                                }
                            }
                        }
                    }                   
                }
            }
        }
      stage('Build and Deploy Vault-App') {
            steps {
              withVault([configuration: [skipSslVerification: true, vaultUrl: "$VAULT_ADDR", vaultCredentialId: 'vault_app_token', engineVersion: 2], vaultSecrets: secret_mongodb]) {
              script {
                openshift.withCluster() {
                  openshift.withProject("$project") {
                    openshift.newApp('https://github.com/ferluko/ocp-vault-poc.git --context-dir appointment --name vault-app-api -l app=vault-app-api -e MONGODB_USERNAME="$MONGODB_USERNAME" MONGODB_PASSWORD="$MONGODB_PASSWORD" MONGODB_DATABASE="$MONGODB_DATABASE" IP="$IP" PORT="$PORT" PROPPATH="$PROPPATH"')
                    sleep(time: 95, unit: 'SECONDS')
                    openshift.raw('expose', 'svc vault-app-api')
                    }
                }
            }
        }
    }
}
      stage('Copy Image to dockerHub Container Registry') {
          steps {
            withVault([configuration: [skipSslVerification: true, vaultUrl: "$VAULT_ADDR", vaultCredentialId: 'vault_app_token', engineVersion: 2], vaultSecrets: secret_docker]) {
            echo "Copy image to dockerHub container registry"
            script {
              sh "skopeo copy --src-tls-verify=false --dest-tls-verify=false --src-creds openshift:\$(oc whoami -t) --dest-creds $DOCKERUSER:$DOCKERPASS docker://image-registry.openshift-image-registry.svc.cluster.local:5000/vault-jenkins/vault-app-api:latest docker://docker.io/semperti/ocp-vault-poc:latest"
            }
          }
      }
  }
 }
}
```
## Análisis del [```setup_vault.sh```](https://gitlab.semperti.com/fernando.gonzalez/jenkins-vault-poc/blob/master/example03/configuration/setup_vault.sh)
Script de configuración de Vault para el escenario
```
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
#vault write auth/approle/role/jenkins-role secret_id_ttl=10m token_num_uses=2 token_ttl=15m token_max_ttl=20m
```

### REFERENCIAS: 
* https://www.hashicorp.com/blog/authenticating-applications-with-vault-approle/
* https://www.vaultproject.io/docs/auth/approle.html
* https://github.com/openshift/jenkins-client-plugin
* https://www.openshift.com/blog/integrating-hashicorp-vault-in-openshift-4
* https://plugins.jenkins.io/hashicorp-vault-plugin/
* https://plugins.jenkins.io/configuration-as-code/
* https://plugins.jenkins.io/credentials/
