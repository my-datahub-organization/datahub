#!/bin/bash
# Entrypoint script for DataHub Frontend
# Parses connection string environment variables into component variables

set -e

echo "=== DataHub Frontend Entrypoint Starting ==="

# Debug: show all DATAHUB_* environment variables
echo "=== Environment Variables Debug ==="
echo "DATAHUB_GMS_URL='$DATAHUB_GMS_URL'"
echo "DATAHUB_GMS_HOST='$DATAHUB_GMS_HOST'"
echo "DATAHUB_GMS_PORT='$DATAHUB_GMS_PORT'"
echo "DATAHUB_SECRET is set: $([ -n "$DATAHUB_SECRET" ] && echo 'YES' || echo 'NO')"
echo "KAFKA_BOOTSTRAP_SERVER='$KAFKA_BOOTSTRAP_SERVER'"
echo "OPENSEARCH_URI is set: $([ -n "$OPENSEARCH_URI" ] && echo 'YES' || echo 'NO')"
echo "==================================="

# Require DATAHUB_GMS_URL - must be set manually
if [ -z "$DATAHUB_GMS_URL" ]; then
    echo "ERROR: DATAHUB_GMS_URL is required but not set (value is empty or unset)"
    echo "Please set DATAHUB_GMS_URL to the GMS service URL (e.g., http://gms-host:8080)"
    exit 1
fi

# Function to wait for DNS resolution of a host
# Default: 40 attempts * 30 seconds = 20 minutes max wait
wait_for_dns() {
    local host="$1"
    local max_attempts="${2:-40}"
    local attempt=1
    
    echo "Waiting for DNS resolution of $host (max wait: $((max_attempts * 30 / 60)) minutes)..."
    while [ $attempt -le $max_attempts ]; do
        if getent hosts "$host" > /dev/null 2>&1; then
            echo "DNS resolved for $host after $((attempt * 30)) seconds"
            return 0
        fi
        if [ $((attempt % 2)) -eq 0 ]; then
            echo "Still waiting for $host... ($((attempt * 30 / 60)) minutes elapsed)"
        fi
        sleep 30
        attempt=$((attempt + 1))
    done
    
    echo "WARNING: DNS resolution failed for $host after $((max_attempts * 30 / 60)) minutes"
    return 1
}

# Function to wait for GMS to be ready (HTTP endpoint responding)
wait_for_gms() {
    local gms_url="$1"
    local max_attempts="${2:-40}"
    local attempt=1
    
    echo "Waiting for GMS at $gms_url (max wait: $((max_attempts * 30 / 60)) minutes)..."
    while [ $attempt -le $max_attempts ]; do
        if curl -sf --max-time 5 "${gms_url}/config" > /dev/null 2>&1; then
            echo "GMS is ready at $gms_url"
            return 0
        fi
        if [ $((attempt % 2)) -eq 0 ]; then
            echo "Still waiting for GMS... ($((attempt * 30 / 60)) minutes elapsed)"
        fi
        sleep 30
        attempt=$((attempt + 1))
    done
    
    echo "WARNING: GMS not ready after $((max_attempts * 30 / 60)) minutes"
    return 1
}

# Parse DATAHUB_GMS_URL (format: http://host:port or https://host:port)
GMS_PROTO="${DATAHUB_GMS_URL%%://*}"
GMS_URL_NO_PROTO="${DATAHUB_GMS_URL#*://}"
GMS_HOSTPORT="${GMS_URL_NO_PROTO%%/*}"

if [[ "$GMS_HOSTPORT" == *":"* ]]; then
    export DATAHUB_GMS_HOST="${GMS_HOSTPORT%%:*}"
    export DATAHUB_GMS_PORT="${GMS_HOSTPORT#*:}"
else
    export DATAHUB_GMS_HOST="$GMS_HOSTPORT"
    if [ "$GMS_PROTO" = "https" ]; then
        export DATAHUB_GMS_PORT="443"
    else
        export DATAHUB_GMS_PORT="80"
    fi
fi
export DATAHUB_GMS_PROTOCOL="$GMS_PROTO"

echo "GMS: $DATAHUB_GMS_PROTOCOL://$DATAHUB_GMS_HOST:$DATAHUB_GMS_PORT"

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

# Wait for GMS to be ready
wait_for_gms "$DATAHUB_GMS_URL" || echo "Continuing anyway..."

# Wait for OpenSearch
if [ -n "$ELASTIC_CLIENT_HOST" ]; then
    wait_for_dns "$ELASTIC_CLIENT_HOST" || echo "Continuing anyway..."
fi

# Wait for Kafka
if [ -n "$KAFKA_BOOTSTRAP_SERVER" ]; then
    KAFKA_HOST="${KAFKA_BOOTSTRAP_SERVER%%:*}"
    wait_for_dns "$KAFKA_HOST" || echo "Continuing anyway..."
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
