#!/usr/bin/env bash
# Dokploy deja vacías las etiquetas de Traefik del servicio: se agregan a mano (igual que la web SIGCOM).
# Uso en el servidor: bash deploy/restore-traefik-sigcom-api.sh [nombre-del-servicio]
set -euo pipefail

SERVICE="${1:-sigcom-sigcommovil-o7503w}"
HOST="api-sigcom.grupo-santacruz.com"

docker service update \
  --label-add 'traefik.enable=true' \
  --label-add "traefik.http.routers.sigcom-api.rule=Host(\`${HOST}\`)" \
  --label-add 'traefik.http.routers.sigcom-api.entrypoints=websecure' \
  --label-add 'traefik.http.routers.sigcom-api.tls=true' \
  --label-add 'traefik.http.routers.sigcom-api.tls.certresolver=letsencrypt' \
  --label-add 'traefik.http.routers.sigcom-api.service=sigcom-api' \
  --label-add 'traefik.http.services.sigcom-api.loadbalancer.server.port=8080' \
  --label-add "traefik.http.routers.sigcom-api-web.rule=Host(\`${HOST}\`)" \
  --label-add 'traefik.http.routers.sigcom-api-web.entrypoints=web' \
  --label-add 'traefik.http.routers.sigcom-api-web.middlewares=sigcom-api-redirect-https' \
  --label-add 'traefik.http.middlewares.sigcom-api-redirect-https.redirectscheme.scheme=https' \
  --label-add 'traefik.http.middlewares.sigcom-api-redirect-https.redirectscheme.permanent=true' \
  --label-add 'traefik.docker.network=dokploy-network' \
  "$SERVICE"

echo "Etiquetas aplicadas a ${SERVICE}. Prueba: https://${HOST}/api/health"
