# Lab 12 — Avanzado: Encrypt at Rest y diagnóstico de CNI/kube-proxy

## Objetivo
Cifrar los `Secret` en el datastore del cluster (equivalente a etcd en k3s) usando `EncryptionConfiguration`, demostrando con evidencia real que antes están en texto plano y después no. Luego diagnosticar, en vivo, cómo el CNI (Flannel) y kube-proxy mueven realmente el tráfico de un Service.

## Duración estimada
90 minutos

> **Nota:** k3s usa por defecto una base de datos SQLite embebida (vía `kine`) en vez de etcd real para un solo nodo server. El mecanismo de `EncryptionConfiguration` es idéntico al de un cluster kubeadm con etcd — es el mismo flag de kube-apiserver.

---

## Parte A — Encrypt Secret at Rest

### Paso 1 — Confirmar que hoy los Secrets están en texto plano

```bash
kubectl create namespace encrypt-demo
kubectl create secret generic credencial-db -n encrypt-demo --from-literal=password=ContraseñaSecreta2026
```

Busca el valor directamente en el datastore del nodo server (sin pasar por la API de Kubernetes):

```bash
HEXVAL=$(python3 -c "print('ContraseñaSecreta2026'.encode('utf-8').hex().upper())")

multipass exec k3s-server -- sudo sh -c \
  "sqlite3 /var/lib/rancher/k3s/server/db/state.db \
  \"SELECT quote(value) FROM kine WHERE name = '/registry/secrets/encrypt-demo/credencial-db' ORDER BY id DESC LIMIT 1;\"" \
  | grep -c "$HEXVAL"
```

Resultado esperado: `1` — el password aparece **tal cual, en bytes planos**, dentro del registro. Base64 en la salida de `kubectl get secret` no es cifrado: aquí lo ves crudo.

### Paso 2 — Generar la clave y la EncryptionConfiguration

```bash
ENCKEY=$(openssl rand -base64 32)

multipass exec k3s-server -- sudo sh -c "cat > /var/lib/rancher/k3s/server/encryption-config-manual.yaml <<EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: $ENCKEY
      - identity: {}
EOF"
```

(El archivo `encryption-config.yaml` de este lab es la misma plantilla, con un placeholder para pegar tu propia clave si prefieres editarlo a mano.)

### Paso 3 — Apuntar kube-apiserver al archivo y reiniciar

```bash
multipass exec k3s-server -- sudo sh -c 'cat > /etc/rancher/k3s/config.yaml <<EOF
kube-apiserver-arg:
  - "encryption-provider-config=/var/lib/rancher/k3s/server/encryption-config-manual.yaml"
EOF'

multipass exec k3s-server -- sudo systemctl restart k3s

# Espera a que el nodo vuelva a Ready
kubectl get nodes -w
```

### Paso 4 — Confirmar que los Secrets NUEVOS nacen cifrados

```bash
kubectl create secret generic credencial-tras-cifrado -n encrypt-demo --from-literal=password=ClaveCifradaDesdeElInicio

HEXVAL2=$(python3 -c "print('ClaveCifradaDesdeElInicio'.encode('utf-8').hex().upper())")
multipass exec k3s-server -- sudo sh -c \
  "sqlite3 /var/lib/rancher/k3s/server/db/state.db \
  \"SELECT quote(value) FROM kine WHERE name = '/registry/secrets/encrypt-demo/credencial-tras-cifrado' ORDER BY id DESC LIMIT 1;\"" \
  | grep -c "$HEXVAL2"
```

Resultado esperado: `0` — ya no está en texto plano. Si inspeccionas el blob verás que ahora empieza con `k8s:enc:aescbc:v1:key1:` seguido de bytes cifrados.

### Paso 5 — Los Secrets VIEJOS no se recifran solos

```bash
# El secret del Paso 1 sigue sin cifrar — habilitar encryption no reescribe el pasado
HEXVAL=$(python3 -c "print('ContraseñaSecreta2026'.encode('utf-8').hex().upper())")
multipass exec k3s-server -- sudo sh -c \
  "sqlite3 /var/lib/rancher/k3s/server/db/state.db \
  \"SELECT quote(value) FROM kine WHERE name = '/registry/secrets/encrypt-demo/credencial-db' ORDER BY id DESC LIMIT 1;\"" \
  | grep -c "$HEXVAL"
# Sigue devolviendo 1

# Forzar la reescritura (equivalente en producción a: kubectl get secrets -A -o json | kubectl replace -f -)
kubectl get secret credencial-db -n encrypt-demo -o yaml | kubectl replace -f -

multipass exec k3s-server -- sudo sh -c \
  "sqlite3 /var/lib/rancher/k3s/server/db/state.db \
  \"SELECT quote(value) FROM kine WHERE name = '/registry/secrets/encrypt-demo/credencial-db' ORDER BY id DESC LIMIT 1;\"" \
  | grep -c "$HEXVAL"
# Ahora 0 — ya quedó cifrado
```

