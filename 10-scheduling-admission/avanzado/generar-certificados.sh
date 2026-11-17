#!/bin/bash
# Genera una CA autofirmada y un certificado de servidor para el webhook
# de admisión, válido para el Service admission-webhook.webhook-system.svc.
set -euo pipefail

WORKDIR=$(mktemp -d)
cd "$WORKDIR"

openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt -days 365 \
  -subj "/CN=admission-webhook-ca"

cat > server.conf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
[req_distinguished_name]
[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = admission-webhook.webhook-system.svc
DNS.2 = admission-webhook.webhook-system.svc.cluster.local
EOF

openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr \
  -subj "/CN=admission-webhook.webhook-system.svc" -config server.conf
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out server.crt -days 365 -extensions v3_req -extfile server.conf

kubectl create namespace webhook-system --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret tls webhook-tls --cert=server.crt --key=server.key \
  -n webhook-system --dry-run=client -o yaml | kubectl apply -f -

CA_BUNDLE=$(base64 < ca.crt | tr -d '\n')
echo ""
echo "CA_BUNDLE generado. Úsalo para reemplazar el placeholder en validating-webhook-config.yaml:"
echo ""
echo "$CA_BUNDLE"
echo ""
echo "Ejemplo:"
echo '  sed "s|CA_BUNDLE_PLACEHOLDER|'"$CA_BUNDLE"'|" validating-webhook-config.yaml | kubectl apply -f -'

cd - > /dev/null
rm -rf "$WORKDIR"
