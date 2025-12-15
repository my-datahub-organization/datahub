# DataHub Actions (Ingestion Executor)
# Build: docker build -t datahub-actions ./actions
# Run: docker run --env-file .env datahub-actions

ARG DATAHUB_VERSION=head
FROM acryldata/datahub-actions:${DATAHUB_VERSION}-slim

# Copy entrypoint script
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# GMS Connection (will be overridden by DATAHUB_GMS_URL from docker-compose)
ENV DATAHUB_GMS_HOST=gms
ENV DATAHUB_GMS_PORT=8080
ENV DATAHUB_GMS_PROTOCOL=http

# Schema Registry
ENV SCHEMA_REGISTRY_URL=http://gms:8080/schema-registry/api/

# Kafka Topics
ENV METADATA_CHANGE_LOG_VERSIONED_TOPIC_NAME=MetadataChangeLog_Versioned_v1
ENV PLATFORM_EVENT_TOPIC_NAME=PlatformEvent_v1

# Kafka SSL Configuration (Python kafka-python properties)
ENV KAFKA_PROPERTIES_SECURITY_PROTOCOL=SSL
ENV KAFKA_PROPERTIES_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM=none

# Use entrypoint to write certificates and set environment variables
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
CMD ["datahub-actions", "actions", "run", "-c", "/etc/datahub/actions/system/conf/executor.yaml"]
