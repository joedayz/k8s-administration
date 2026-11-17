# Lab 12 — Básico: Image Security (imagePullSecrets con registro privado)

## Objetivo
Levantar un registro Docker privado con autenticación, y comprobar en la práctica que Kubernetes **no puede** descargar una imagen de un registro privado sin las credenciales correctas — el error más común al migrar una app a un cluster nuevo.

## Duración estimada
60 minutos

> **IP de referencia:** este lab usa `192.168.252.3` (la IP de `k3s-worker` en el setup de Multipass del curso). Ajusta el valor según `multipass info k3s-worker | grep IPv4` en tu entorno.

---

## Parte A — Preparar el registro privado (rol instructor/admin del cluster)

### Paso 1 — Desplegar el registro con autenticación básica

```bash
kubectl create namespace imgsec-demo

# Genera el archivo htpasswd (usuario: admin, password: SuperSecreto123)
HTPASSWD_LINE=$(htpasswd -nbB admin SuperSecreto123)
kubectl create secret generic registry-auth -n imgsec-demo --from-literal=htpasswd="$HTPASSWD_LINE"

kubectl apply -f registro-privado.yaml
kubectl rollout status deployment/registro-privado -n imgsec-demo --timeout=60s
```

### Paso 2 — Confirmar que el registro exige credenciales

```bash
# Sin credenciales -> 401
curl -s -o /dev/null -w "%{http_code}\n" http://192.168.252.3:30500/v2/_catalog

# Con credenciales -> 200
curl -s -u admin:SuperSecreto123 -o /dev/null -w "%{http_code}\n" http://192.168.252.3:30500/v2/_catalog
```

### Paso 3 — Subir una imagen de prueba al registro privado

`nginx:alpine` es una imagen **multi-arquitectura**; para copiarla a tu registro privado sin arrastrar todas las plataformas, usa `skopeo` desde uno de los nodos (selecciona solo `linux/amd64`):

```bash
multipass exec k3s-worker -- sh -c 'which skopeo || sudo apt-get install -y skopeo'

multipass exec k3s-worker -- skopeo copy --override-os linux --override-arch amd64 \
  --dest-tls-verify=false --dest-creds admin:SuperSecreto123 \
  docker://docker.io/library/nginx:alpine \
  docker://192.168.252.3:30500/privado/nginx:1.0

# Verifica que llegó
curl -s -u admin:SuperSecreto123 http://192.168.252.3:30500/v2/privado/nginx/tags/list
```

### Paso 4 — Permitir HTTP (sin TLS) hacia el registro en todos los nodos

Por defecto containerd exige HTTPS para cualquier registro. Como este es un registro de laboratorio sin certificado, hay que marcarlo como inseguro en **cada nodo**:

```bash
for node in k3s-server k3s-worker k3s-worker2; do
  multipass exec $node -- sudo sh -c 'cat > /etc/rancher/k3s/registries.yaml <<EOF
mirrors:
  "192.168.252.3:30500":
    endpoint:
      - "http://192.168.252.3:30500"
configs:
  "192.168.252.3:30500":
    tls:
      insecure_skip_verify: true
EOF'
done

multipass exec k3s-server -- sudo systemctl restart k3s
multipass exec k3s-worker -- sudo systemctl restart k3s-agent
multipass exec k3s-worker2 -- sudo systemctl restart k3s-agent

# Espera a que los 3 nodos vuelvan a Ready antes de continuar
kubectl get nodes -w
```

> En producción nunca harías esto — usarías un registro con un certificado TLS válido (interno o de una CA pública). Este paso existe solo para poder practicar sin montar una PKI completa.

---

## Parte B — El lab real: imagePullSecrets (para el alumno)

### Paso 5 — Intentar un pull sin credenciales

```bash
kubectl run pod-sin-secret --image=192.168.252.3:30500/privado/nginx:1.0 -n imgsec-demo

sleep 10
kubectl get pod pod-sin-secret -n imgsec-demo
kubectl describe pod pod-sin-secret -n imgsec-demo | grep "Failed to pull"
```

Resultado esperado:

```
STATUS: ErrImagePull / ImagePullBackOff

Failed to pull image "192.168.252.3:30500/privado/nginx:1.0": ...
pull access denied, repository does not exist or may require authorization:
authorization failed: no basic auth credentials
```

```bash
kubectl delete pod pod-sin-secret -n imgsec-demo
```

### Paso 6 — Crear el Secret de tipo `docker-registry`

```bash
kubectl create secret docker-registry regcred \
  --docker-server=192.168.252.3:30500 \
  --docker-username=admin \
  --docker-password=SuperSecreto123 \
  -n imgsec-demo
```

### Paso 7 — Desplegar el pod referenciando el secret

```bash
kubectl apply -f pod-con-secret.yaml

sleep 10
kubectl get pod pod-con-secret -n imgsec-demo -o wide
# STATUS: Running
```

---

## Limpieza

```bash
kubectl delete namespace imgsec-demo

# Revertir la configuración de registro inseguro en los nodos (opcional, si no vas a reusarlo)
for node in k3s-server k3s-worker k3s-worker2; do
  multipass exec $node -- sudo rm -f /etc/rancher/k3s/registries.yaml
done
multipass exec k3s-server -- sudo systemctl restart k3s
multipass exec k3s-worker -- sudo systemctl restart k3s-agent
multipass exec k3s-worker2 -- sudo systemctl restart k3s-agent
```

---

## Verificación final

```bash
kubectl get pods -A | grep imgsec-demo
# No debe devolver nada
```

---

## Preguntas de reflexión para el instructor

1. ¿Por qué `imagePullSecrets` se define a nivel de Pod y no de namespace? ¿Cómo evitarías repetirlo en cada manifiesto? (pista: `ServiceAccount.imagePullSecrets`)
2. ¿Qué pasa si el Secret existe pero tiene credenciales incorrectas? ¿El mensaje de error cambia respecto a no tener ningún secret?
3. ¿Qué riesgo de seguridad tiene usar `insecure_skip_verify: true` en producción? ¿Qué alternativa usarías con un registro interno real?
4. Si tu organización usa un registro como ECR/GCR/ACR, ¿de dónde obtiene Kubernetes las credenciales en vez de un Secret estático? (pista: integraciones nativas por nube, tokens de corta duración)
