FROM jenkins/jenkins:lts
ENV CASC_JENKINS_CONFIG="/var/jenkins_home/jenkins.yml"
ENV CASC_VAULT_TOKEN=s.lwJF5vQ1pyvCTxjKr1QkYS4L
ENV CASC_VAULT_PATH=/secret/jenkins
ENV CASC_VAULT_URL=https://vault-hashicorp.apps.ocp4.labs.semperti.local
USER jenkins
RUN /usr/local/bin/install-plugins.sh configuration-as-code git workflow-cps-global-lib hashicorp-vault-plugin
