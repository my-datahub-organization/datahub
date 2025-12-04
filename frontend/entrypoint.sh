#!/bin/bash
# Entrypoint script for DataHub Frontend
# Parses connection string environment variables into component variables

set -e

# Parse OPENSEARCH_URI (format: https://user:pass@host:port)
# Frontend uses ELASTIC_CLIENT_* variables
if [ -n "$OPENSEARCH_URI" ]; then
    # Remove protocol prefix
    OS_URL_NO_PROTO="${OPENSEARCH_URI#*://}"
    
    # Extract user:pass (before @)
    OS_USERPASS="${OS_URL_NO_PROTO%%@*}"
    export ELASTIC_CLIENT_USERNAME="${OS_USERPASS%%:*}"
    export ELASTIC_CLIENT_PASSWORD="${OS_USERPASS#*:}"
    
    # Extract host:port (after @)
    OS_HOSTPORT="${OS_URL_NO_PROTO#*@}"
    export ELASTIC_CLIENT_HOST="${OS_HOSTPORT%%:*}"
    export ELASTIC_CLIENT_PORT="${OS_HOSTPORT#*:}"
    
    echo "OpenSearch configured: host=$ELASTIC_CLIENT_HOST, port=$ELASTIC_CLIENT_PORT"
fi

# Build Kafka SASL JAAS config from individual credentials
if [ -n "$KAFKA_SASL_USERNAME" ] && [ -n "$KAFKA_SASL_PASSWORD" ]; then
    export KAFKA_PROPERTIES_SASL_JAAS_CONFIG="org.apache.kafka.common.security.plain.PlainLoginModule required username=\"$KAFKA_SASL_USERNAME\" password=\"$KAFKA_SASL_PASSWORD\";"
    echo "Kafka SASL configured for user: $KAFKA_SASL_USERNAME"
fi

# Set truststore password (use a default if not provided)
if [ -z "$KAFKA_PROPERTIES_SSL_TRUSTSTORE_PASSWORD" ]; then
    export KAFKA_PROPERTIES_SSL_TRUSTSTORE_PASSWORD="changeit"
fi

# Debug: print configured endpoints (without secrets)
echo "=== DataHub Frontend Configuration ==="
echo "GMS Host: ${DATAHUB_GMS_HOST:-NOT SET}:${DATAHUB_GMS_PORT:-NOT SET}"
echo "Kafka Bootstrap: ${KAFKA_BOOTSTRAP_SERVER:-NOT SET}"
echo "OpenSearch Host: ${ELASTIC_CLIENT_HOST:-NOT SET}:${ELASTIC_CLIENT_PORT:-NOT SET}"
echo "======================================"

# Execute the original entrypoint/command
exec "$@"
