# DataHub Upgrade Job
# This container initializes Elasticsearch/OpenSearch indices and runs database migrations
# Build: docker build -t datahub-upgrade ./upgrade
# Run: docker run --env-file .env datahub-upgrade

ARG DATAHUB_VERSION=head
FROM acryldata/datahub-upgrade:${DATAHUB_VERSION}

# Install openssl for certificate handling
USER root
RUN apk add --no-cache openssl bc
USER datahub

# Copy custom entrypoint script
COPY entrypoint.sh /custom-entrypoint.sh

# Skip dependency checks (we handle them in entrypoint)
ENV SKIP_ELASTICSEARCH_CHECK=true
ENV SKIP_KAFKA_CHECK=true
ENV SKIP_NEO4J_CHECK=true
ENV SKIP_MYSQL_CHECK=true
ENV SKIP_POSTGRES_CHECK=true

# PostgreSQL Configuration
ENV EBEAN_DATASOURCE_DRIVER=org.postgresql.Driver

# Kafka Configuration - Certificate-based authentication (mTLS)
ENV SPRING_KAFKA_PROPERTIES_SECURITY_PROTOCOL=SSL
ENV SPRING_KAFKA_PROPERTIES_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM=
ENV SPRING_KAFKA_PROPERTIES_SSL_TRUSTSTORE_TYPE=JKS

# OpenSearch Configuration
ENV ELASTICSEARCH_IMPLEMENTATION=opensearch
ENV ELASTICSEARCH_USE_SSL=true
ENV ELASTICSEARCH_SSL_PROTOCOL=TLSv1.2

# Entity Registry Configuration
ENV ENTITY_REGISTRY_CONFIG_PATH=/datahub/datahub-gms/resources/entity-registry.yml

ENTRYPOINT ["/bin/bash", "/custom-entrypoint.sh"]
CMD ["java", "-jar", "/datahub/datahub-upgrade/bin/datahub-upgrade.jar", "-u", "SystemUpdate"]
