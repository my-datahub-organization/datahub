#!/bin/bash
# Entrypoint script for DataHub GMS
# Parses connection string environment variables into component variables

set -e

# Change to a writable directory - Ebean tries to write DDL files to ./
cd /tmp

echo "=== GMS Entrypoint Starting ==="

# Display memory information
echo "=== Container Memory Information ==="
if [ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
    MEMORY_LIMIT=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)
    MEMORY_LIMIT_GB=$(echo "scale=2; $MEMORY_LIMIT / 1024 / 1024 / 1024" | bc)
    echo "Memory limit (cgroup v1): ${MEMORY_LIMIT_GB} GB (${MEMORY_LIMIT} bytes)"
elif [ -f /sys/fs/cgroup/memory.max ]; then
    MEMORY_LIMIT=$(cat /sys/fs/cgroup/memory.max)
    if [ "$MEMORY_LIMIT" = "max" ]; then
        echo "Memory limit (cgroup v2): unlimited"
    else
        MEMORY_LIMIT_GB=$(echo "scale=2; $MEMORY_LIMIT / 1024 / 1024 / 1024" | bc)
        echo "Memory limit (cgroup v2): ${MEMORY_LIMIT_GB} GB (${MEMORY_LIMIT} bytes)"
    fi
else
    echo "Memory limit: Unable to detect (cgroup not available)"
fi

# Display total system memory
if [ -f /proc/meminfo ]; then
    TOTAL_MEM=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_MEM_GB=$(echo "scale=2; $TOTAL_MEM / 1024 / 1024" | bc)
    FREE_MEM=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    FREE_MEM_GB=$(echo "scale=2; $FREE_MEM / 1024 / 1024" | bc)
    echo "System total memory: ${TOTAL_MEM_GB} GB"
    echo "System available memory: ${FREE_MEM_GB} GB"
fi

# Display JVM memory settings
echo "JVM memory settings (JAVA_OPTS): $JAVA_OPTS"
echo "===================================="
echo ""

# Check for all required environment variables
# These are populated by service integrations - if not set, the data services aren't ready
check_required_env_vars() {
    local missing=""
    
    [ -z "$DATABASE_URL" ] && missing="$missing DATABASE_URL"
    [ -z "$OPENSEARCH_URI" ] && missing="$missing OPENSEARCH_URI"
    [ -z "$KAFKA_BOOTSTRAP_SERVER" ] && missing="$missing KAFKA_BOOTSTRAP_SERVER"
    [ -z "$KAFKA_ACCESS_CERT" ] && missing="$missing KAFKA_ACCESS_CERT"
    [ -z "$KAFKA_ACCESS_KEY" ] && missing="$missing KAFKA_ACCESS_KEY"
    [ -z "$KAFKA_CA_CERT" ] && missing="$missing KAFKA_CA_CERT"
    
    if [ -n "$missing" ]; then
        echo "=============================================="
        echo "ERROR: Required environment variables missing:"
        echo " $missing"
        echo "=============================================="
        echo ""
        echo "The data services (PostgreSQL, Kafka, OpenSearch) may still be starting."
        echo "Their service_uri is not yet available for the credential integration."
        echo ""
        echo "Sleeping for 60 seconds before exiting..."
        echo "The container will restart and re-resolve environment variables."
        sleep 60
        return 1
    fi
    
    echo "All required environment variables are set!"
    return 0
}

# Check environment variables - exit if missing (container will restart)
if ! check_required_env_vars; then
    exit 1
fi

# Debug: show what env vars we received from integrations
echo "DEBUG: Environment variables from integrations:"
echo "  DATABASE_URL set: $([ -n "$DATABASE_URL" ] && echo 'YES' || echo 'NO')"
echo "  OPENSEARCH_URI set: $([ -n "$OPENSEARCH_URI" ] && echo 'YES' || echo 'NO')"
echo "  KAFKA_BOOTSTRAP_SERVER set: $([ -n "$KAFKA_BOOTSTRAP_SERVER" ] && echo 'YES' || echo 'NO')"
echo "  KAFKA_ACCESS_CERT set: $([ -n "$KAFKA_ACCESS_CERT" ] && echo 'YES' || echo 'NO')"
echo "  KAFKA_ACCESS_KEY set: $([ -n "$KAFKA_ACCESS_KEY" ] && echo 'YES' || echo 'NO')"
echo "  KAFKA_CA_CERT set: $([ -n "$KAFKA_CA_CERT" ] && echo 'YES' || echo 'NO')"
echo ""
echo "=== Authentication Configuration Debug ==="
echo "DATAHUB_SECRET is set: $([ -n "$DATAHUB_SECRET" ] && echo 'YES' || echo 'NO')"
if [ -n "$DATAHUB_SECRET" ]; then
    echo "DATAHUB_SECRET value: ...${DATAHUB_SECRET: -3} (last 3 chars)"
