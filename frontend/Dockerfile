# DataHub Frontend (Web UI)
# Build: docker build -t datahub-frontend-aiven ./frontend
# Run: docker run -p 8092:9002 -v $(pwd)/certs:/etc/datahub/certs:ro --env-file .env datahub-frontend-aiven

ARG DATAHUB_VERSION=head
FROM acryldata/datahub-frontend-react:${DATAHUB_VERSION}

# GMS Connection (default to Docker host)
ENV DATAHUB_GMS_HOST=host.docker.internal
ENV DATAHUB_GMS_PORT=8093
ENV DATAHUB_APP_VERSION=1.0
ENV DATAHUB_PLAY_MEM_BUFFER_SIZE=10MB

# Kafka Configuration
ENV DATAHUB_TRACKING_TOPIC=DataHubUsageEvent_v1

# Kafka SSL/SASL (Play Framework style)
ENV KAFKA_PROPERTIES_SECURITY_PROTOCOL=SASL_SSL
ENV KAFKA_PROPERTIES_SASL_MECHANISM=PLAIN
ENV KAFKA_PROPERTIES_SSL_TRUSTSTORE_LOCATION=/etc/datahub/certs/truststore.jks
ENV KAFKA_PROPERTIES_SSL_KEYSTORE_LOCATION=/etc/datahub/certs/keystore.jks

# OpenSearch Configuration (Play Framework style)
ENV ELASTIC_CLIENT_USE_SSL=true
ENV ELASTIC_CLIENT_SSL_PROTOCOL=TLSv1.2

# JVM Settings
ENV JAVA_OPTS="-Xms512m -Xmx512m -Dhttp.port=9002 -Dconfig.file=datahub-frontend/conf/application.conf -Djava.security.auth.login.config=datahub-frontend/conf/jaas.conf -Dlogback.configurationFile=datahub-frontend/conf/logback.xml -Dlogback.debug=false -Dpidfile.path=/dev/null"

# Expose Frontend port
EXPOSE 9002

# Required environment variables (must be provided at runtime):
# - DATAHUB_SECRET
# - KAFKA_BOOTSTRAP_SERVER
# - KAFKA_PROPERTIES_SASL_JAAS_CONFIG
# - KAFKA_PROPERTIES_SSL_TRUSTSTORE_PASSWORD
# - KAFKA_PROPERTIES_SSL_KEYSTORE_PASSWORD
# - ELASTIC_CLIENT_HOST
# - ELASTIC_CLIENT_PORT
# - ELASTIC_CLIENT_USERNAME
# - ELASTIC_CLIENT_PASSWORD

