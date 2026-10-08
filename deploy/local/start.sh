#!/usr/bin/env bash
# Punto de entrada que usa launchd: carga los secretos y arranca el release
# activo. deploy.sh lo copia a $DEPLOY_DIR para que no dependa del checkout
# del runner (que se limpia en cada job).
set -euo pipefail

APP=user_roles_demo
ENV_FILE="${ENV_FILE:-$HOME/.config/$APP/prod.env}"

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

current="$(dirname "$0")/current"

# Recién instalado todavía no hay release: salir con 0 para que launchd no
# lo reintente en bucle. El primer deploy.sh lo arranca con `kickstart`.
if [[ ! -x "$current/bin/server" ]]; then
  echo "Sin release en $current todavía; nada que arrancar"
  exit 0
fi

exec "$current/bin/server"
