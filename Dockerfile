FROM ubuntu:20.04

# Copiar a JDK e o Besu para a imagem
COPY jdk-21.0.8 /opt/jdk
COPY besu-24.7.0 /opt/besu

# Configurar variáveis de ambiente
ENV JAVA_HOME=/opt/jdk
ENV PATH="/opt/besu/bin:/opt/jdk/bin:${PATH}"

# Definir o ponto de entrada padrão
ENTRYPOINT ["besu"]
