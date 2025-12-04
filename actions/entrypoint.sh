#!/bin/bash
# Entrypoint script for DataHub Actions
# Maps environment variable names to expected format

set -e

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

# Debug: print configured endpoints (without secrets)
echo "=== DataHub Actions Configuration ==="
echo "GMS Host: ${DATAHUB_GMS_HOST:-NOT SET}:${DATAHUB_GMS_PORT:-NOT SET}"
echo "Kafka Bootstrap: ${KAFKA_BOOTSTRAP_SERVER:-NOT SET}"
echo "Schema Registry: ${SCHEMA_REGISTRY_URL:-NOT SET}"
echo "======================================"

# Execute the original entrypoint/command
exec "$@"

