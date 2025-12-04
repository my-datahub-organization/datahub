# DataHub Actions (Ingestion Executor)
# Build: docker build -t datahub-actions ./actions
# Run: docker run --env-file .env datahub-actions

ARG DATAHUB_VERSION=head
FROM acryldata/datahub-actions:${DATAHUB_VERSION}-slim

# Install PostgreSQL driver
RUN pip install psycopg2-binary==2.9.9

# Copy entrypoint script that maps env var names
COPY entrypoint.sh /entrypoint.sh

# GMS Connection
ENV DATAHUB_GMS_HOST=host.docker.internal
ENV DATAHUB_GMS_PORT=8080
ENV DATAHUB_GMS_PROTOCOL=http

# System Auth
ENV DATAHUB_SYSTEM_CLIENT_ID=__datahub_system

# Kafka Configuration
ENV METADATA_AUDIT_EVENT_NAME=MetadataAuditEvent_v4
ENV METADATA_CHANGE_LOG_VERSIONED_TOPIC_NAME=MetadataChangeLog_Versioned_v1

# Kafka SSL/SASL
ENV KAFKA_PROPERTIES_SECURITY_PROTOCOL=SASL_SSL
ENV KAFKA_PROPERTIES_SASL_MECHANISM=PLAIN
ENV KAFKA_PROPERTIES_SSL_CA_LOCATION=/etc/datahub/certs/kafka/ca.pem

# Use entrypoint to map env var names
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
CMD ["datahub-actions", "actions", "run", "-c", "/etc/datahub/actions/system/conf/executor.yaml"]
