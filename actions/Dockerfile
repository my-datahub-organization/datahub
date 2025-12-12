# DataHub Actions (Ingestion Executor)
# Build: docker build -t datahub-actions ./actions
# Run: docker run --env-file .env datahub-actions

ARG DATAHUB_VERSION=head
FROM acryldata/datahub-actions:${DATAHUB_VERSION}-slim

# Install OpenSSL and Java keytool for certificate operations (as root)
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssl \
    openjdk-17-jre-headless \
    && rm -rf /var/lib/apt/lists/*

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER datahub

# Authentication Configuration - MUST be provided via environment variables from .env
# GMS Connection (overridden by entrypoint from DATAHUB_GMS_URL)
ENV DATAHUB_GMS_HOST=host.docker.internal
ENV DATAHUB_GMS_PORT=8080
ENV DATAHUB_GMS_PROTOCOL=http

# Kafka Configuration - Certificate-based authentication (mTLS)
ENV KAFKA_PROPERTIES_SECURITY_PROTOCOL=SSL
ENV KAFKA_PROPERTIES_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM=
ENV KAFKA_PROPERTIES_SSL_TRUSTSTORE_TYPE=JKS
ENV KAFKA_PROPERTIES_SSL_KEYSTORE_TYPE=PKCS12

# Use entrypoint to map env var names
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
CMD ["datahub-actions", "actions", "run", "-c", "/etc/datahub/actions/system/conf/executor.yaml"]
