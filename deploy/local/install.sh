#!/usr/bin/env bash
# Preparación única de esta Mac para recibir deploys locales:
#   1. crea ~/.config/user_roles_demo/prod.env con un SECRET_KEY_BASE nuevo
#   2. crea la base de datos de producción
#   3. registra la app en launchd (arranca sola y se reinicia si se cae)
#
# Ejecutar desde la raíz del repo: deploy/local/install.sh
set -euo pipefail

APP=user_roles_demo
LABEL="com.${APP}"
DEPLOY_DIR="${DEPLOY_DIR:-$HOME/apps/$APP}"
ENV_FILE="${ENV_FILE:-$HOME/.config/$APP/prod.env}"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

mkdir -p "$DEPLOY_DIR/releases" "$DEPLOY_DIR/log" "$(dirname "$ENV_FILE")"

if [[ -f "$ENV_FILE" ]]; then
  echo "==> $ENV_FILE ya existe, no lo toco"
else
  echo "==> Creando $ENV_FILE"
  secret="$(mix phx.gen.secret)"
  sed "s|__GENERADO_POR_INSTALL__|$secret|" deploy/local/prod.env.example > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

echo "==> Creando la base de datos (si no existe)"
MIX_ENV=prod mix ecto.create

echo "==> Registrando $LABEL en launchd"
sed "s|__DEPLOY_DIR__|$DEPLOY_DIR|g" deploy/local/com.user_roles_demo.plist > "$PLIST"
cp deploy/local/start.sh "$DEPLOY_DIR/start.sh"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "==> Listo. El primer deploy: deploy/local/deploy.sh"
