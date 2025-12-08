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
    [ -z "$KAFKA_SASL_USERNAME" ] && missing="$missing KAFKA_SASL_USERNAME"
    [ -z "$KAFKA_SASL_PASSWORD" ] && missing="$missing KAFKA_SASL_PASSWORD"
    
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
echo "  KAFKA_SASL_USERNAME set: $([ -n "$KAFKA_SASL_USERNAME" ] && echo 'YES' || echo 'NO')"

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
    echo "DEBUG: OPENSEARCH_URI='$OPENSEARCH_URI'"
    
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

# Build Kafka SASL JAAS config
if [ -n "$KAFKA_SASL_USERNAME" ] && [ -n "$KAFKA_SASL_PASSWORD" ]; then
    export SPRING_KAFKA_PROPERTIES_SASL_JAAS_CONFIG="org.apache.kafka.common.security.plain.PlainLoginModule required username=\"$KAFKA_SASL_USERNAME\" password=\"$KAFKA_SASL_PASSWORD\";"
    echo "Kafka SASL: user=$KAFKA_SASL_USERNAME"
fi

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

# Kafka SSL Configuration - fetch and import Aiven's CA certificate
if [ -n "$KAFKA_BOOTSTRAP_SERVER" ]; then
    KAFKA_HOST="${KAFKA_BOOTSTRAP_SERVER%%:*}"
    KAFKA_PORT="${KAFKA_BOOTSTRAP_SERVER#*:}"
    
    echo "=== Setting up Kafka SSL truststore ==="
    TRUSTSTORE_PATH="/tmp/kafka-truststore.jks"
    TRUSTSTORE_PASS="changeit"
    
    # Check if required tools are available
    echo "DEBUG: Checking for required tools..."
    which openssl && echo "  openssl: $(openssl version)" || echo "  openssl: NOT FOUND"
    which keytool && echo "  keytool: found" || echo "  keytool: NOT FOUND"
    which timeout && echo "  timeout: found" || echo "  timeout: NOT FOUND"
    
    # Fetch the full certificate chain from the Kafka server
    echo "Fetching certificate chain from $KAFKA_HOST:$KAFKA_PORT..."
    
    # Get the full certificate chain with -showcerts
    echo "DEBUG: Running openssl s_client..."
    echo | openssl s_client -connect "$KAFKA_HOST:$KAFKA_PORT" -servername "$KAFKA_HOST" -showcerts </dev/null 2>&1 > /tmp/openssl-output.txt
    
    # Extract all certificates from the chain into separate files
    awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' /tmp/openssl-output.txt > /tmp/kafka-all-certs.pem
    
    if [ -s /tmp/kafka-all-certs.pem ]; then
        echo "DEBUG: Certificate chain fetched, size: $(wc -c < /tmp/kafka-all-certs.pem) bytes"
        
        # Count certificates in the chain
        CERT_COUNT=$(grep -c "BEGIN CERTIFICATE" /tmp/kafka-all-certs.pem || echo "0")
        echo "DEBUG: Found $CERT_COUNT certificate(s) in the chain"
        
        # Create truststore
        rm -f "$TRUSTSTORE_PATH"
        
        # Import each certificate from the chain
        # We use awk to split certificates and import each one
        ALIAS_NUM=0
        awk '/-----BEGIN CERTIFICATE-----/{f=1; n++} f{print > "/tmp/cert-"n".pem"} /-----END CERTIFICATE-----/{f=0}' /tmp/kafka-all-certs.pem
        
        for CERT_FILE in /tmp/cert-*.pem; do
            if [ -f "$CERT_FILE" ] && [ -s "$CERT_FILE" ]; then
                ALIAS_NUM=$((ALIAS_NUM + 1))
                echo "DEBUG: Importing certificate $ALIAS_NUM from $CERT_FILE"
                keytool -import -trustcacerts \
                    -keystore "$TRUSTSTORE_PATH" \
                    -storepass "$TRUSTSTORE_PASS" \
                    -noprompt \
                    -alias "kafka-cert-$ALIAS_NUM" \
                    -file "$CERT_FILE" 2>&1 || echo "  (may be duplicate)"
                rm -f "$CERT_FILE"
            fi
        done
        
        if [ -f "$TRUSTSTORE_PATH" ]; then
            echo "Truststore created at $TRUSTSTORE_PATH with $ALIAS_NUM certificate(s)"
            ls -la "$TRUSTSTORE_PATH"
            echo "DEBUG: Truststore contents:"
            keytool -list -keystore "$TRUSTSTORE_PATH" -storepass "$TRUSTSTORE_PASS" 2>&1 | head -15
            # Update Kafka SSL configuration to use our truststore
            export SPRING_KAFKA_PROPERTIES_SSL_TRUSTSTORE_LOCATION="$TRUSTSTORE_PATH"
            export SPRING_KAFKA_PROPERTIES_SSL_TRUSTSTORE_PASSWORD="$TRUSTSTORE_PASS"
        else
            echo "WARNING: Failed to create truststore"
        fi
    else
        echo "WARNING: Could not fetch certificates from Kafka"
        echo "DEBUG: openssl output was:"
        cat /tmp/openssl-output.txt 2>/dev/null | head -50 || echo "(no output captured)"
    fi
    
    echo "Kafka: $KAFKA_BOOTSTRAP_SERVER (SASL_SSL)"
fi

echo "=== Configuration Complete ==="
echo ""

# Execute the original entrypoint/command
exec "$@"
