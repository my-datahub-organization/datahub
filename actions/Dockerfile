# DataHub Actions (Ingestion Executor)
# Build: docker build -t datahub-actions-aiven ./actions
# Run: docker run -v $(pwd)/certs:/etc/datahub/certs:ro -v $(pwd)/executor.yaml:/etc/datahub/actions/system/conf/executor.yaml:ro --env-file .env datahub-actions-aiven

ARG DATAHUB_VERSION=head
FROM acryldata/datahub-actions:${DATAHUB_VERSION}-slim

# Install PostgreSQL driver
RUN pip install psycopg2-binary==2.9.9

# GMS Connection (default to Docker host)
ENV DATAHUB_GMS_HOST=host.docker.internal
ENV DATAHUB_GMS_PORT=8093
ENV DATAHUB_GMS_PROTOCOL=http

# System Auth
ENV DATAHUB_SYSTEM_CLIENT_ID=__datahub_system

# Kafka Configuration
ENV METADATA_AUDIT_EVENT_NAME=MetadataAuditEvent_v4
ENV METADATA_CHANGE_LOG_VERSIONED_TOPIC_NAME=MetadataChangeLog_Versioned_v1

# Kafka SSL/SASL (only CA cert needed for SASL_SSL + PLAIN)
ENV KAFKA_PROPERTIES_SECURITY_PROTOCOL=SASL_SSL
ENV KAFKA_PROPERTIES_SASL_MECHANISM=PLAIN
ENV KAFKA_PROPERTIES_SSL_CA_LOCATION=/etc/datahub/certs/kafka/ca.pem

# Default command
CMD ["datahub-actions", "actions", "run", "-c", "/etc/datahub/actions/system/conf/executor.yaml"]

# Required environment variables (must be provided at runtime):
# - DATAHUB_SYSTEM_CLIENT_SECRET
# - KAFKA_BOOTSTRAP_SERVER
# - KAFKA_PROPERTIES_SASL_USERNAME
# - KAFKA_PROPERTIES_SASL_PASSWORD
# - SCHEMA_REGISTRY_URL
