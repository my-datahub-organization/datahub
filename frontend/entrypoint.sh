#!/bin/bash
# Entrypoint script for DataHub Frontend
# Parses connection string environment variables into component variables

set -e

echo "=== DataHub Frontend Entrypoint Starting ==="

# Show memory information
echo "=== Memory Information ==="
if [ -f /proc/meminfo ]; then
    echo "Total Memory: $(grep MemTotal /proc/meminfo | awk '{print $2 / 1024 " MB"}')"
    echo "Available Memory: $(grep MemAvailable /proc/meminfo | awk '{print $2 / 1024 " MB"}')"
    echo "Free Memory: $(grep MemFree /proc/meminfo | awk '{print $2 / 1024 " MB"}')"
else
    echo "Memory info not available (/proc/meminfo not found)"
fi
echo "==========================="

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

# Setup Kafka SSL certificates for mTLS
if [ -n "$KAFKA_ACCESS_CERT" ] && [ -n "$KAFKA_ACCESS_KEY" ] && [ -n "$KAFKA_CA_CERT" ]; then
    CERTS_DIR="/tmp/certs"
    mkdir -p "$CERTS_DIR"
    chmod 700 "$CERTS_DIR"
    
    echo "Setting up Kafka SSL certificates..."
    echo "$KAFKA_ACCESS_CERT" > "$CERTS_DIR/kafka-client.crt"
    echo "$KAFKA_ACCESS_KEY" > "$CERTS_DIR/kafka-client.key"
    echo "$KAFKA_CA_CERT" > "$CERTS_DIR/kafka-ca.crt"
    chmod 600 "$CERTS_DIR/kafka-client.key"
    
    # Create PKCS12 keystore
    KEYSTORE_PATH="/tmp/kafka-client-keystore.p12"
    KEYSTORE_PASS="changeit"
    openssl pkcs12 -export -in "$CERTS_DIR/kafka-client.crt" -inkey "$CERTS_DIR/kafka-client.key" \
        -out "$KEYSTORE_PATH" -name kafka-client -passout "pass:$KEYSTORE_PASS" 2>&1 || {
        echo "ERROR: Failed to create keystore"
        exit 1
    }
    export KAFKA_PROPERTIES_SSL_KEYSTORE_LOCATION="$KEYSTORE_PATH"
    export KAFKA_PROPERTIES_SSL_KEYSTORE_PASSWORD="$KEYSTORE_PASS"
    export KAFKA_PROPERTIES_SSL_KEY_PASSWORD="$KEYSTORE_PASS"
    
    # Create JKS truststore
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

# Set JAVA_OPTS for Play Framework (similar to original start.sh)
export JAVA_OPTS="${JAVA_MEMORY_OPTS:--Xms512m -Xmx1024m} \
   -Dhttp.port=9002 \
   -Dconfig.file=datahub-frontend/conf/application.conf \
   -Djava.security.auth.login.config=datahub-frontend/conf/jaas.conf \
   -Dlogback.configurationFile=datahub-frontend/conf/logback.xml \
   -Dlogback.debug=false \
   -Dpidfile.path=/dev/null"

echo "Starting DataHub Frontend..."
# Execute datahub-frontend directly
exec /datahub-frontend/bin/datahub-frontend
