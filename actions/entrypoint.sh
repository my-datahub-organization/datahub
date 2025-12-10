#!/bin/bash
# Entrypoint script for DataHub Actions
# Maps environment variable names to expected format

set -e

echo "=== DataHub Actions Entrypoint Starting ==="

# Require DATAHUB_GMS_URL - must be set manually
if [ -z "$DATAHUB_GMS_URL" ]; then
    echo "ERROR: DATAHUB_GMS_URL is required but not set"
    echo "Please set DATAHUB_GMS_URL to the GMS service URL (e.g., http://gms-host:8080)"
    exit 1
fi

echo "DATAHUB_GMS_URL: $DATAHUB_GMS_URL"
echo "KAFKA_BOOTSTRAP_SERVER: ${KAFKA_BOOTSTRAP_SERVER:-NOT SET}"

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
export SCHEMA_REGISTRY_URL="${DATAHUB_GMS_URL}/schema-registry/api/"

echo "GMS: $DATAHUB_GMS_PROTOCOL://$DATAHUB_GMS_HOST:$DATAHUB_GMS_PORT"

# Setup Kafka SSL certificates for mTLS
if [ -n "$KAFKA_ACCESS_CERT" ] && [ -n "$KAFKA_ACCESS_KEY" ] && [ -n "$KAFKA_CA_CERT" ]; then
    echo "Setting up Kafka SSL certificates..."
    
    CERTS_DIR="/tmp/certs"
    mkdir -p "$CERTS_DIR"
    chmod 700 "$CERTS_DIR"
    
    # Write certificates to files
    echo "$KAFKA_ACCESS_CERT" > "$CERTS_DIR/kafka-client.crt"
    echo "$KAFKA_ACCESS_KEY" > "$CERTS_DIR/kafka-client.key"
    echo "$KAFKA_CA_CERT" > "$CERTS_DIR/kafka-ca.crt"
    
    # Set proper permissions
    chmod 644 "$CERTS_DIR/kafka-client.crt" "$CERTS_DIR/kafka-ca.crt"
    chmod 600 "$CERTS_DIR/kafka-client.key"
    
    # Create PKCS12 keystore from certificate and key
    KEYSTORE_PATH="/tmp/kafka-client-keystore.p12"
    KEYSTORE_PASS="changeit"
    
    openssl pkcs12 -export \
        -in "$CERTS_DIR/kafka-client.crt" \
        -inkey "$CERTS_DIR/kafka-client.key" \
        -out "$KEYSTORE_PATH" \
        -name kafka-client \
        -passout pass:"$KEYSTORE_PASS" 2>&1 || {
        echo "ERROR: Failed to create keystore"
        exit 1
    }
    chmod 600 "$KEYSTORE_PATH"
    export KAFKA_PROPERTIES_SSL_KEYSTORE_LOCATION="$KEYSTORE_PATH"
    export KAFKA_PROPERTIES_SSL_KEYSTORE_PASSWORD="$KEYSTORE_PASS"
    
    # Create JKS truststore from CA certificate
    TRUSTSTORE_PATH="/tmp/kafka-truststore.jks"
    TRUSTSTORE_PASS="changeit"
    
    rm -f "$TRUSTSTORE_PATH"
    keytool -import -trustcacerts -keystore "$TRUSTSTORE_PATH" -storepass "$TRUSTSTORE_PASS" \
        -noprompt -alias "kafka-ca" -file "$CERTS_DIR/kafka-ca.crt" 2>&1 || {
        echo "ERROR: Failed to create truststore"
        exit 1
    }
    export KAFKA_PROPERTIES_SSL_TRUSTSTORE_LOCATION="$TRUSTSTORE_PATH"
    export KAFKA_PROPERTIES_SSL_TRUSTSTORE_PASSWORD="$TRUSTSTORE_PASS"
    
    echo "Kafka certificates configured for mTLS"
    echo "Keystore: $KAFKA_PROPERTIES_SSL_KEYSTORE_LOCATION"
    echo "Truststore: $KAFKA_PROPERTIES_SSL_TRUSTSTORE_LOCATION"
fi

# Kafka configuration
if [ -n "$KAFKA_BOOTSTRAP_SERVER" ]; then
    echo "Kafka: $KAFKA_BOOTSTRAP_SERVER (mTLS)"
fi

# Set system client ID if not provided (defaults to __datahub_system)
if [ -z "$DATAHUB_SYSTEM_CLIENT_ID" ]; then
    export DATAHUB_SYSTEM_CLIENT_ID="__datahub_system"
    echo "Using default DATAHUB_SYSTEM_CLIENT_ID: __datahub_system"
fi

# Set system client secret if not provided (must match across all services)
# Uses DATAHUB_SECRET as fallback since it's already shared across services
if [ -z "$DATAHUB_SYSTEM_CLIENT_SECRET" ]; then
    if [ -z "$DATAHUB_SECRET" ]; then
        echo "ERROR: DATAHUB_SYSTEM_CLIENT_SECRET or DATAHUB_SECRET must be set"
        echo "The system client secret must be shared across all services (frontend, gms, actions)"
        exit 1
    fi
    export DATAHUB_SYSTEM_CLIENT_SECRET="$DATAHUB_SECRET"
    echo "Using DATAHUB_SECRET as DATAHUB_SYSTEM_CLIENT_SECRET (shared across services)"
fi

# Wait for all dependencies to be DNS-resolvable before proceeding
echo "=== Waiting for dependencies ==="

# Wait for GMS to be ready
wait_for_gms "$DATAHUB_GMS_URL" || echo "Continuing anyway..."

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

