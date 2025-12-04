#!/bin/bash
# Entrypoint script for DataHub Actions
# Maps environment variable names to expected format

# Immediately log to prove we're running
echo "=== ACTIONS ENTRYPOINT STARTING ===" >&2
echo "Date: $(date)" >&2
echo "Args: $@" >&2
echo "Whoami: $(whoami)" >&2

# Don't exit on error initially
# set -e

# Parse DATAHUB_GMS_URL (format: https://uuid-8080.region.stg.rapu.app)
# This is provided by the service credential integration from GMS
if [ -n "$DATAHUB_GMS_URL" ]; then
    # Extract protocol
    GMS_PROTO="${DATAHUB_GMS_URL%%://*}"
    # Remove protocol prefix
    GMS_URL_NO_PROTO="${DATAHUB_GMS_URL#*://}"
    # Remove any path
    GMS_HOSTPORT="${GMS_URL_NO_PROTO%%/*}"
    
    # Extract host and port (handle case with and without explicit port)
    if [[ "$GMS_HOSTPORT" == *":"* ]]; then
        export DATAHUB_GMS_HOST="${GMS_HOSTPORT%%:*}"
        export DATAHUB_GMS_PORT="${GMS_HOSTPORT#*:}"
    else
        export DATAHUB_GMS_HOST="$GMS_HOSTPORT"
        # Default port based on protocol
        if [ "$GMS_PROTO" = "https" ]; then
            export DATAHUB_GMS_PORT="443"
        else
            export DATAHUB_GMS_PORT="80"
        fi
    fi
    export DATAHUB_GMS_PROTOCOL="$GMS_PROTO"
    
    # Also set SCHEMA_REGISTRY_URL based on GMS URL
    export SCHEMA_REGISTRY_URL="${DATAHUB_GMS_URL}/schema-registry/api/"
    
    echo "GMS configured from URL: protocol=$DATAHUB_GMS_PROTOCOL, host=$DATAHUB_GMS_HOST, port=$DATAHUB_GMS_PORT"
fi

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

# Print all env vars for debugging (hide passwords)
echo "=== Environment Variables ===" >&2
env | grep -v PASSWORD | grep -v SECRET | sort >&2
echo "=============================" >&2

# Execute the original entrypoint/command
echo "Executing command: $@" >&2
exec "$@"

