#!/bin/sh
# Crea la base de datos del servicio de monitoreo (una base por servicio, D-01). El
# contenedor de PostgreSQL ejecuta este script SOLO la primera vez, cuando el volumen esta
# vacio.
#
# Si el volumen ya existia, crea la base a mano:
#   docker exec comondurismo-postgres psql -U <POSTGRES_USER> -d postgres \
#     -c "CREATE DATABASE comondurismo_monitor"
set -e

MONITOR_DB="${POSTGRES_MONITOR_DB:-comondurismo_monitor}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
	SELECT 'CREATE DATABASE "${MONITOR_DB}"'
	WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${MONITOR_DB}')\gexec
EOSQL
