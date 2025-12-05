#!/bin/bash
# Entrypoint script for DataHub Actions
# Maps environment variable names to expected format

set -e

echo "=== DataHub Actions Entrypoint Starting ==="

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
    
    # Also set SCHEMA_REGISTRY_URL based on GMS URL
    export SCHEMA_REGISTRY_URL="${DATAHUB_GMS_URL}/schema-registry/api/"
    
    echo "GMS configured from URL: protocol=$DATAHUB_GMS_PROTOCOL, host=$DATAHUB_GMS_HOST, port=$DATAHUB_GMS_PORT"
elif [ -n "$GMS_SERVICE_NAME" ]; then
    # Fallback: try to reach GMS using internal service name
    echo "DATAHUB_GMS_URL not set, trying to discover GMS via service name: $GMS_SERVICE_NAME"
    
    # Try internal service name with port 8080 (GMS default)
    for gms_candidate in "${GMS_SERVICE_NAME}:8080" "${GMS_SERVICE_NAME}.default.svc.cluster.local:8080"; do
        echo "Trying GMS at $gms_candidate..."
        if curl -sf --max-time 5 "http://${gms_candidate}/config" > /dev/null 2>&1; then
            export DATAHUB_GMS_HOST="${gms_candidate%%:*}"
            export DATAHUB_GMS_PORT="${gms_candidate#*:}"
            export DATAHUB_GMS_PROTOCOL="http"
            export SCHEMA_REGISTRY_URL="http://${gms_candidate}/schema-registry/api/"
            echo "GMS discovered at $gms_candidate"
            break
        fi
    done
    
    if [ -z "$DATAHUB_GMS_HOST" ]; then
        echo "WARNING: Could not discover GMS, using defaults"
    fi
fi

# Actions uses KAFKA_PROPERTIES_SASL_USERNAME/PASSWORD directly
# Map from generic names
if [ -n "$KAFKA_SASL_USERNAME" ]; then
    export KAFKA_PROPERTIES_SASL_USERNAME="$KAFKA_SASL_USERNAME"
fi
if [ -n "$KAFKA_SASL_PASSWORD" ]; then
    export KAFKA_PROPERTIES_SASL_PASSWORD="$KAFKA_SASL_PASSWORD"
fi

# Generate system client secret if not provided (used for GMS authentication)
if [ -z "$DATAHUB_SYSTEM_CLIENT_SECRET" ]; then
    export DATAHUB_SYSTEM_CLIENT_SECRET="${DATAHUB_SECRET:-$(openssl rand -hex 32)}"
    echo "Generated DATAHUB_SYSTEM_CLIENT_SECRET"
fi

# Wait for all dependencies to be DNS-resolvable before proceeding
echo "=== Waiting for dependencies ==="

# Wait for GMS to be ready (not just DNS, but actual HTTP response)
if [ -n "$DATAHUB_GMS_HOST" ] && [ "$DATAHUB_GMS_HOST" != "host.docker.internal" ]; then
    GMS_URL="${DATAHUB_GMS_PROTOCOL:-http}://${DATAHUB_GMS_HOST}:${DATAHUB_GMS_PORT:-8080}"
    wait_for_gms "$GMS_URL" || echo "Continuing anyway..."
fi

# Wait for Kafka
if [ -n "$KAFKA_BOOTSTRAP_SERVER" ]; then
    KAFKA_HOST="${KAFKA_BOOTSTRAP_SERVER%%:*}"
    wait_for_dns "$KAFKA_HOST" || echo "Continuing anyway..."
fi

echo "=== All dependencies ready ==="

# Debug: print configured endpoints (without secrets)
echo "GMS: ${DATAHUB_GMS_HOST:-NOT SET}:${DATAHUB_GMS_PORT:-NOT SET}"
echo "Kafka: ${KAFKA_BOOTSTRAP_SERVER:-NOT SET}"
echo "Schema Registry: ${SCHEMA_REGISTRY_URL:-NOT SET}"

# Execute the original command
exec "$@"

