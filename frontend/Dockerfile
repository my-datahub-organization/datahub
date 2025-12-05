# DataHub Frontend (Web UI)
# Build: docker build -t datahub-frontend ./frontend
# Run: docker run -p 9002:9002 --env-file .env datahub-frontend

ARG DATAHUB_VERSION=head
FROM acryldata/datahub-frontend-react:${DATAHUB_VERSION}

# Copy entrypoint script that parses connection string env vars
COPY entrypoint.sh /entrypoint.sh

# GMS Connection
ENV DATAHUB_GMS_HOST=host.docker.internal
ENV DATAHUB_GMS_PORT=8080
ENV DATAHUB_APP_VERSION=1.0
ENV DATAHUB_PLAY_MEM_BUFFER_SIZE=10MB

# Kafka Configuration
ENV DATAHUB_TRACKING_TOPIC=DataHubUsageEvent_v1

# Kafka SASL with SSL (required by Aiven Kafka)
ENV KAFKA_PROPERTIES_SECURITY_PROTOCOL=SASL_SSL
ENV KAFKA_PROPERTIES_SASL_MECHANISM=PLAIN
# Disable SSL certificate verification (Aiven uses self-signed CA)
ENV KAFKA_PROPERTIES_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM=
ENV KAFKA_PROPERTIES_SSL_TRUSTSTORE_TYPE=JKS
ENV KAFKA_PROPERTIES_SSL_TRUSTSTORE_LOCATION=/etc/ssl/certs/java/cacerts
ENV KAFKA_PROPERTIES_SSL_TRUSTSTORE_PASSWORD=changeit

# OpenSearch Configuration (Play Framework style)
ENV ELASTIC_CLIENT_USE_SSL=true
ENV ELASTIC_CLIENT_SSL_PROTOCOL=TLSv1.2

# JVM Settings - reduced memory for container environments + SSL truststore
ENV JAVA_OPTS="-Xms256m -Xmx384m -Dhttp.port=9002 -Dconfig.file=datahub-frontend/conf/application.conf -Djava.security.auth.login.config=datahub-frontend/conf/jaas.conf -Dlogback.configurationFile=datahub-frontend/conf/logback.xml -Dlogback.debug=false -Dpidfile.path=/dev/null -Djavax.net.ssl.trustStore=/etc/ssl/certs/java/cacerts -Djavax.net.ssl.trustStorePassword=changeit"

# Expose Frontend port
EXPOSE 9002

# Use entrypoint to parse connection string env vars into component vars
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
CMD ["/datahub-frontend/bin/datahub-frontend"]
