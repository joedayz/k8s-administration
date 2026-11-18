#!/usr/bin/env bash
# Simulacro CKA II — Reto 5: etcd "estilo kubeadm" en k3s-worker2.
# k3s usa SQLite (kine), así que levantamos un etcd con TLS como static pod para
# practicar etcdctl/etcdutl con las mismas rutas y flags que en un cluster kubeadm.
#
# Uso (desde tu Mac/Linux):
#   multipass transfer preparar-etcd.sh k3s-worker2:/tmp/
#   multipass exec k3s-worker2 -- sudo bash /tmp/preparar-etcd.sh
set -euo pipefail

ETCD_VER=v3.6.16
ARCH=$(dpkg --print-architecture)          # amd64 | arm64
PKI=/etc/kubernetes/pki/etcd
DATA=/var/lib/etcd
MANIFESTS=/var/lib/rancher/k3s/agent/pod-manifests
NODE_IP=$(hostname -I | awk '{print $1}')

echo ">> Instalando etcdctl y etcdutl ${ETCD_VER} (${ARCH})"
if ! command -v etcdctl >/dev/null || ! etcdctl version | grep -q "${ETCD_VER#v}"; then
  curl -sSL "https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-${ARCH}.tar.gz" \
    | tar xz -C /tmp
  install -m 0755 "/tmp/etcd-${ETCD_VER}-linux-${ARCH}/etcdctl" /usr/local/bin/etcdctl
  install -m 0755 "/tmp/etcd-${ETCD_VER}-linux-${ARCH}/etcdutl" /usr/local/bin/etcdutl
  rm -rf "/tmp/etcd-${ETCD_VER}-linux-${ARCH}"
fi

echo ">> Generando PKI de etcd en ${PKI}"
mkdir -p "$PKI"
cd "$PKI"
if [ ! -f ca.crt ]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 365 -subj "/CN=etcd-ca" \
    -keyout ca.key -out ca.crt 2>/dev/null
  openssl req -newkey rsa:2048 -nodes -subj "/CN=$(hostname)" \
    -keyout server.key -out server.csr 2>/dev/null
  printf "subjectAltName=DNS:localhost,DNS:%s,IP:127.0.0.1,IP:%s\nextendedKeyUsage=serverAuth,clientAuth\n" \
    "$(hostname)" "$NODE_IP" > server.ext
  openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -days 365 -extfile server.ext -out server.crt 2>/dev/null
  rm -f server.csr server.ext ca.srl
  chmod 600 ./*.key
fi

echo ">> Creando el static pod etcd (data-dir ${DATA})"
mkdir -p "$DATA" "$MANIFESTS" /opt/cka2
cat > "${MANIFESTS}/etcd.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: etcd
  namespace: kube-system
  labels:
    component: etcd
    tier: control-plane
spec:
  hostNetwork: true
  containers:
  - name: etcd
    image: quay.io/coreos/etcd:${ETCD_VER}
    command:
    - etcd
    - --name=$(hostname)
    - --data-dir=/var/lib/etcd
    - --listen-client-urls=https://127.0.0.1:2379,https://${NODE_IP}:2379
    - --advertise-client-urls=https://${NODE_IP}:2379
    - --listen-peer-urls=https://127.0.0.1:2380
    - --initial-advertise-peer-urls=https://127.0.0.1:2380
    - --initial-cluster=$(hostname)=https://127.0.0.1:2380
    - --cert-file=/etc/kubernetes/pki/etcd/server.crt
    - --key-file=/etc/kubernetes/pki/etcd/server.key
    - --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
    - --client-cert-auth=true
    - --peer-cert-file=/etc/kubernetes/pki/etcd/server.crt
    - --peer-key-file=/etc/kubernetes/pki/etcd/server.key
    - --peer-trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
    - --peer-client-cert-auth=true
    volumeMounts:
    - name: etcd-data
      mountPath: /var/lib/etcd
    - name: etcd-certs
      mountPath: /etc/kubernetes/pki/etcd
      readOnly: true
  volumes:
  - name: etcd-data
    hostPath:
      path: ${DATA}
      type: DirectoryOrCreate
  - name: etcd-certs
    hostPath:
      path: ${PKI}
      type: Directory
EOF

echo ">> Esperando a que etcd responda"

FLAGS=(--endpoints=https://127.0.0.1:2379 --cacert=$PKI/ca.crt --cert=$PKI/server.crt --key=$PKI/server.key)
for _ in $(seq 1 60); do
  etcdctl "${FLAGS[@]}" endpoint health >/dev/null 2>&1 && break
  sleep 2
done
etcdctl "${FLAGS[@]}" endpoint health

echo ">> Cargando los datos de la empresa"
for app in pagos catalogo inventario; do
  etcdctl "${FLAGS[@]}" put "/empresa/apps/${app}" "estado=produccion" >/dev/null
done
etcdctl "${FLAGS[@]}" put /empresa/config/version "2026.11" >/dev/null
etcdctl "${FLAGS[@]}" get /empresa --prefix --keys-only
echo ">> Listo. etcd escucha en https://127.0.0.1:2379 y https://${NODE_IP}:2379"
