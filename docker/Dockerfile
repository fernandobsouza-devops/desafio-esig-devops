# Usa a imagem oficial do Tomcat 9 com JDK 11
FROM tomcat:9.0-jdk11-openjdk-slim

# Define o diretório de trabalho do Tomcat
WORKDIR /usr/local/tomcat

# Remove as aplicações padrão do Tomcat para limpar a raiz
RUN rm -rf webapps/*

# Baixa o agente Jolokia JVM Agent para monitoramento via JMX/HTTP
ADD https://repo1.maven.org/maven2/org/jolokia/jolokia-jvm/1.7.2/jolokia-jvm-1.7.2-agent.jar bin/jolokia-agent.jar

# Baixa o arquivo WAR estável do Jenkins e o posiciona no Tomcat
ADD https://get.jenkins.io/war-stable/latest/jenkins.war webapps/jenkins.war

# Configura as opções da JVM para carregar o agente do Jolokia na porta 8778
ENV CATALINA_OPTS="-javaagent:/usr/local/tomcat/bin/jolokia-agent.jar=port=8778,host=0.0.0.0"

# Expõe as portas do Tomcat (8080) e do Jolokia (8778)
EXPOSE 8080 8778

# Comando para iniciar o servidor Tomcat
CMD ["catalina.sh", "run"]