# ocp-vault-poc Stage #2 - OCP + Vault + Jenkins
Prueba de Concepto para la integración de Hashicorp Vault en pipelines CI/CD de Jenkins con compilación y despliegue en Openshift para Aplicaciones "No native Vault logic built-in".
 
## Introducción
Estas instrucciones permitirán obtener una copia de la PoC funcional en su entorno para propósitos de construcción, integración y despliegue de diferentes aplicaciones y deferentes estrategias para la obtención de secretos desde Hashicorp Vault en un pipeline CI/CD de Jenkins.

## Conceptos a ver...
* Revisión de conceptos a generales de Vault
* Policy/ Role/ Path Secret/ Token
* Auth Methods: Token, AppRole
* Engines: KV
* Plugin de Vault para Jenkins
* Plugin de Jenkins Configuration as a Code

## Escenarios a cubrir...
* [Example03](https://gitlab.semperti.com/fernando.gonzalez/jenkins-vault-poc/tree/master/example03) - Recrear el escenario Original de [OCP-Vault-PoC Stage #1](https://github.com/ferluko/ocp-vault-poc)
* [Example04](https://gitlab.semperti.com/fernando.gonzalez/jenkins-vault-poc/tree/master/example04) - Aplicación Java 8 Stateless
* [Example05](https://gitlab.semperti.com/fernando.gonzalez/jenkins-vault-poc/tree/master/example05) - Aplicación Node.js con persistencia de datos

### Pre-Requisitos
_En tu entorno._

* [Vault Server +1.4](https://learn.hashicorp.com/tutorials/vault/getting-started-install?in=vault/getting-started) - Desplegado e inicializado. URL y Token con privilegios válidos. Si aún no lo tiene y desea desplegarlo en Openshift v4.x, pueden utilizar un bash script de despliegue sencillo con posterior inicialización (incluye el unseal) disponible [aqui](https://gitlab.semperti.com/fernando.gonzalez/jenkins-vault-poc/blob/master/bin/init_unseal_vault.sh).

_En tu maquina local._
* [Openshift CLI](https://docs.openshift.com/container-platform/4.2/cli_reference/openshift_cli/getting-started-cli.html) - Instalado y login configurado contra el cluster OCP.

_NOTA: Este despliegue podrá sencillamente adaptarse a otras versiones de Kubernetes (GKE, AKS, PKS, etc) si se considera el despliegue de la aplicación sin la utilización de templates de Openshift o bien consultar el siguiente repositorio para manifiestos agnósticos al sabor de Kubernetes [link](http://gitlab.semperti.com/fernando.gonzalez/jenkins-vault-poc.git)._

## Comenzando
_En tu maquina local._

Clonamos el repositorio y creamos el proyecto ```vault-jenkins``` en Openshift

```
export REPO_PIPELINE="http://gitlab.semperti.com/fernando.gonzalez/jenkins-vault-poc.git"
git clone ${REPO_PIPELINE} 
cd jenkins-vault-poc
oc new-project vault-jenkins
```
## Ejecución del escenario
Previo a la configuración y despliegue de Jenkins, es requerido preparar el escenario. Se realizará las tareas correspondientes en el entorno para su posterior ejecución exitosa en el pipeline. Esta tareas por ejemplo son: configuración del método de autenticación con Vault, crear los secretos ejemplos que luego serán obtenidos en el pipeline, armar la estrategia de despliegue de Openshift con referencia al Pipeline, entre otras. Cada escenario tiene su propio set de comandos y archivos de configuración. 

Entonces se recomienda continuar la PoC con el Readme del propio escenario a ejecutar:
* [Example03](https://gitlab.semperti.com/fernando.gonzalez/jenkins-vault-poc/tree/master/example03) - Recrear el escenario Original de [OCP-Vault-PoC Stage #1](https://github.com/ferluko/ocp-vault-poc)
* [Example04](https://gitlab.semperti.com/fernando.gonzalez/jenkins-vault-poc/tree/master/example04) - Aplicación Java 8 Stateless
* [Example05](https://gitlab.semperti.com/fernando.gonzalez/jenkins-vault-poc/tree/master/example05) - Aplicación Node.js con persistencia de datos

## Configuración y despliegue de Jenkins para todos los escenarios
Una vez preparado el escenario en el paso anterior, se recomienda avanzar con la PoC realizando lo siguiente.
### Building de Agente de Jenkins con Maven y Skopeo
Para la compilación de los artefactos, ejecución de scripts y tareas auxiliares necesarias en todo pipeline CI/CD, utilizaremos un agente (slave) para Jenkins con la imagen de base Maven que Openshift provee por default en su registry: ```"image-registry.openshift-image-registry.svc:5000/openshift/jenkins-agent-maven"```. Es decir, al ejecutarse el pipeline Jenkins desplegará un pod con esta imagen para las tareas mencionadas. De esta forma nos ahorramos tener un slave siempre activo consumiendo recursos y solo lo desplegamos al momento de utilizarlo.

En detalle, recompilaremos la imagen mencionada agregándole ```skopeo``` y ```ubi8/go-toolset``` y una vez finalizado llamaremos este ImageStream: ``` maven-skopeo-agent```.

Más información del agente mencionado en su [Repositorio](https://github.com/openshift/jenkins/tree/master/agent-maven-3.5) oficial.


```
oc new-build --strategy=docker -D $'FROM registry.access.redhat.com/ubi8/go-toolset:latest as builder\n
ENV SKOPEO_VERSION=v1.0.0\n
RUN git clone -b $SKOPEO_VERSION https://github.com/containers/skopeo.git && cd skopeo/ && make binary-local DISABLE_CGO=1\n
FROM image-registry.openshift-image-registry.svc:5000/openshift/jenkins-agent-maven:v4.0 as final\n
USER root\n
RUN mkdir /etc/containers\n
COPY --from=builder /opt/app-root/src/skopeo/default-policy.json /etc/containers/policy.json\n
COPY --from=builder /opt/app-root/src/skopeo/skopeo /usr/bin\n
USER 1001' --name=maven-skopeo-agent -n vault-jenkins 
```

Una vez completado el *building* creamos el configmap que posteriormente utilizará jenkins para configurar e invocar este agente:

```
oc create -f ./manifests/agent-cm.yaml -n vault-jenkins 
```
## Despliegue (Deployment) de JENKINS Ephemeral en OPENSHIFT
Ephemeral, sin persistencia de datos configurado o definido por código al inicio. Se recomienda desplegar la imagen de un reciente **build** del repositorio original de la version Jenkins mantenido por Red Hat. así no tendrán problemas con las dependencias. Realizar un nuevo **build** de Jenkins para Openshift del siguiente [Repositorio](https://github.com/openshift/jenkins) con el siguiente comando:

```
oc new-build https://github.com/openshift/jenkins.git --context-dir 2 -n openshift
```
Para el despliegue de Jenkins utilizaremos el template que nos trae Openshift, los manifiestos y los parámetros que acepta podrán ser consultados con el siguiente comando:

```
oc get template jenkins-ephemeral -n openshift -o yaml
```

Entonces, pasamos como parámetro al template Openshift desplegar desde la última imagen compilada, el path del archivo de configuración definido por el configmap creado en el escenario elegido, la instalación del plugin de Hashicorp Vault y la actualización del resto de los plugins para no tener problemas con la dependencias:

```
oc new-app jenkins-ephemeral --param JENKINS_IMAGE_STREAM_TAG=jenkins:latest -e CASC_JENKINS_CONFIG=/var/jenkins_config/ PLUGINS_FORCE_UPGRADE=true INSTALL_PLUGINS=hashicorp-vault-plugin -n vault-jenkins
oc rollout pause dc jenkins -n vault-jenkins
oc patch dc jenkins --patch='{ "spec": { "strategy": { "type": "Recreate" }}}' -n vault-jenkins
oc set volume dc/jenkins --add --overwrite --name=casc-jenkins --mount-path=/var/jenkins_config/ --type configmap --configmap-name jenkins-configuration-as-code -n vault-jenkins
oc rollout resume dc jenkins -n vault-jenkins
```

## Ejecución del Pipeline del escenario elegido

Para la ejecución del escenario solo es cuestión de comenzar el *Build* del *BuildConfig* definido en el propio escenario. Lo ejecutamos con el siguiente comando:

```
oc start-build ${CONTEXT_DIR_PIPELINE}-pipeline -n vault-jenkins
```

A modo didáctico se podrá observar el progreso del Pipeline y acceder a los logs de Jenkins desde la cónsola GUI de Openshift.



#### REFERENCIAS: 
* https://www.hashicorp.com/blog/authenticating-applications-with-vault-approle/
* https://github.com/openshift/jenkins-client-plugin
* https://www.openshift.com/blog/integrating-hashicorp-vault-in-openshift-4
* https://plugins.jenkins.io/hashicorp-vault-plugin/
* https://plugins.jenkins.io/configuration-as-code/
* https://plugins.jenkins.io/credentials/