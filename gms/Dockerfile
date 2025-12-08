# DataHub GMS (Metadata Service)
# Build: docker build -t datahub-gms ./gms
# Run: docker run -p 8080:8080 --env-file .env datahub-gms

ARG DATAHUB_VERSION=head
FROM acryldata/datahub-gms:${DATAHUB_VERSION}

# Install openssl for fetching Kafka SSL certificates
USER root
RUN apk add --no-cache openssl bc
USER datahub

# Copy custom entrypoint script
COPY entrypoint.sh /custom-entrypoint.sh

# Disable the base image's dependency wait (we handle startup order differently)
ENV SKIP_ELASTICSEARCH_CHECK=true
ENV SKIP_KAFKA_CHECK=true
ENV SKIP_NEO4J_CHECK=true
ENV SKIP_MYSQL_CHECK=true
ENV SKIP_POSTGRES_CHECK=true

# PostgreSQL Configuration
ENV EBEAN_DATASOURCE_DRIVER=org.postgresql.Driver
# Auto-create tables if they don't exist
ENV EBEAN_AUTOCREATE=true
# Completely disable DDL file generation (container filesystem is read-only)
ENV EBEAN_DDL_GENERATE=false
ENV EBEAN_DDL_RUN=false
ENV EBEAN_DDL_INIT_SQL=
ENV EBEAN_DDL_SEED_SQL=

# Kafka Configuration
ENV KAFKA_AUTO_CREATE_TOPICS_ENABLED=true
ENV SCHEMA_REGISTRY_TYPE=INTERNAL
ENV KAFKA_SCHEMAREGISTRY_URL=http://localhost:8080/schema-registry/api/

# Kafka SASL with SSL (required by Aiven Kafka)
ENV SPRING_KAFKA_PROPERTIES_SECURITY_PROTOCOL=SASL_SSL
ENV SPRING_KAFKA_PROPERTIES_SASL_MECHANISM=PLAIN
# Disable hostname verification (Aiven uses internal hostnames)
ENV SPRING_KAFKA_PROPERTIES_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM=
# Truststore is configured dynamically by entrypoint (fetches CA from Kafka server)
ENV SPRING_KAFKA_PROPERTIES_SSL_TRUSTSTORE_TYPE=JKS

# OpenSearch Configuration
ENV ELASTICSEARCH_PROTOCOL=https
ENV ELASTICSEARCH_USE_SSL=true
ENV ELASTICSEARCH_IMPLEMENTATION=opensearch
ENV ELASTICSEARCH_SSL_PROTOCOL=TLSv1.2

# Entity Registry Configuration
ENV ENTITY_REGISTRY_CONFIG_PATH=/datahub/datahub-gms/resources/entity-registry.yml

# Service Configuration
ENV GRAPH_SERVICE_IMPL=elasticsearch
ENV MAE_CONSUMER_ENABLED=true
ENV MCE_CONSUMER_ENABLED=true
ENV PE_CONSUMER_ENABLED=true
ENV UI_INGESTION_ENABLED=true

# Bootstrap Configuration - Required for index creation and system setup
ENV BOOTSTRAP_SYSTEM_UPDATE_ENABLED=true
ENV DATAHUB_ANALYTICS_ENABLED=true
ENV BOOTSTRAP_SYSTEM_UPDATE_WAIT_FOR_SYSTEM_UPDATE=false
# Force reindex on startup if indices are missing
ENV ALWAYS_EMIT_CHANGE_LOG=true

# Authentication disabled by default - can be enabled via environment variables if needed
# ENV DATAHUB_SYSTEM_CLIENT_ID=__datahub_system
# ENV DATAHUB_SYSTEM_CLIENT_SECRET=your-secret-here
# ENV METADATA_SERVICE_AUTH_ENABLED=true
# ENV DATAHUB_TOKEN_SERVICE_SIGNING_KEY=your-signing-key-here
# ENV DATAHUB_TOKEN_SERVICE_SALT=your-salt-here

# JVM Settings - DataHub GMS needs adequate memory for bootstrap and index creation
# SSL truststore is configured dynamically by entrypoint script
ENV JAVA_OPTS="-Xms1024m -Xmx2048m -XX:+UseG1GC -XX:MaxGCPauseMillis=200"

# Expose GMS port
EXPOSE 8080

ENTRYPOINT ["/bin/bash", "/custom-entrypoint.sh"]
CMD ["/bin/bash", "-c", "exec /datahub/datahub-gms/scripts/start.sh"]
