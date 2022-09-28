Scripts de soporte y jenkinsfile para ejeucion de pipeline
**Jenkinsfile**= Ejecuta el pipeline que obtiene los secretos desde Hashicorp Vault.

**\configuration\010-deploy-secret-mongodb-service.yaml**= Ejecuta la creacion del servicio y secretos de mongodb.

**\configuration\setup_vault.sh**= Habilita, configura y popula secretos en Hashicorp Vault con el metodo approle.

*REPO_PIPELINE*= Es el presente repositorio del cual obtendremos los archivos necesarios para realizar el despliegue inicial de Jenkins, la configuracion de Hashicorp Vault con APPROLE como metodo de autentificacion y el pipeline que terminara desplegando la aplicacion de ejemplo.

*CONTEXT_DIR_PIPELINE*= Sera el directorio que definiremos como contexto para la ejecucion del pipeline

*VAULT_ADDR*= Es la ruta del servicio de Hashicorp Vault la cual obtendremos desde *Networking -> Routes* en nuestra consola de OCP. Ademas la misma debera de estar declarada como variable de entorno donde Hashicorp Vault se este ejecutando.

*VAULT_TOKEN*= El root token que obtendremos al despliegue inicial de Hashicorp Vault.

*OCP_TOKEN*= Esta variable la obtendremos directamente desde la consola de Openshift.