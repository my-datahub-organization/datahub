# Required Environment Variables

## Common (All Services)

- `DATAHUB_SECRET` - Secret key for Play Framework session encryption (must match across all services)
- `METADATA_SERVICE_AUTH_ENABLED` [Optional] - Set to `false` for cookie-based auth (default: `false`)

## Frontend

- `DATAHUB_GMS_URL` - GMS service URL (e.g., `http://gms:8080`)
- `DATAHUB_SYSTEM_CLIENT_SECRET` [Optional] - Required if `METADATA_SERVICE_AUTH_ENABLED=true`
- `OPENSEARCH_URI` [Optional] - OpenSearch connection string (e.g., `https://user:pass@host:port`)
- `KAFKA_BOOTSTRAP_SERVER` [Optional] - Kafka bootstrap server (e.g., `kafka-host:9092`)
- `KAFKA_ACCESS_CERT` - Kafka client certificate (PEM format)
- `KAFKA_ACCESS_KEY` - Kafka client private key (PEM format)
- `KAFKA_CA_CERT` - Kafka CA certificate (PEM format)

## GMS

- `DATABASE_URL` - PostgreSQL connection string (e.g., `postgres://user:pass@host:port/db?sslmode=require`)
- `OPENSEARCH_URI` - OpenSearch connection string (e.g., `https://user:pass@host:port`)
- `KAFKA_BOOTSTRAP_SERVER` - Kafka bootstrap server (e.g., `kafka-host:9092`)
- `KAFKA_ACCESS_CERT` - Kafka client certificate (PEM format)
- `KAFKA_ACCESS_KEY` - Kafka client private key (PEM format)
- `KAFKA_CA_CERT` - Kafka CA certificate (PEM format)
- `KAFKA_SCHEMAREGISTRY_URL` [Optional] - Schema registry URL (defaults to GMS built-in)

## Actions

- `DATAHUB_GMS_URL` - GMS service URL (e.g., `http://gms:8080`)
- `DATAHUB_SYSTEM_CLIENT_ID` [Optional] - Required if `METADATA_SERVICE_AUTH_ENABLED=true`
- `DATAHUB_SYSTEM_CLIENT_SECRET` [Optional] - Required if `METADATA_SERVICE_AUTH_ENABLED=true`
- `KAFKA_BOOTSTRAP_SERVER` [Optional] - Kafka bootstrap server
- `KAFKA_ACCESS_CERT` - Kafka client certificate (PEM format)
- `KAFKA_ACCESS_KEY` - Kafka client private key (PEM format)
- `KAFKA_CA_CERT` - Kafka CA certificate (PEM format)

## Upgrade

- `DATABASE_URL` - PostgreSQL connection string
- `OPENSEARCH_URI` - OpenSearch connection string
- `KAFKA_BOOTSTRAP_SERVER` [Optional] - Kafka bootstrap server
- `KAFKA_ACCESS_CERT` - Kafka client certificate (PEM format)
- `KAFKA_ACCESS_KEY` - Kafka client private key (PEM format)
- `KAFKA_CA_CERT` - Kafka CA certificate (PEM format)

## Notes

- Variables marked `[Optional]` are not required for basic operation
- `DATAHUB_GMS_HOST` and `DATAHUB_GMS_PORT` are automatically derived from `DATAHUB_GMS_URL` by the entrypoint script
- Connection strings should include credentials: `protocol://username:password@host:port/path`
- Kafka SSL certificates must be provided as multi-line PEM format strings
