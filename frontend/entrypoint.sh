#!/bin/bash
# Entrypoint script for DataHub Frontend
# Parses connection string environment variables into component variables

set -e

echo "=== DataHub Frontend Entrypoint Starting ==="

# Function to wait for DNS resolution of a host
# Default: 120 attempts * 10 seconds = 20 minutes max wait
wait_for_dns() {
    local host="$1"
    local max_attempts="${2:-120}"
    local attempt=1
    
    echo "Waiting for DNS resolution of $host (max wait: $((max_attempts * 10 / 60)) minutes)..."
    while [ $attempt -le $max_attempts ]; do
        if getent hosts "$host" > /dev/null 2>&1; then
            echo "DNS resolved for $host after $((attempt * 10)) seconds"
            return 0
        fi
        if [ $((attempt % 6)) -eq 0 ]; then
            echo "Still waiting for $host... ($((attempt * 10 / 60)) minutes elapsed)"
        fi
        sleep 10
        attempt=$((attempt + 1))
    done
    
    echo "WARNING: DNS resolution failed for $host after $((max_attempts * 10 / 60)) minutes"
    return 1
}

# Parse DATAHUB_GMS_URL (format: https://uuid-8080.region.stg.rapu.app)
# This is provided by the service credential integration from GMS
if [ -n "$DATAHUB_GMS_URL" ]; then
    # Extract protocol
    GMS_PROTO="${DATAHUB_GMS_URL%%://*}"
    # Remove protocol prefix
    GMS_URL_NO_PROTO="${DATAHUB_GMS_URL#*://}"
    # Remove any path
    GMS_HOSTPORT="${GMS_URL_NO_PROTO%%/*}"
    
    # Extract host and port (handle case with and without explicit port)
    if [[ "$GMS_HOSTPORT" == *":"* ]]; then
        export DATAHUB_GMS_HOST="${GMS_HOSTPORT%%:*}"
        export DATAHUB_GMS_PORT="${GMS_HOSTPORT#*:}"
    else
        export DATAHUB_GMS_HOST="$GMS_HOSTPORT"
        # Default port based on protocol
        if [ "$GMS_PROTO" = "https" ]; then
            export DATAHUB_GMS_PORT="443"
        else
            export DATAHUB_GMS_PORT="80"
        fi
    fi
    export DATAHUB_GMS_PROTOCOL="$GMS_PROTO"
    
    echo "GMS configured from URL: protocol=$DATAHUB_GMS_PROTOCOL, host=$DATAHUB_GMS_HOST, port=$DATAHUB_GMS_PORT"
fi

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

# Wait for all dependencies to be DNS-resolvable before proceeding
echo "=== Waiting for dependencies ==="

# Wait for GMS
if [ -n "$DATAHUB_GMS_HOST" ]; then
    wait_for_dns "$DATAHUB_GMS_HOST" 120
fi

# Wait for OpenSearch
if [ -n "$ELASTIC_CLIENT_HOST" ]; then
    wait_for_dns "$ELASTIC_CLIENT_HOST" 120
fi

# Wait for Kafka
if [ -n "$KAFKA_BOOTSTRAP_SERVER" ]; then
    KAFKA_HOST="${KAFKA_BOOTSTRAP_SERVER%%:*}"
    wait_for_dns "$KAFKA_HOST" 120
fi

echo "=== All dependencies ready ==="

# Debug: print configured endpoints (without secrets)
echo "=== DataHub Frontend Configuration ==="
echo "GMS Host: ${DATAHUB_GMS_HOST:-NOT SET}:${DATAHUB_GMS_PORT:-NOT SET}"
echo "Kafka Bootstrap: ${KAFKA_BOOTSTRAP_SERVER:-NOT SET}"
echo "OpenSearch Host: ${ELASTIC_CLIENT_HOST:-NOT SET}:${ELASTIC_CLIENT_PORT:-NOT SET}"
echo "======================================"

# Execute the original entrypoint/command
exec "$@"
