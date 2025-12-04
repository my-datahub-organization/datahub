# DataHub GMS (Metadata Service)
# Build: docker build -t datahub-gms ./gms
# Run: docker run -p 8080:8080 --env-file .env datahub-gms

ARG DATAHUB_VERSION=head
FROM acryldata/datahub-gms:${DATAHUB_VERSION}

# Copy entrypoint script that parses connection string env vars
# and then calls the original startup
COPY entrypoint.sh /aiven-entrypoint.sh

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

# Kafka SSL/SASL
ENV SPRING_KAFKA_PROPERTIES_SECURITY_PROTOCOL=SASL_SSL
ENV SPRING_KAFKA_PROPERTIES_SASL_MECHANISM=PLAIN
ENV SPRING_KAFKA_PROPERTIES_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM=https
# Use Java's default cacerts truststore (Alpine path)
ENV SPRING_KAFKA_PROPERTIES_SSL_TRUSTSTORE_LOCATION=/etc/ssl/certs/java/cacerts
ENV SPRING_KAFKA_PROPERTIES_SSL_TRUSTSTORE_PASSWORD=changeit
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

# JVM Settings - reduced memory for container environments
# Include SSL truststore settings as JVM properties
ENV JAVA_OPTS="-Xms256m -Xmx512m -Djavax.net.ssl.trustStore=/etc/ssl/certs/java/cacerts -Djavax.net.ssl.trustStorePassword=changeit"

# Expose GMS port
EXPOSE 8080

# Use our entrypoint to parse env vars, then delegate to original startup
# The base image uses /datahub/datahub-gms/scripts/start.sh
ENTRYPOINT ["/bin/bash", "/aiven-entrypoint.sh"]
CMD ["/bin/bash", "-c", "exec /datahub/datahub-gms/scripts/start.sh"]
