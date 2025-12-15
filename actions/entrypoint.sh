#!/bin/bash
set -e

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
        if curl -sfk --max-time 5 "${gms_url}/config" > /dev/null 2>&1; then
            echo "GMS is ready at $gms_url"
            # Also wait for schema registry endpoint to be ready
            if curl -sfk --max-time 5 "${gms_url}/schema-registry/api/subjects" > /dev/null 2>&1; then
                echo "Schema registry is ready at ${gms_url}/schema-registry/api/"
                return 0
            else
                echo "GMS is ready but schema registry not yet available, waiting..."
            fi
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

# Parse DATAHUB_GMS_URL if provided (format: http://host:port or https://host:port)
# This overrides the Dockerfile defaults (gms:8080) when running externally
if [ -n "${DATAHUB_GMS_URL:-}" ]; then
    GMS_PROTO="${DATAHUB_GMS_URL%%://*}"
    GMS_URL_NO_PROTO="${DATAHUB_GMS_URL#*://}"
    GMS_HOSTPORT="${GMS_URL_NO_PROTO%%/*}"
    
    if [[ "$GMS_HOSTPORT" == *":"* ]]; then
        GMS_HOST="${GMS_HOSTPORT%%:*}"
        GMS_PORT="${GMS_HOSTPORT#*:}"
    else
        GMS_HOST="$GMS_HOSTPORT"
        if [ "$GMS_PROTO" = "https" ]; then
            GMS_PORT="443"
        else
            GMS_PORT="80"
        fi
    fi
    
    # Override the Dockerfile defaults
    export DATAHUB_GMS_HOST="$GMS_HOST"
    export DATAHUB_GMS_PORT="$GMS_PORT"
    export DATAHUB_GMS_PROTOCOL="$GMS_PROTO"
    
    # Update SCHEMA_REGISTRY_URL to use the parsed GMS URL
    export SCHEMA_REGISTRY_URL="${DATAHUB_GMS_URL}/schema-registry/api/"
    
    echo "Parsed GMS URL: DATAHUB_GMS_HOST=$DATAHUB_GMS_HOST, DATAHUB_GMS_PORT=$DATAHUB_GMS_PORT, DATAHUB_GMS_PROTOCOL=$DATAHUB_GMS_PROTOCOL"
    echo "Schema Registry URL: $SCHEMA_REGISTRY_URL"
fi

# Write Kafka SSL certificates to disk if provided
if [ -n "$KAFKA_ACCESS_CERT" ] && [ -n "$KAFKA_ACCESS_KEY" ] && [ -n "$KAFKA_CA_CERT" ]; then
    mkdir -p /etc/datahub/certs/kafka
    echo "$KAFKA_CA_CERT" > /etc/datahub/certs/kafka/ca.pem
    echo "$KAFKA_ACCESS_CERT" > /etc/datahub/certs/kafka/service.cert
    echo "$KAFKA_ACCESS_KEY" > /etc/datahub/certs/kafka/service.key
    chmod 644 /etc/datahub/certs/kafka/ca.pem /etc/datahub/certs/kafka/service.cert
    chmod 600 /etc/datahub/certs/kafka/service.key
    
    # Add consumer_config to executor.yaml if not present
    EXECUTOR_YAML="/etc/datahub/actions/system/conf/executor.yaml"
    if ! grep -q "consumer_config:" "$EXECUTOR_YAML"; then
        sed -i '/schema_registry_url:/a\      consumer_config:\n        security.protocol: ${KAFKA_PROPERTIES_SECURITY_PROTOCOL:-SSL}\n        ssl.endpoint.identification.algorithm: ${KAFKA_PROPERTIES_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM:-none}\n        ssl.ca.location: /etc/datahub/certs/kafka/ca.pem\n        ssl.certificate.location: /etc/datahub/certs/kafka/service.cert\n        ssl.key.location: /etc/datahub/certs/kafka/service.key' "$EXECUTOR_YAML"
    fi
fi

# Wait for dependencies
echo "=== Waiting for dependencies ==="

# Wait for GMS if DATAHUB_GMS_URL is set
if [ -n "${DATAHUB_GMS_URL:-}" ]; then
    wait_for_gms "$DATAHUB_GMS_URL" || echo "Continuing anyway..."
fi

# Wait for Kafka if KAFKA_BOOTSTRAP_SERVER is set
if [ -n "${KAFKA_BOOTSTRAP_SERVER:-}" ]; then
    KAFKA_HOST="${KAFKA_BOOTSTRAP_SERVER%%:*}"
    wait_for_dns "$KAFKA_HOST" || echo "Continuing anyway..."
fi

echo "=== All dependencies ready ==="

# Ensure system client credentials are exported for ingestion subprocesses
# The Python ingestion client reads these from environment variables
if [ -n "${DATAHUB_SYSTEM_CLIENT_ID:-}" ]; then
    export DATAHUB_SYSTEM_CLIENT_ID
    echo "DATAHUB_SYSTEM_CLIENT_ID exported: ${DATAHUB_SYSTEM_CLIENT_ID}"
else
    # Default to __datahub_system if not set
    export DATAHUB_SYSTEM_CLIENT_ID="__datahub_system"
    echo "DATAHUB_SYSTEM_CLIENT_ID defaulted to: __datahub_system"
fi

if [ -n "${DATAHUB_SYSTEM_CLIENT_SECRET:-}" ]; then
    export DATAHUB_SYSTEM_CLIENT_SECRET
    echo "DATAHUB_SYSTEM_CLIENT_SECRET exported: [REDACTED]"
else
    echo "WARNING: DATAHUB_SYSTEM_CLIENT_SECRET is not set - ingestion may fail with 401 Unauthorized"
fi

# Also export GMS URL variables for the Python client
if [ -n "${DATAHUB_GMS_URL:-}" ]; then
    export DATAHUB_GMS_URL
    echo "DATAHUB_GMS_URL exported: ${DATAHUB_GMS_URL}"
fi

exec "$@"
