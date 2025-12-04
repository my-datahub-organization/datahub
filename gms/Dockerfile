# DataHub GMS (Metadata Service)
# Build: docker build -t datahub-gms ./gms
# Run: docker run -p 8080:8080 --env-file .env datahub-gms

ARG DATAHUB_VERSION=head
FROM acryldata/datahub-gms:${DATAHUB_VERSION}

# Working directory for DDL file generation
WORKDIR /tmp/ddl

# Copy entrypoint script that parses connection string env vars
COPY entrypoint.sh /entrypoint.sh

# Disable the base image's dependency wait (we handle startup order differently)
ENV SKIP_ELASTICSEARCH_CHECK=true
ENV SKIP_KAFKA_CHECK=true
ENV SKIP_NEO4J_CHECK=true
ENV SKIP_MYSQL_CHECK=true
ENV SKIP_POSTGRES_CHECK=true

# PostgreSQL Configuration
ENV EBEAN_DATASOURCE_DRIVER=org.postgresql.Driver
ENV EBEAN_AUTOCREATE=true
ENV EBEAN_DDL_MODE=update

# Kafka Configuration
ENV KAFKA_AUTO_CREATE_TOPICS_ENABLED=true
ENV SCHEMA_REGISTRY_TYPE=INTERNAL
ENV KAFKA_SCHEMAREGISTRY_URL=http://localhost:8080/schema-registry/api/

# Kafka SSL/SASL
ENV SPRING_KAFKA_PROPERTIES_SECURITY_PROTOCOL=SASL_SSL
ENV SPRING_KAFKA_PROPERTIES_SASL_MECHANISM=PLAIN
# Use system CA certificates instead of custom truststore
ENV SPRING_KAFKA_PROPERTIES_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM=https

# OpenSearch Configuration
ENV ELASTICSEARCH_PROTOCOL=https
ENV ELASTICSEARCH_USE_SSL=true
ENV ELASTICSEARCH_IMPLEMENTATION=opensearch
ENV ELASTICSEARCH_SSL_PROTOCOL=TLSv1.2

# Service Configuration
ENV GRAPH_SERVICE_IMPL=elasticsearch
ENV MAE_CONSUMER_ENABLED=true
ENV MCE_CONSUMER_ENABLED=true
ENV PE_CONSUMER_ENABLED=true
ENV UI_INGESTION_ENABLED=true

# JVM Settings
ENV JAVA_OPTS="-Xms1g -Xmx1g"

# Expose GMS port
EXPOSE 8080

# Use entrypoint to parse connection string env vars into component vars
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
CMD ["/datahub/datahub-gms/bin/datahub-gms"]
