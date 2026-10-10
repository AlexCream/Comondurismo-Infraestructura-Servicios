#!/bin/sh
# Crea la base de datos del servicio de contenido junto a la de identidad (una base por
# servicio, sin compartir tablas; D-01). El contenedor de PostgreSQL ejecuta este script
# SOLO la primera vez, cuando el volumen esta vacio.
#
# Si el volumen ya existia, crea la base a mano:
#   docker exec comondurismo-postgres psql -U <POSTGRES_USER> -d postgres \
#     -c "CREATE DATABASE comondurismo_content"
#
# Las extensiones (postgis, pg_trgm, unaccent) las crea la primera migracion del servicio.
set -e

CONTENT_DB="${POSTGRES_CONTENT_DB:-comondurismo_content}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
	SELECT 'CREATE DATABASE "${CONTENT_DB}"'
	WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${CONTENT_DB}')\gexec
EOSQL
