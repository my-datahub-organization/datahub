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
ENV EBEAN_AUTOCREATE=true
ENV EBEAN_DDL_GENERATE=false
ENV EBEAN_DDL_RUN=false
# Increase connection pool size to handle search queries
ENV EBEAN_DATASOURCE_MAX_CONNECTIONS=100
ENV EBEAN_DATASOURCE_MIN_CONNECTIONS=10

# Kafka Configuration - Certificate-based authentication (mTLS)
ENV SPRING_KAFKA_PROPERTIES_SECURITY_PROTOCOL=SSL
ENV SPRING_KAFKA_PROPERTIES_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM=
ENV SPRING_KAFKA_PROPERTIES_SSL_TRUSTSTORE_TYPE=JKS

# Schema Registry Configuration - Use GMS's built-in schema registry
ENV SCHEMA_REGISTRY_TYPE=INTERNAL

ENV METADATA_SERVICE_AUTH_ENABLED=true

# OpenSearch Configuration
ENV ELASTICSEARCH_IMPLEMENTATION=opensearch
ENV ELASTICSEARCH_USE_SSL=true
ENV ELASTICSEARCH_SSL_PROTOCOL=TLSv1.2
ENV ELASTICSEARCH_BUILD_INDICES_RETENTION_VALUE=30
ENV ELASTICSEARCH_INDEX_BUILDER_MAPPINGS_REINDEX=true
ENV ELASTICSEARCH_INDEX_BUILDER_SETTINGS_REINDEX=true
ENV ES_BULK_REFRESH_POLICY=WAIT_UNTIL

# Entity Registry Configuration
ENV ENTITY_REGISTRY_CONFIG_PATH=/datahub/datahub-gms/resources/entity-registry.yml

# Graph Service Configuration
ENV GRAPH_SERVICE_IMPL=elasticsearch
ENV GRAPH_SERVICE_DIFF_MODE_ENABLED=true
ENV ENTITY_SERVICE_ENABLE_RETENTION=true

# Bootstrap Configuration
ENV BOOTSTRAP_SYSTEM_UPDATE_ENABLED=true
ENV BOOTSTRAP_SYSTEM_UPDATE_WAIT_FOR_SYSTEM_UPDATE=false
ENV INDEX_BUILDER_ENABLED=true
ENV ALWAYS_EMIT_CHANGE_LOG=true

# Consumer Enablement - CRITICAL for MCL consumer to start
ENV MAE_CONSUMER_ENABLED=true
ENV MCE_CONSUMER_ENABLED=true
ENV PE_CONSUMER_ENABLED=true

# Kafka Consumer Configuration
ENV KAFKA_AUTO_CREATE_TOPICS_ENABLED=true
ENV KAFKA_CONSUMER_STOP_ON_DESERIALIZATION_ERROR=true

# Authentication Configuration - MUST be provided via environment variables from .env
# Do NOT set defaults here - they must be explicitly provided via docker-compose
ENV AUTH_VERBOSE_LOGGING=true

# JVM Memory Settings - Using full 2GB container limit
ENV JAVA_OPTS="-Xms1g -Xmx2g"

# Expose GMS port
EXPOSE 8080

ENTRYPOINT ["/bin/bash", "/custom-entrypoint.sh"]
CMD ["/bin/bash", "-c", "exec /datahub/datahub-gms/scripts/start.sh"]
