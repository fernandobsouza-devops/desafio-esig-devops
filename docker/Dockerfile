FROM tomcat:9.0-jdk17-temurin-jammy

WORKDIR /usr/local/tomcat

# Diretório padrão para os dados e configurações do Jenkins
ENV JENKINS_HOME=/var/jenkins_home

# Cria o diretório de dados do Jenkins, instala curl e limpa as aplicações padrão do Tomcat
RUN apt-get update && apt-get install -y curl && \
    mkdir -p /var/jenkins_home && \
    rm -rf webapps/* && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Item 1 e 3: Baixa o WAR oficial do Jenkins como ROOT.war (para responder direto na raiz /)
# Item 6: Baixa o Jolokia Agent v1.6.2 com URL validada no Maven Central
RUN curl -fL -o webapps/ROOT.war "https://updates.jenkins.io/download/war/2.440.3/jenkins.war" && \
    curl -fL -o bin/jolokia-agent.jar "https://repo1.maven.org/maven2/org/jolokia/jolokia-jvm/1.6.2/jolokia-jvm-1.6.2-agent.jar" && \
    chmod 644 bin/jolokia-agent.jar webapps/ROOT.war

# Item 6: Configura limites de memória e ativa o agente Jolokia na JVM do Tomcat
ENV CATALINA_OPTS="-Xms512m -Xmx1024m -javaagent:/usr/local/tomcat/bin/jolokia-agent.jar=port=8778,host=0.0.0.0"

EXPOSE 8080 8778

CMD ["catalina.sh", "run"]