---

## Parte B — Diagnóstico de CNI y kube-proxy

### Paso 6 — Identificar el CNI y el modo de kube-proxy en uso

```bash
# CNI: revisa el archivo de configuración que usa containerd
multipass exec k3s-worker -- sudo cat /var/lib/rancher/k3s/agent/etc/cni/net.d/10-flannel.conflist

# Modo de kube-proxy, visible en los logs al arrancar
multipass exec k3s-worker -- sh -c \
  'sudo journalctl -u k3s-agent --no-pager | grep "proxy-mode" | tail -1'
```

Resultado esperado: `type":"flannel"` en el conflist, y `--proxy-mode=iptables` en los logs (modo por defecto de k3s).

### Paso 7 — Crear un Service y ver las reglas iptables que genera kube-proxy

```bash
kubectl create namespace cni-demo
kubectl apply -f app-demo-cni.yaml
sleep 8

CLUSTER_IP=$(kubectl get svc app-demo-cni -n cni-demo -o jsonpath='{.spec.clusterIP}')
echo "ClusterIP: $CLUSTER_IP"

multipass exec k3s-worker -- sudo iptables-save -t nat | grep "$CLUSTER_IP"
```

Verás una cadena `KUBE-SVC-xxxx` que salta a dos reglas `KUBE-SEP-xxxx`, una con `--probability 0.5` — así es como kube-proxy balancea tráfico **sin pasar por un proceso intermediario**, son reglas de kernel puras.

### Paso 8 — Confirmar que las reglas apuntan a los pods reales

```bash
kubectl get pods -n cni-demo -o wide
kubectl get endpoints app-demo-cni -n cni-demo
# Las IPs deben coincidir exactamente con las de las reglas KUBE-SEP del paso anterior
```

### Paso 9 — Probar conectividad cross-node sobre la VXLAN de Flannel

```bash
kubectl run netshoot-test --image=nginx:alpine -n cni-demo --restart=Never --command -- sleep 3600
sleep 5

for i in 1 2 3 4; do
  kubectl exec netshoot-test -n cni-demo -- wget -qO- --timeout=2 http://app-demo-cni.cni-demo.svc.cluster.local | grep -o "Welcome to nginx"
done
```

Confirma la interfaz VXLAN que hace posible esa conectividad entre nodos distintos:

```bash
multipass exec k3s-worker -- ip -d link show flannel.1
# vxlan id 1 ... dstport 8472 — el puerto UDP estándar de Flannel VXLAN
```

---

## Limpieza

```bash
kubectl delete namespace encrypt-demo cni-demo

# Revertir el cifrado (opcional, si no vas a seguir usándolo en otros labs)
multipass exec k3s-server -- sudo rm -f /etc/rancher/k3s/config.yaml /var/lib/rancher/k3s/server/encryption-config-manual.yaml
multipass exec k3s-server -- sudo systemctl restart k3s
```

---

## Verificación final

```bash
kubectl get pods -A | grep -E "encrypt-demo|cni-demo"
# No debe devolver nada
```

---

## Preguntas de reflexión para el instructor

1. ¿Por qué `EncryptionConfiguration` lista `identity` como último provider en vez de solo `aescbc`? ¿Qué pasaría en la lectura de Secrets viejos si no estuviera?
2. Si rotas la clave de cifrado (`key1` → `key2`), ¿qué pasos necesitas para que TODOS los Secrets queden cifrados con la clave nueva?
3. ¿Por qué el `--probability` en las reglas `KUBE-SEP` decrece (0.5, luego 1.0 implícito en la última) en vez de ser igual para todas?
4. ¿Qué ventaja de rendimiento tiene el modo `ipvs` de kube-proxy sobre `iptables` cuando el cluster tiene miles de Services? (pista: piensa en cómo escala una lista de reglas secuenciales vs. una tabla hash)
