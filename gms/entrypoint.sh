#!/bin/bash
# Entrypoint script for DataHub GMS
# Parses connection string environment variables into component variables

set -e

# Change to a writable directory - Ebean tries to write DDL files to ./
cd /tmp

echo "=== GMS Entrypoint Starting ==="

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
    OS_URL_NO_PROTO="${OPENSEARCH_URI#*://}"
    OS_USERPASS="${OS_URL_NO_PROTO%%@*}"
    export ELASTICSEARCH_USERNAME="${OS_USERPASS%%:*}"
    export ELASTICSEARCH_PASSWORD="${OS_USERPASS#*:}"
    OS_HOSTPORT="${OS_URL_NO_PROTO#*@}"
    export ELASTICSEARCH_HOST="${OS_HOSTPORT%%:*}"
    export ELASTICSEARCH_PORT="${OS_HOSTPORT#*:}"
    echo "OpenSearch: $ELASTICSEARCH_HOST:$ELASTICSEARCH_PORT"
fi

# Build Kafka SASL JAAS config
if [ -n "$KAFKA_SASL_USERNAME" ] && [ -n "$KAFKA_SASL_PASSWORD" ]; then
    export SPRING_KAFKA_PROPERTIES_SASL_JAAS_CONFIG="org.apache.kafka.common.security.plain.PlainLoginModule required username=\"$KAFKA_SASL_USERNAME\" password=\"$KAFKA_SASL_PASSWORD\";"
    echo "Kafka SASL: user=$KAFKA_SASL_USERNAME"
fi

# Setup Kafka SSL - download and trust the server certificate
if [ -n "$KAFKA_BOOTSTRAP_SERVER" ]; then
    KAFKA_HOST="${KAFKA_BOOTSTRAP_SERVER%%:*}"
    KAFKA_PORT="${KAFKA_BOOTSTRAP_SERVER#*:}"
    TRUSTSTORE="/tmp/kafka-truststore.jks"
    TRUSTSTORE_PASS="changeit"
    
    echo "Fetching Kafka SSL certificate from $KAFKA_HOST:$KAFKA_PORT..."
    
    # Download server certificate
    echo | openssl s_client -connect "$KAFKA_HOST:$KAFKA_PORT" -servername "$KAFKA_HOST" 2>/dev/null | \
        openssl x509 -outform PEM > /tmp/kafka-cert.pem 2>/dev/null || true
    
    if [ -s /tmp/kafka-cert.pem ]; then
        # Create truststore with the server cert
        rm -f "$TRUSTSTORE"
        keytool -import -trustcacerts -alias kafka-server -file /tmp/kafka-cert.pem \
            -keystore "$TRUSTSTORE" -storepass "$TRUSTSTORE_PASS" -noprompt 2>/dev/null
        rm -f /tmp/kafka-cert.pem
        
        # Configure Kafka to use this truststore
        export SPRING_KAFKA_PROPERTIES_SSL_TRUSTSTORE_LOCATION="$TRUSTSTORE"
        export SPRING_KAFKA_PROPERTIES_SSL_TRUSTSTORE_PASSWORD="$TRUSTSTORE_PASS"
        export SPRING_KAFKA_PROPERTIES_SSL_TRUSTSTORE_TYPE="JKS"
        
        # Update JAVA_OPTS
        export JAVA_OPTS="${JAVA_OPTS} -Djavax.net.ssl.trustStore=$TRUSTSTORE -Djavax.net.ssl.trustStorePassword=$TRUSTSTORE_PASS"
        
        echo "Kafka SSL truststore created with server certificate"
    else
        echo "WARNING: Could not fetch Kafka certificate, SSL may fail"
    fi
fi

export SPRING_KAFKA_PROPERTIES_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM=""

echo "=== Configuration Complete ==="

# Execute the original entrypoint/command
exec "$@"
