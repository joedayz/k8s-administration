#!/usr/bin/env bash
# Simulacro CKA II — Reto 6: deja k3s-worker NotReady con dos averías encadenadas.
# NO leas este script antes de intentar el reto: diagnostica desde kubectl y el nodo.
#
# Uso:
#   multipass transfer romper-nodo.sh k3s-worker:/tmp/
#   multipass exec k3s-worker -- sudo bash /tmp/romper-nodo.sh
set -euo pipefail

mkdir -p /etc/rancher/k3s/config.yaml.d
cat > /etc/rancher/k3s/config.yaml.d/50-tuning.yaml <<'EOF'
# Ajustes de rendimiento del kubelet (ticket OPS-4711)
kubelet-arg:
- "max-pods=110"
- "eviction-hard=memory.available<100Mi"
- "node-status-update-frequncy=10s"
EOF

systemctl disable --now k3s-agent >/dev/null 2>&1
echo "k3s-worker averiado. Empieza el reto."
