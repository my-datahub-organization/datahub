#!/bin/bash
# Entrypoint script for DataHub GMS
# Parses connection string environment variables into component variables

set -e

echo "=== GMS Entrypoint Starting ==="
echo "DATABASE_URL set: $([ -n "$DATABASE_URL" ] && echo 'yes' || echo 'NO')"
echo "OPENSEARCH_URI set: $([ -n "$OPENSEARCH_URI" ] && echo 'yes' || echo 'NO')"
echo "KAFKA_BOOTSTRAP_SERVER set: $([ -n "$KAFKA_BOOTSTRAP_SERVER" ] && echo 'yes' || echo 'NO')"
echo "KAFKA_SASL_USERNAME set: $([ -n "$KAFKA_SASL_USERNAME" ] && echo 'yes' || echo 'NO')"

# Parse DATABASE_URL (format: postgres://user:pass@host:port/dbname?sslmode=require)
if [ -n "$DATABASE_URL" ]; then
    # Remove protocol prefix
    DB_URL_NO_PROTO="${DATABASE_URL#*://}"
    
    # Extract user:pass (before @)
    DB_USERPASS="${DB_URL_NO_PROTO%%@*}"
    export EBEAN_DATASOURCE_USERNAME="${DB_USERPASS%%:*}"
    export EBEAN_DATASOURCE_PASSWORD="${DB_USERPASS#*:}"
    
    # Extract host:port/dbname (after @)
    DB_HOSTPATH="${DB_URL_NO_PROTO#*@}"
    DB_HOSTPORT="${DB_HOSTPATH%%/*}"
    export EBEAN_DATASOURCE_HOST="$DB_HOSTPORT"
    
    # Extract dbname (between / and ?)
    DB_DBNAME_QUERY="${DB_HOSTPATH#*/}"
    DB_DBNAME="${DB_DBNAME_QUERY%%\?*}"
    
    # Build JDBC URL
    export EBEAN_DATASOURCE_URL="jdbc:postgresql://${DB_HOSTPORT}/${DB_DBNAME}?sslmode=require"
    
    echo "PostgreSQL configured: host=$EBEAN_DATASOURCE_HOST, db=$DB_DBNAME"
fi

# Parse OPENSEARCH_URI (format: https://user:pass@host:port)
if [ -n "$OPENSEARCH_URI" ]; then
    # Remove protocol prefix
    OS_URL_NO_PROTO="${OPENSEARCH_URI#*://}"
    
    # Extract user:pass (before @)
    OS_USERPASS="${OS_URL_NO_PROTO%%@*}"
    export ELASTICSEARCH_USERNAME="${OS_USERPASS%%:*}"
    export ELASTICSEARCH_PASSWORD="${OS_USERPASS#*:}"
    
    # Extract host:port (after @)
    OS_HOSTPORT="${OS_URL_NO_PROTO#*@}"
    export ELASTICSEARCH_HOST="${OS_HOSTPORT%%:*}"
    export ELASTICSEARCH_PORT="${OS_HOSTPORT#*:}"
    
    echo "OpenSearch configured: host=$ELASTICSEARCH_HOST, port=$ELASTICSEARCH_PORT"
fi

# Build Kafka SASL JAAS config from individual credentials
if [ -n "$KAFKA_SASL_USERNAME" ] && [ -n "$KAFKA_SASL_PASSWORD" ]; then
    export SPRING_KAFKA_PROPERTIES_SASL_JAAS_CONFIG="org.apache.kafka.common.security.plain.PlainLoginModule required username=\"$KAFKA_SASL_USERNAME\" password=\"$KAFKA_SASL_PASSWORD\";"
    echo "Kafka SASL configured for user: $KAFKA_SASL_USERNAME"
fi

# Set truststore password (use a default if not provided)
if [ -z "$SPRING_KAFKA_PROPERTIES_SSL_TRUSTSTORE_PASSWORD" ]; then
    export SPRING_KAFKA_PROPERTIES_SSL_TRUSTSTORE_PASSWORD="changeit"
fi

# Debug: print configured endpoints (without secrets)
echo "=== DataHub GMS Configuration ==="
echo "PostgreSQL Host: ${EBEAN_DATASOURCE_HOST:-NOT SET}"
echo "Kafka Bootstrap: ${KAFKA_BOOTSTRAP_SERVER:-NOT SET}"
echo "OpenSearch Host: ${ELASTICSEARCH_HOST:-NOT SET}:${ELASTICSEARCH_PORT:-NOT SET}"
echo "================================="

# Execute the original entrypoint/command
exec "$@"
