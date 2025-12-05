#!/bin/bash
# Entrypoint script for DataHub GMS
# Parses connection string environment variables into component variables

set -e

# Change to a writable directory - Ebean tries to write DDL files to ./
cd /tmp

echo "=== GMS Entrypoint Starting ==="

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
echo "=== Waiting for dependencies ==="

# Wait for PostgreSQL (don't fail if it times out - let the app handle it)
if [ -n "$EBEAN_DATASOURCE_HOST" ]; then
    PG_HOST="${EBEAN_DATASOURCE_HOST%%:*}"
    wait_for_dns "$PG_HOST" || echo "Continuing anyway..."
fi

# Wait for OpenSearch
if [ -n "$ELASTICSEARCH_HOST" ]; then
    wait_for_dns "$ELASTICSEARCH_HOST" || echo "Continuing anyway..."
fi

# Wait for Kafka
echo "DEBUG: KAFKA_BOOTSTRAP_SERVER='$KAFKA_BOOTSTRAP_SERVER'"
if [ -n "$KAFKA_BOOTSTRAP_SERVER" ]; then
    KAFKA_HOST="${KAFKA_BOOTSTRAP_SERVER%%:*}"
    echo "DEBUG: Extracted KAFKA_HOST='$KAFKA_HOST'"
    wait_for_dns "$KAFKA_HOST" || echo "Continuing anyway..."
else
    echo "DEBUG: KAFKA_BOOTSTRAP_SERVER is not set!"
fi

echo "=== All dependencies ready ==="

# Kafka SSL Configuration - fetch and import Aiven's CA certificate
if [ -n "$KAFKA_BOOTSTRAP_SERVER" ]; then
    KAFKA_HOST="${KAFKA_BOOTSTRAP_SERVER%%:*}"
    KAFKA_PORT="${KAFKA_BOOTSTRAP_SERVER#*:}"
    
    echo "=== Setting up Kafka SSL truststore ==="
    TRUSTSTORE_PATH="/tmp/kafka-truststore.jks"
    TRUSTSTORE_PASS="changeit"
    
    # Fetch the CA certificate chain from the Kafka server
    echo "Fetching CA certificate from $KAFKA_HOST:$KAFKA_PORT..."
    if echo | timeout 10 openssl s_client -connect "$KAFKA_HOST:$KAFKA_PORT" -servername "$KAFKA_HOST" -showcerts 2>/dev/null | openssl x509 -outform PEM > /tmp/kafka-ca.pem 2>/dev/null; then
        if [ -s /tmp/kafka-ca.pem ]; then
            echo "CA certificate fetched successfully"
            
            # Create a new truststore with the CA certificate
            rm -f "$TRUSTSTORE_PATH"
            keytool -import -trustcacerts \
                -keystore "$TRUSTSTORE_PATH" \
                -storepass "$TRUSTSTORE_PASS" \
                -noprompt \
                -alias kafka-ca \
                -file /tmp/kafka-ca.pem 2>/dev/null
            
            if [ -f "$TRUSTSTORE_PATH" ]; then
                echo "Truststore created at $TRUSTSTORE_PATH"
                # Update Kafka SSL configuration to use our truststore
                export SPRING_KAFKA_PROPERTIES_SSL_TRUSTSTORE_LOCATION="$TRUSTSTORE_PATH"
                export SPRING_KAFKA_PROPERTIES_SSL_TRUSTSTORE_PASSWORD="$TRUSTSTORE_PASS"
            else
                echo "WARNING: Failed to create truststore"
            fi
        else
            echo "WARNING: CA certificate file is empty"
        fi
    else
        echo "WARNING: Could not fetch CA certificate from Kafka"
    fi
    
    echo "Kafka: $KAFKA_BOOTSTRAP_SERVER (SASL_SSL)"
fi

echo "=== Configuration Complete ==="

# Execute the original entrypoint/command
exec "$@"