else
    echo "ERROR: DATAHUB_SECRET is NOT SET - this will cause authentication failures!"
fi
echo "METADATA_SERVICE_AUTH_ENABLED='${METADATA_SERVICE_AUTH_ENABLED:-NOT SET}'"
if [ "${METADATA_SERVICE_AUTH_ENABLED:-false}" != "false" ]; then
    echo "WARNING: METADATA_SERVICE_AUTH_ENABLED is not 'false' - current value: '${METADATA_SERVICE_AUTH_ENABLED}'"
else
    echo "✓ METADATA_SERVICE_AUTH_ENABLED is correctly set to 'false'"
fi
echo "AUTH_NATIVE_ENABLED='${AUTH_NATIVE_ENABLED:-NOT SET}'"
echo "AUTH_GUEST_ENABLED='${AUTH_GUEST_ENABLED:-NOT SET}'"
echo "========================================="
echo ""

# Function to write certificates to disk
setup_certificates() {
    local certs_dir="/tmp/certs"
    mkdir -p "$certs_dir"
    chmod 700 "$certs_dir"
    
    echo "=== Setting up Kafka SSL/TLS certificates ==="
    
    # Write Kafka client certificate
    echo "$KAFKA_ACCESS_CERT" > "$certs_dir/kafka-client.crt"
    chmod 600 "$certs_dir/kafka-client.crt"
    echo "Wrote Kafka client certificate to $certs_dir/kafka-client.crt"
    
    # Write Kafka client private key
    echo "$KAFKA_ACCESS_KEY" > "$certs_dir/kafka-client.key"
    chmod 600 "$certs_dir/kafka-client.key"
    echo "Wrote Kafka client private key to $certs_dir/kafka-client.key"
    
    # Write Kafka CA certificate
    echo "$KAFKA_CA_CERT" > "$certs_dir/kafka-ca.crt"
    chmod 644 "$certs_dir/kafka-ca.crt"
    echo "Wrote Kafka CA certificate to $certs_dir/kafka-ca.crt"
    
    echo "Certificate setup complete"
}

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

# Parse DATABASE_URL (format: postgres://user:pass@host:port/dbname?sslmode=require)
if [ -n "$DATABASE_URL" ]; then
    DB_URL_NO_PROTO="${DATABASE_URL#*://}"
    DB_USERPASS="${DB_URL_NO_PROTO%%@*}"
    export EBEAN_DATASOURCE_USERNAME="${DB_USERPASS%%:*}"
    export EBEAN_DATASOURCE_PASSWORD="${DB_USERPASS#*:}"
    DB_HOSTPATH="${DB_URL_NO_PROTO#*@}"
    DB_HOSTPORT="${DB_HOSTPATH%%/*}"
    export EBEAN_DATASOURCE_HOST="$DB_HOSTPORT"
    DB_DBNAME_QUERY="${DB_HOSTPATH#*/}"
    DB_DBNAME="${DB_DBNAME_QUERY%%\?*}"
    export EBEAN_DATASOURCE_URL="jdbc:postgresql://${DB_HOSTPORT}/${DB_DBNAME}?sslmode=require"
    echo "PostgreSQL: $EBEAN_DATASOURCE_HOST"
fi

