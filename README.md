# Infraestructura de desarrollo

PostgreSQL (con PostGIS), Redis, almacenamiento de objetos compatible con S3 (RustFS) y Mailpit
para desarrollar los servicios de identidad y de contenido. **No forma parte de los servicios**:
puedes mover esta carpeta fuera de sus repositorios sin cambiar nada de ellos.

**Nginx no está aquí**: no es un servicio de Comondurismo. Lo configura el administrador del
servidor (la guía está en la bóveda de Obsidian, nota `Despliegue_y_Nginx`).

```bash
cp .env.example .env     # define POSTGRES_PASSWORD, REDIS_PASSWORD, S3_ACCESS_KEY y S3_SECRET_KEY
docker compose up -d
docker compose ps        # espera a que postgres y redis estén "healthy"
```

Crea la red `comondurismo-network`, a la que se conectan los contenedores de los servicios para
encontrarse por nombre.

## Puertos (rango de Comondurismo: 50300–50400)

Todo se publica solo en `127.0.0.1`.

| Pieza | En la red de Docker | En tu máquina |
|---|---|---|
| PostgreSQL | `postgres:5432` | `127.0.0.1:50300` |
| Redis | `redis:6379` | `127.0.0.1:50301` |
| Mailpit (SMTP / web) | `mailpit:1025` / `8025` | `127.0.0.1:50302` / <http://localhost:50303> |
| Almacenamiento S3 (API / consola) | `storage:9000` / `9001` | `127.0.0.1:50304` / <http://localhost:50305> |

La API S3 (`S3_API_PORT`) escucha en `S3_BIND_ADDRESS` (por defecto `127.0.0.1`; `0.0.0.0` solo para
probar con otros equipos del laboratorio). Las bases, Redis, Mailpit y la consola son siempre locales.

> **Windows:** si Docker falla con `forbidden by its access permissions`, el sistema tiene
> reservado parte del rango; la solución está en la nota `Puertos_y_Red` de la bóveda.

## Documentación

Todo el detalle (cómo encuentra el servicio estas piezas, base de contenido, almacenamiento,
datos y reinicio, levantar el entorno completo) está en la bóveda de Obsidian
(`Comondurismo-Documentacion-Obsidian/Comondurismo/Servicios/`): notas `Infraestructura_Desarrollo`,
`Puertos_y_Red` y `Arquitectura_de_Servicios`.

Lo esencial:

- Los datos viven en los volúmenes `postgres_data`, `redis_data` y `storage_data`. Para empezar de
  cero (**borra todo**, incluidos los archivos subidos): `docker compose down -v`.
- La base está **vacía**: aplica las migraciones desde cada servicio (`/migrate up`).
- `postgres/initdb/` crea la base `comondurismo_content` la primera vez que arranca PostgreSQL con
  un volumen vacío.
