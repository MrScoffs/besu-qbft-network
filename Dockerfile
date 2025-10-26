FROM ubuntu:20.04

# Copiar a JDK e o Besu para a imagem
COPY jdk-21.0.9 /opt/jdk
COPY besu-25.9.0 /opt/besu

# Configurar variáveis de ambiente
ENV JAVA_HOME=/opt/jdk
ENV PATH="/opt/besu/bin:/opt/jdk/bin:${PATH}"

# Definir o ponto de entrada padrão
ENTRYPOINT ["besu"]