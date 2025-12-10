# DataHub Frontend (Web UI)
# Build: docker build -t datahub-frontend ./frontend
# Run: docker run -p 9002:9002 --env-file .env datahub-frontend

ARG DATAHUB_VERSION=head
FROM acryldata/datahub-frontend-react:${DATAHUB_VERSION}

# Install bash, openssl, and keytool for certificate handling
USER root
RUN apk add --no-cache bash openssl openjdk17-jre-headless
USER datahub

# Copy entrypoint script that parses connection string env vars
COPY entrypoint.sh /entrypoint.sh

# GMS Connection (overridden by entrypoint from DATAHUB_GMS_URL)
ENV DATAHUB_GMS_HOST=host.docker.internal
ENV DATAHUB_GMS_PORT=8080

# Authentication Configuration
ENV DATAHUB_ANALYTICS_ENABLED=true
ENV PAC4J_SESSIONSTORE_PROVIDER=PlayCacheSessionStore
# Disable Metadata Service Authentication (use cookie-based auth instead)
ENV METADATA_SERVICE_AUTH_ENABLED=false
ENV AUTH_VERBOSE_LOGGING=true
ENV GRAPHQL_VERBOSE_LOGGING=true

# Kafka Configuration - Certificate-based authentication (mTLS)
ENV KAFKA_PROPERTIES_SECURITY_PROTOCOL=SSL
ENV KAFKA_PROPERTIES_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM=
ENV KAFKA_PROPERTIES_SSL_TRUSTSTORE_TYPE=JKS
ENV KAFKA_PROPERTIES_SSL_KEYSTORE_TYPE=PKCS12

# OpenSearch Configuration
ENV ELASTIC_CLIENT_USE_SSL=true
ENV ELASTIC_CLIENT_SSL_PROTOCOL=TLSv1.2

# Expose Frontend port
EXPOSE 9002

# Use entrypoint to parse connection string env vars into component vars
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
