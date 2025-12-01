# DataHub GMS (Metadata Service)
# Build: docker build -t datahub-gms-aiven ./gms
# Run: docker run -p 8093:8080 -v $(pwd)/certs:/etc/datahub/certs:ro -v $(pwd)/tmp/ddl:/tmp/ddl:rw --env-file .env datahub-gms-aiven

ARG DATAHUB_VERSION=head
FROM acryldata/datahub-gms:${DATAHUB_VERSION}

# Working directory for DDL file generation
WORKDIR /tmp/ddl

# PostgreSQL Configuration
ENV EBEAN_DATASOURCE_DRIVER=org.postgresql.Driver
ENV EBEAN_AUTOCREATE=true
ENV EBEAN_DDL_MODE=update

# Kafka Configuration
ENV KAFKA_AUTO_CREATE_TOPICS_ENABLED=true
ENV SCHEMA_REGISTRY_TYPE=INTERNAL
ENV KAFKA_SCHEMAREGISTRY_URL=http://localhost:8080/schema-registry/api/

# Kafka SSL/SASL (only truststore needed for SASL_SSL + PLAIN)
ENV SPRING_KAFKA_PROPERTIES_SECURITY_PROTOCOL=SASL_SSL
ENV SPRING_KAFKA_PROPERTIES_SASL_MECHANISM=PLAIN
ENV SPRING_KAFKA_PROPERTIES_SSL_TRUSTSTORE_LOCATION=/etc/datahub/certs/truststore.jks

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

# Required environment variables (must be provided at runtime):
# - EBEAN_DATASOURCE_USERNAME
# - EBEAN_DATASOURCE_PASSWORD
# - EBEAN_DATASOURCE_HOST (host:port format)
# - EBEAN_DATASOURCE_URL (full JDBC URL)
# - KAFKA_BOOTSTRAP_SERVER
# - SPRING_KAFKA_PROPERTIES_SASL_JAAS_CONFIG (contains username/password)
# - SPRING_KAFKA_PROPERTIES_SSL_TRUSTSTORE_PASSWORD
# - ELASTICSEARCH_HOST
# - ELASTICSEARCH_PORT
# - ELASTICSEARCH_USERNAME
# - ELASTICSEARCH_PASSWORD
