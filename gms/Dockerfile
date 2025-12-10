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

# Kafka Configuration - Certificate-based authentication (mTLS)
ENV SPRING_KAFKA_PROPERTIES_SECURITY_PROTOCOL=SSL
ENV SPRING_KAFKA_PROPERTIES_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM=
ENV SPRING_KAFKA_PROPERTIES_SSL_TRUSTSTORE_TYPE=JKS

# Schema Registry Configuration - Use GMS's built-in schema registry
ENV SCHEMA_REGISTRY_TYPE=INTERNAL

# OpenSearch Configuration
ENV ELASTICSEARCH_IMPLEMENTATION=opensearch
ENV ELASTICSEARCH_USE_SSL=true
ENV ELASTICSEARCH_SSL_PROTOCOL=TLSv1.2
ENV ELASTICSEARCH_BUILD_INDICES_RETENTION_VALUE=30

# Entity Registry Configuration
ENV ENTITY_REGISTRY_CONFIG_PATH=/datahub/datahub-gms/resources/entity-registry.yml

# Bootstrap Configuration
ENV BOOTSTRAP_SYSTEM_UPDATE_ENABLED=true
ENV BOOTSTRAP_SYSTEM_UPDATE_WAIT_FOR_SYSTEM_UPDATE=false
ENV INDEX_BUILDER_ENABLED=true
ENV ALWAYS_EMIT_CHANGE_LOG=true

# Authentication Configuration
# Disable Metadata Service Authentication (use cookie-based auth instead)
ENV METADATA_SERVICE_AUTH_ENABLED=false
ENV AUTH_NATIVE_ENABLED=true
ENV AUTH_GUEST_ENABLED=true
ENV BOOTSTRAP_DEFAULT_ROOT_USER_ENABLED=true

# Enable verbose authentication logging for debugging
ENV AUTH_VERBOSE_LOGGING=true

# Expose GMS port
EXPOSE 8080

ENTRYPOINT ["/bin/bash", "/custom-entrypoint.sh"]
CMD ["/bin/bash", "-c", "exec /datahub/datahub-gms/scripts/start.sh"]
