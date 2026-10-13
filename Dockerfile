# syntax=docker/dockerfile:1

# Imagenes de los servicios de Comondurismo a partir de los BINARIOS ya compilados que viajan
# en este repositorio (bin/). No hay codigo fuente ni compilador aqui: el servidor solo descarga
# este repositorio, y la imagen se arma copiando los ejecutables a una base minima.
#
# Los binarios los produce scripts/compilar-binarios.sh (compila con Docker desde los
# repositorios de cada servicio). Dos imagenes, un solo Dockerfile:
#
#   docker build --target identity -t comondurismo-identity:release .
#   docker build --target content  -t comondurismo-content:release  .
#
# (compose.yml ya lo hace: "docker compose build"). Para otra arquitectura:
#   docker build --platform linux/arm64 --target identity ...   # requiere bin/linux-arm64/
#
# Ejecutables en la raiz de cada imagen:
#   identity: /api (comando por defecto)  /migrate  /genkey  /grantrole  /healthcheck
#   content:  /api (comando por defecto)  /migrate  /healthcheck

# ---- Verificacion de integridad ----
# Falla la construccion si falta un binario o si no coincide con bin/<arquitectura>/SHA256SUMS
# (archivo danado, copia incompleta o binario cambiado a mano).
FROM alpine:3.21 AS verificar
ARG TARGETARCH
WORKDIR /bin-src
COPY bin/linux-${TARGETARCH}/ ./
RUN sha256sum -c SHA256SUMS

# ---- Base minima ----
# distroless/static: sin shell ni gestor de paquetes, con certificados CA y datos de zona
# horaria. Corre como usuario no root (uid 65532).
FROM gcr.io/distroless/static-debian12:nonroot AS base
USER nonroot:nonroot

# ---- Servicio de identidad ----
FROM base AS identity
LABEL org.opencontainers.image.title="comondurismo-identity" \
      org.opencontainers.image.description="Servicio de identidad de Comondurismo (binario precompilado)" \
      org.opencontainers.image.source="https://github.com/AlexCream/Comondurismo-Autenticacion-Api"
COPY --from=verificar --chmod=0755 /bin-src/identity/ /
# Todo Comondurismo usa el rango 50300-50400 (identidad: 50310).
ENV PORT=50310
EXPOSE 50310
HEALTHCHECK --interval=15s --timeout=5s --start-period=15s --retries=3 \
  CMD ["/healthcheck"]
# CMD (y no ENTRYPOINT) para poder ejecutar otros binarios de la imagen: /migrate, /genkey...
CMD ["/api"]

# ---- Servicio de contenido ----
FROM base AS content
LABEL org.opencontainers.image.title="comondurismo-content" \
      org.opencontainers.image.description="Servicio de contenido de Comondurismo (binario precompilado)" \
      org.opencontainers.image.source="https://github.com/AlexCream/Comondurismo-Contenido-API"
COPY --from=verificar --chmod=0755 /bin-src/content/ /
# Contenido: 50311.
ENV PORT=50311
EXPOSE 50311
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
  CMD ["/healthcheck"]
CMD ["/api"]