# Parse OPENSEARCH_URI (format: https://user:pass@host:port)
if [ -n "$OPENSEARCH_URI" ]; then
    echo "DEBUG: Parsing OPENSEARCH_URI..."
    
    # Get protocol (https or http)
    OS_PROTO="${OPENSEARCH_URI%%://*}"
    OS_URL_NO_PROTO="${OPENSEARCH_URI#*://}"
    OS_USERPASS="${OS_URL_NO_PROTO%%@*}"
    export ELASTICSEARCH_USERNAME="${OS_USERPASS%%:*}"
    export ELASTICSEARCH_PASSWORD="${OS_USERPASS#*:}"
    OS_HOSTPORT="${OS_URL_NO_PROTO#*@}"
    export ELASTICSEARCH_HOST="${OS_HOSTPORT%%:*}"
    export ELASTICSEARCH_PORT="${OS_HOSTPORT#*:}"
    
    # Enable SSL if using https
    if [ "$OS_PROTO" = "https" ]; then
        export ELASTICSEARCH_USE_SSL="true"
        export ELASTICSEARCH_SSL_PROTOCOL="TLSv1.2"
    fi
    
    echo "DEBUG: ELASTICSEARCH_HOST='$ELASTICSEARCH_HOST'"
    echo "DEBUG: ELASTICSEARCH_PORT='$ELASTICSEARCH_PORT'"
    echo "DEBUG: ELASTICSEARCH_USERNAME='$ELASTICSEARCH_USERNAME'"
    echo "DEBUG: ELASTICSEARCH_USE_SSL='$ELASTICSEARCH_USE_SSL'"
    echo "OpenSearch: $ELASTICSEARCH_HOST:$ELASTICSEARCH_PORT (SSL: ${ELASTICSEARCH_USE_SSL:-false})"
else
    echo "WARNING: OPENSEARCH_URI is not set!"
fi

# Setup certificates on disk
setup_certificates

# Wait for all dependencies to be DNS-resolvable before proceeding
echo "=== Waiting for dependencies (all must resolve) ==="

DNS_FAILED=0

# Wait for PostgreSQL
if [ -n "$EBEAN_DATASOURCE_HOST" ]; then
    PG_HOST="${EBEAN_DATASOURCE_HOST%%:*}"
    if ! wait_for_dns "$PG_HOST"; then
        echo "ERROR: PostgreSQL DNS resolution failed!"
        DNS_FAILED=1
    fi
else
    echo "ERROR: PostgreSQL host not configured!"
    DNS_FAILED=1
fi

# Wait for OpenSearch
if [ -n "$ELASTICSEARCH_HOST" ]; then
    if ! wait_for_dns "$ELASTICSEARCH_HOST"; then
        echo "ERROR: OpenSearch DNS resolution failed!"
        DNS_FAILED=1
    fi
else
    echo "ERROR: OpenSearch host not configured!"
    DNS_FAILED=1
fi

# Wait for Kafka
echo "DEBUG: KAFKA_BOOTSTRAP_SERVER='$KAFKA_BOOTSTRAP_SERVER'"
if [ -n "$KAFKA_BOOTSTRAP_SERVER" ]; then
    KAFKA_HOST="${KAFKA_BOOTSTRAP_SERVER%%:*}"
    echo "DEBUG: Extracted KAFKA_HOST='$KAFKA_HOST'"
    if ! wait_for_dns "$KAFKA_HOST"; then
        echo "ERROR: Kafka DNS resolution failed!"
        DNS_FAILED=1
    fi
else
    echo "ERROR: Kafka host not configured!"
    DNS_FAILED=1
fi

# Exit if any DNS resolution failed
if [ $DNS_FAILED -eq 1 ]; then
    echo "=============================================="
    echo "ERROR: One or more required services are not reachable!"
    echo "=============================================="
    echo "Sleeping for 60 seconds before exiting..."
    echo "The container will restart and retry."
    sleep 60
    exit 1
fi

echo "=== All dependencies ready ==="

