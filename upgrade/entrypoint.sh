#!/bin/bash
# Entrypoint script for DataHub Upgrade Job
# Parses connection string environment variables into component variables

set -e

echo "=== DataHub Upgrade Job Entrypoint Starting ==="

# Debug: show what env vars we received
echo "DEBUG: Environment variables from docker-compose:"
echo "  DATABASE_URL set: $([ -n "${DATABASE_URL:-}" ] && echo 'YES' || echo 'NO')"
echo "  OPENSEARCH_URI set: $([ -n "${OPENSEARCH_URI:-}" ] && echo 'YES' || echo 'NO')"
echo "  KAFKA_BOOTSTRAP_SERVER set: $([ -n "${KAFKA_BOOTSTRAP_SERVER:-}" ] && echo 'YES' || echo 'NO')"
echo "  KAFKA_ACCESS_CERT set: $([ -n "${KAFKA_ACCESS_CERT:-}" ] && echo 'YES' || echo 'NO')"
echo "  KAFKA_ACCESS_KEY set: $([ -n "${KAFKA_ACCESS_KEY:-}" ] && echo 'YES' || echo 'NO')"
echo "  KAFKA_CA_CERT set: $([ -n "${KAFKA_CA_CERT:-}" ] && echo 'YES' || echo 'NO')"

# Function to setup certificates
setup_certificates() {
    local certs_dir="/tmp/certs"
    mkdir -p "$certs_dir"
    chmod 700 "$certs_dir"
    
    echo "=== Setting up Kafka SSL/TLS certificates ==="
    
    # Write certificate files
    echo "$KAFKA_ACCESS_CERT" > "$certs_dir/kafka-client.crt"
    chmod 600 "$certs_dir/kafka-client.crt"
    echo "Wrote Kafka client certificate to $certs_dir/kafka-client.crt"
    
    echo "$KAFKA_ACCESS_KEY" > "$certs_dir/kafka-client.key"
    chmod 600 "$certs_dir/kafka-client.key"
    echo "Wrote Kafka client private key to $certs_dir/kafka-client.key"
    
    echo "$KAFKA_CA_CERT" > "$certs_dir/kafka-ca.crt"
    chmod 644 "$certs_dir/kafka-ca.crt"
    echo "Wrote Kafka CA certificate to $certs_dir/kafka-ca.crt"
    
    # Create PKCS12 keystore from PEM files
    KEYSTORE_PATH="/tmp/kafka-client-keystore.p12"
    KEYSTORE_PASS="changeit"
    
    echo "Creating PKCS12 keystore from client certificate and key..."
    openssl pkcs12 -export \
        -in "$certs_dir/kafka-client.crt" \
        -inkey "$certs_dir/kafka-client.key" \
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
    
    # Create JKS truststore from CA certificate
    TRUSTSTORE_PATH="/tmp/kafka-truststore.jks"
    TRUSTSTORE_PASS="changeit"
    
    rm -f "$TRUSTSTORE_PATH"
    
    echo "Importing Kafka CA certificate into truststore..."
    keytool -import -trustcacerts \
        -keystore "$TRUSTSTORE_PATH" \
        -storepass "$TRUSTSTORE_PASS" \
        -noprompt \
        -alias "kafka-ca" \
        -file "$certs_dir/kafka-ca.crt" 2>&1 || {
        echo "ERROR: Failed to import CA certificate"
        exit 1
    }
    
    if [ -f "$TRUSTSTORE_PATH" ]; then
        echo "Truststore created at $TRUSTSTORE_PATH"
        export SPRING_KAFKA_PROPERTIES_SSL_TRUSTSTORE_LOCATION="$TRUSTSTORE_PATH"
        export SPRING_KAFKA_PROPERTIES_SSL_TRUSTSTORE_PASSWORD="$TRUSTSTORE_PASS"
        echo "Certificate setup complete"
    else
        echo "ERROR: Failed to create truststore"
        exit 1
    fi
}

# Parse DATABASE_URL (format: postgres://user:pass@host:port/dbname?sslmode=require)
if [ -n "${DATABASE_URL:-}" ]; then
    echo "DEBUG: Parsing DATABASE_URL..."
    
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
    
    echo "DEBUG: EBEAN_DATASOURCE_URL='$EBEAN_DATASOURCE_URL'"
    echo "DEBUG: EBEAN_DATASOURCE_HOST='$EBEAN_DATASOURCE_HOST'"
    echo "DEBUG: EBEAN_DATASOURCE_USERNAME='$EBEAN_DATASOURCE_USERNAME'"
    echo "PostgreSQL: $EBEAN_DATASOURCE_HOST"
else
    echo "ERROR: DATABASE_URL is not set!"
    exit 1
fi

# Parse OPENSEARCH_URI (format: https://user:pass@host:port)
if [ -n "${OPENSEARCH_URI:-}" ]; then
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
    export ELASTICSEARCH_PROTOCOL="$OS_PROTO"
    if [ "$OS_PROTO" = "https" ]; then
        export ELASTICSEARCH_USE_SSL="true"
        export ELASTICSEARCH_SSL_PROTOCOL="TLSv1.2"
    else
        export ELASTICSEARCH_USE_SSL="false"
    fi
    
    echo "DEBUG: ELASTICSEARCH_HOST='$ELASTICSEARCH_HOST'"
    echo "DEBUG: ELASTICSEARCH_PORT='$ELASTICSEARCH_PORT'"
    echo "DEBUG: ELASTICSEARCH_USERNAME='$ELASTICSEARCH_USERNAME'"
    echo "DEBUG: ELASTICSEARCH_USE_SSL='$ELASTICSEARCH_USE_SSL'"
    echo "OpenSearch: $ELASTICSEARCH_HOST:$ELASTICSEARCH_PORT (SSL: ${ELASTICSEARCH_USE_SSL:-false})"
else
    echo "ERROR: OPENSEARCH_URI is not set!"
    exit 1
fi

# Setup certificates if Kafka cert environment variables are present
if [ -n "${KAFKA_ACCESS_CERT:-}" ] && [ -n "${KAFKA_ACCESS_KEY:-}" ] && [ -n "${KAFKA_CA_CERT:-}" ]; then
    setup_certificates
    echo "Kafka: $KAFKA_BOOTSTRAP_SERVER (mTLS)"
else
    echo "WARNING: Kafka SSL certificates not provided"
    if [ -z "${KAFKA_BOOTSTRAP_SERVER:-}" ]; then
        echo "ERROR: KAFKA_BOOTSTRAP_SERVER is not set!"
        exit 1
    fi
    echo "Kafka: $KAFKA_BOOTSTRAP_SERVER (no SSL)"
fi

# Validate required environment variables
if [ -z "${EBEAN_DATASOURCE_URL:-}" ]; then
    echo "ERROR: EBEAN_DATASOURCE_URL environment variable is required (derived from DATABASE_URL)"
    exit 1
fi

if [ -z "${ELASTICSEARCH_HOST:-}" ]; then
    echo "ERROR: ELASTICSEARCH_HOST environment variable is required (derived from OPENSEARCH_URI)"
    exit 1
fi

if [ -z "${KAFKA_BOOTSTRAP_SERVER:-}" ]; then
    echo "ERROR: KAFKA_BOOTSTRAP_SERVER environment variable is required"
    exit 1
fi

echo "=== Configuration Complete ==="
echo ""
echo "Starting upgrade job..."

# Execute the upgrade job
exec "$@"
