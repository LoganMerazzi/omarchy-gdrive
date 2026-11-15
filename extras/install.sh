#!/bin/bash
# Instala as peças do logan.gdrive que ficam fora da pasta do plugin
# (script ~/.local/bin/gdrive e o serviço rclone-gdrive) e roda o setup
# do rclone, que abre o navegador para autorizar o Google Drive.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

install -Dm755 "$here/gdrive" "$HOME/.local/bin/gdrive"
install -Dm644 "$here/rclone-gdrive.service" "$HOME/.config/systemd/user/rclone-gdrive.service"

exec "$HOME/.local/bin/gdrive" setup