# Kafka SSL Configuration - use certificate-based authentication (mTLS)
if [ -n "$KAFKA_BOOTSTRAP_SERVER" ]; then
    echo "=== Setting up Kafka SSL configuration ==="
    CERTS_DIR="/tmp/certs"
    
    # Create a PKCS12 keystore from the client certificate and key
    KEYSTORE_PATH="/tmp/kafka-client-keystore.p12"
    KEYSTORE_PASS="changeit"
    
    echo "Creating PKCS12 keystore from client certificate and key..."
    openssl pkcs12 -export \
        -in "$CERTS_DIR/kafka-client.crt" \
        -inkey "$CERTS_DIR/kafka-client.key" \
        -out "$KEYSTORE_PATH" \
        -name kafka-client \
        -passout "pass:$KEYSTORE_PASS" 2>&1 || {
        echo "ERROR: Failed to create keystore"
        exit 1
    }
    
    if [ -f "$KEYSTORE_PATH" ]; then
        echo "Keystore created at $KEYSTORE_PATH"
        export SPRING_KAFKA_PROPERTIES_SSL_KEYSTORE_LOCATION="$KEYSTORE_PATH"
        export SPRING_KAFKA_PROPERTIES_SSL_KEYSTORE_PASSWORD="$KEYSTORE_PASS"
        export SPRING_KAFKA_PROPERTIES_SSL_KEY_PASSWORD="$KEYSTORE_PASS"
    else
        echo "ERROR: Failed to create keystore"
        exit 1
    fi
    
    # Create truststore from CA certificate
    TRUSTSTORE_PATH="/tmp/kafka-truststore.jks"
    TRUSTSTORE_PASS="changeit"
    
    rm -f "$TRUSTSTORE_PATH"
    
    echo "Importing Kafka CA certificate into truststore..."
    keytool -import -trustcacerts \
        -keystore "$TRUSTSTORE_PATH" \
        -storepass "$TRUSTSTORE_PASS" \
        -noprompt \
        -alias "kafka-ca" \
        -file "$CERTS_DIR/kafka-ca.crt" 2>&1 || {
        echo "ERROR: Failed to import CA certificate"
        exit 1
    }
    
    if [ -f "$TRUSTSTORE_PATH" ]; then
        echo "Truststore created at $TRUSTSTORE_PATH"
        ls -la "$TRUSTSTORE_PATH"
        echo "DEBUG: Truststore contents:"
        keytool -list -keystore "$TRUSTSTORE_PATH" -storepass "$TRUSTSTORE_PASS" 2>&1 | head -15
        export SPRING_KAFKA_PROPERTIES_SSL_TRUSTSTORE_LOCATION="$TRUSTSTORE_PATH"
        export SPRING_KAFKA_PROPERTIES_SSL_TRUSTSTORE_PASSWORD="$TRUSTSTORE_PASS"
    else
        echo "ERROR: Failed to create truststore"
        exit 1
    fi
    
    echo "Kafka: $KAFKA_BOOTSTRAP_SERVER (mTLS)"
fi

# Configure Schema Registry to use GMS's built-in endpoint
# GMS has a built-in schema registry at /schema-registry/api/
# We'll set this to point to localhost (GMS itself) once it starts
if [ -z "$KAFKA_SCHEMAREGISTRY_URL" ]; then
    # Use GMS's built-in schema registry endpoint
    export KAFKA_SCHEMAREGISTRY_URL="http://localhost:8080/schema-registry/api/"
    echo "Schema Registry: Using GMS's built-in endpoint at $KAFKA_SCHEMAREGISTRY_URL"
else
    echo "Schema Registry: Using configured URL: $KAFKA_SCHEMAREGISTRY_URL"
fi


echo "=== Configuration Complete ==="
echo ""
echo "=== Final Authentication Check ==="
if [ -n "$DATAHUB_SECRET" ] && [ "${METADATA_SERVICE_AUTH_ENABLED:-false}" = "false" ]; then
    echo "✓ Authentication configuration is correct:"
    echo "  - DATAHUB_SECRET is set"
    echo "  - METADATA_SERVICE_AUTH_ENABLED=false"
else
    echo "✗ Authentication configuration issue detected:"
    [ -z "$DATAHUB_SECRET" ] && echo "  - DATAHUB_SECRET is NOT SET"
    [ "${METADATA_SERVICE_AUTH_ENABLED:-false}" != "false" ] && echo "  - METADATA_SERVICE_AUTH_ENABLED is '${METADATA_SERVICE_AUTH_ENABLED:-NOT SET}' (should be 'false')"
fi
echo "=================================="
echo ""

# Execute the original entrypoint/command
exec "$@"
