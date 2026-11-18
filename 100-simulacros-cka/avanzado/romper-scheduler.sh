#!/usr/bin/env bash
# Simulacro CKA II — Reto 7: "los pods nuevos no arrancan".
# NO leas este script antes de intentar el reto.
#
# Uso:
#   multipass transfer romper-scheduler.sh k3s-server:/tmp/
#   multipass exec k3s-server -- sudo bash /tmp/romper-scheduler.sh
set -euo pipefail

mkdir -p /etc/rancher/k3s/config.yaml.d
cat > /etc/rancher/k3s/config.yaml.d/60-ha-externo.yaml <<'EOF'
# Preparación para scheduler externo en HA (CHG-2209) — NO TOCAR
disable-scheduler: true
EOF

systemctl restart k3s
echo "Cambio aplicado. Espera ~30 s a que el API server vuelva y empieza el reto."
