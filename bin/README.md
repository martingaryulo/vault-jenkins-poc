Scripts de soporte y para ejecucion de PoC.

**init_unseal_vault.sh**= Ejecuta el unseal de Hashicorp Vault siempre que se ejecute con un solo pod. No utilizar para implementacion con HA ya que requiere de unseal respetando el orden de pod 0,1,2 .

**setup_vault_server.sh**= Ejecutar para realizar un deployment de Hashicorp Vault standalone. 
**setup_jenkins.sh**= Ejecuta la PoC de manera integra cumpliendo con los pre-requisitos establecidos.
Para ejecutarse correctamente deben pasarsele los parametros

*REPO_PIPELINE*= Es el presente repositorio del cual obtendremos los archivos necesarios para realizar el despliegue inicial de Jenkins, la configuracion de Hashicorp Vault con APPROLE como metodo de autentificacion y el pipeline que terminara desplegando la aplicacion de ejemplo.

*CONTEXT_DIR_PIPELINE*= Sera el directorio que definiremos como contexto para la ejecucion del pipeline

*VAULT_ADDR*= Es la ruta del servicio de Hashicorp Vault la cual obtendremos desde *Networking -> Routes* en nuestra consola de OCP. Ademas la misma debera de estar declarada como variable de entorno donde Hashicorp Vault se este ejecutando.

*VAULT_TOKEN*= El root token que obtendremos al despliegue inicial de Hashicorp Vault.

*OCP_TOKEN*= Esta variable la obtendremos directamente desde la consola de Openshift.