#!/usr/bin/env bash
# Despliega un release de producción en esta Mac.
#
# Lo ejecuta el job `deploy` de .github/workflows/ci.yml en el self-hosted
# runner, pero también se puede correr a mano desde la raíz del repo:
#
#     deploy/local/deploy.sh
#
# Cada deploy queda en $DEPLOY_DIR/releases/<sha> y `current` apunta al
# activo, así que un rollback es mover el symlink y reiniciar (ver la guía).
set -euo pipefail

APP=user_roles_demo
LABEL="com.${APP}"
DEPLOY_DIR="${DEPLOY_DIR:-$HOME/apps/$APP}"
ENV_FILE="${ENV_FILE:-$HOME/.config/$APP/prod.env}"
SHA="${RELEASE_SHA:-$(git rev-parse HEAD)}"
RELEASE_DIR="$DEPLOY_DIR/releases/${SHA:0:12}"
KEEP_RELEASES="${KEEP_RELEASES:-5}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Falta $ENV_FILE — corre primero deploy/local/install.sh" >&2
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

export MIX_ENV=prod

echo "==> Compilando release ${SHA:0:12}"
mix deps.get --only prod
mix compile
mix assets.setup

# El binario de Tailwind para macOS arm64 puede venir con firma inválida y
# macOS lo mata (exit 137). Re-firmarlo ad hoc lo deja ejecutable.
for bin in _build/tailwind-* _build/esbuild-*; do
  codesign -v "$bin" 2>/dev/null || codesign --force --sign - "$bin"
done

mix assets.deploy
mix release --overwrite --path "$RELEASE_DIR"
cp deploy/local/start.sh "$DEPLOY_DIR/start.sh"

# Migrar antes de cambiar `current`: si falla, la versión anterior sigue arriba.
echo "==> Corriendo migraciones"
"$RELEASE_DIR/bin/migrate"

echo "==> Activando release"
ln -sfn "$RELEASE_DIR" "$DEPLOY_DIR/current"
launchctl kickstart -k "gui/$(id -u)/$LABEL"

echo "==> Esperando a http://localhost:${PORT}"
for _ in $(seq 1 30); do
  if curl -fsS -o /dev/null "http://localhost:${PORT}/"; then
    echo "==> Deploy OK (${SHA:0:12})"

    # Conserva solo los últimos $KEEP_RELEASES releases.
    ls -1dt "$DEPLOY_DIR"/releases/* | tail -n +"$((KEEP_RELEASES + 1))" | xargs rm -rf
    exit 0
  fi
  sleep 1
done

echo "La app no respondió en 30s. Revisa $DEPLOY_DIR/log/" >&2
exit 1
