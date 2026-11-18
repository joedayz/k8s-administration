# Lab 100 — Intermedio: Retos de Dificultad Media (Workloads, Red y Almacenamiento)

## Objetivo
Resolver ejercicios de ~10 minutos que combinan varios objetos de Kubernetes: StatefulSets, Jobs, sidecars nativos, NetworkPolicy, Ingress, Gateway API, PV estáticos, Kustomize, Helm, CRDs, PriorityClass, ValidatingAdmissionPolicy, RBAC con tokens, StorageClass por defecto, Downward API y EndpointSlices. Ninguno repite los retos del módulo 99 (allí ya se hicieron SA+Role, Ingress TLS, PVC dinámico, deny-all con DNS y ClusterRole de nodos).

## Duración estimada
170 minutos (16 retos × 10 min + revisión) — o dos sesiones: retos 1–8 y 9–16

> Namespace principal: `cka2-mid`. Créalo una vez al inicio:
> ```bash
> kubectl create namespace cka2-mid
> kubectl config set-context --current --namespace=cka2-mid
> ```
> Al terminar, vuelve a `default`: `kubectl config set-context --current --namespace=default`

---

## Reto 1 — StatefulSet con Service headless y volumeClaimTemplates (10 min)

> En el namespace `cka2-mid` crea un StatefulSet `kv` con 3 réplicas (`nginx:alpine`) y un
> Service headless `kv-hl`. Cada réplica debe tener su propio PVC de 64Mi (StorageClass
> `local-path`) montado en `/usr/share/nginx/html`. Escribe en cada réplica un `index.html`
> con su hostname. Comprueba que `kv-1.kv-hl.cka2-mid.svc.cluster.local` resuelve a la IP
> del pod `kv-1` y que, al borrar `kv-1`, el pod recreado conserva **el mismo nombre y los mismos datos**.

```bash
# Solución
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: kv-hl
  namespace: cka2-mid
spec:
  clusterIP: None          # headless: el DNS devuelve las IPs de los pods
  selector:
    app: kv
  ports:
  - port: 80
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kv
  namespace: cka2-mid
spec:
  serviceName: kv-hl       # obligatorio para los registros DNS por pod
  replicas: 3
  selector:
    matchLabels:
      app: kv
  template:
    metadata:
      labels:
        app: kv
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: datos
          mountPath: /usr/share/nginx/html
  volumeClaimTemplates:
  - metadata:
      name: datos
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: local-path
      resources:
        requests:
          storage: 64Mi
YAML

kubectl rollout status statefulset/kv -n cka2-mid --timeout=120s
# Los pods se crean en orden: kv-0 → kv-1 → kv-2

for i in 0 1 2; do
  kubectl exec -n cka2-mid kv-$i -- sh -c 'hostname > /usr/share/nginx/html/index.html'
done
```

**Verificación:**
```bash
kubectl get pvc -n cka2-mid
# datos-kv-0, datos-kv-1, datos-kv-2 → Bound (patrón <plantilla>-<statefulset>-<ordinal>)

# DNS estable por pod (resuelve a la IP del pod, no a una ClusterIP)
kubectl get pod kv-1 -n cka2-mid -o jsonpath='{.status.podIP}{"\n"}'
kubectl run dns-test -n cka2-mid --rm -it --restart=Never --image=busybox:1.36 -- \
  nslookup kv-1.kv-hl.cka2-mid.svc.cluster.local
# Address: <la misma IP que kv-1>

# El headless devuelve las 3 IPs
kubectl run dns-test -n cka2-mid --rm -it --restart=Never --image=busybox:1.36 -- \
  nslookup kv-hl.cka2-mid.svc.cluster.local

# Identidad y datos persistentes
kubectl delete pod kv-1 -n cka2-mid
kubectl wait --for=condition=Ready pod/kv-1 -n cka2-mid --timeout=90s
kubectl run curl-test -n cka2-mid --rm -it --restart=Never --image=curlimages/curl:8.11.1 -- \
  curl -s http://kv-1.kv-hl
# kv-1   ← mismo nombre y mismo contenido tras recrearse
```

> **Ojo:** `kubectl delete statefulset kv` **no** borra los PVC `datos-kv-*`; hay que borrarlos a mano
> (o usar `spec.persistentVolumeClaimRetentionPolicy`).

---

## Reto 2 — Job paralelo con completions, parallelism, backoffLimit y deadline (10 min)

> En `cka2-mid` crea un Job `procesar-lotes` (`busybox:1.36`) que ejecute **6 completions**
> con **parallelism 2**, en modo `Indexed`, donde cada pod imprima `Lote <índice>` y duerma 5 s.
> El Job debe fallar si supera **60 segundos** o **2 reintentos**, y debe autoeliminarse
> 120 s después de terminar. Crea además un Job `job-falla` con `backoffLimit: 1` cuyo
> contenedor salga con código 1 y comprueba la razón del fallo.

```bash
# Solución — generar el esqueleto y completarlo
kubectl create job procesar-lotes -n cka2-mid --image=busybox:1.36 \
  --dry-run=client -o yaml -- sh -c 'echo "Lote $JOB_COMPLETION_INDEX"; sleep 5' > job.yaml

# Editar spec del Job: añadir completions, parallelism, completionMode, backoffLimit,
# activeDeadlineSeconds y ttlSecondsAfterFinished
cat <<'YAML' | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: procesar-lotes
  namespace: cka2-mid
spec:
  completions: 6
  parallelism: 2
  completionMode: Indexed
  backoffLimit: 2
  activeDeadlineSeconds: 60
  ttlSecondsAfterFinished: 120
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: lote
        image: busybox:1.36
        command: ["sh", "-c", "echo \"Lote $JOB_COMPLETION_INDEX\"; sleep 5"]
YAML

# Job que falla siempre
cat <<'YAML' | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: job-falla
  namespace: cka2-mid
spec:
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: falla
        image: busybox:1.36
        command: ["sh", "-c", "echo fallo; exit 1"]
YAML
```

**Verificación:**
```bash
# Nunca más de 2 pods corriendo a la vez
kubectl get pods -n cka2-mid -l job-name=procesar-lotes -w
# (Ctrl+C cuando estén todos Completed)

kubectl wait --for=condition=Complete job/procesar-lotes -n cka2-mid --timeout=90s
kubectl get job procesar-lotes -n cka2-mid
# COMPLETIONS 6/6   DURATION ~15-20s (3 tandas de 2)

# Cada índice se ejecutó exactamente una vez
for p in $(kubectl get pods -n cka2-mid -l job-name=procesar-lotes -o name); do
  kubectl logs -n cka2-mid $p
done | sort
# Lote 0 ... Lote 5

kubectl get job job-falla -n cka2-mid \
  -o jsonpath='{.status.conditions[?(@.type=="Failed")].reason}{"\n"}'
# BackoffLimitExceeded
kubectl get pods -n cka2-mid -l job-name=job-falla
# 2 pods en Error (intento inicial + 1 reintento)

# A los 120 s el Job completado desaparece solo (TTL)
sleep 120; kubectl get job procesar-lotes -n cka2-mid
# Error from server (NotFound)
```

---

## Reto 3 — Sidecar nativo (initContainer con restartPolicy: Always) (10 min)

> En `cka2-mid` crea un Deployment `web-logs` (`nginx:alpine`) que escriba su access log en
> un volumen `emptyDir` montado en `/var/log/nginx`. Añade un **sidecar nativo** `log-shipper`
> (`busybox:1.36`) que haga `tail -F /var/log/nginx/access.log`. Después crea un Job
> `job-con-sidecar` cuyo contenedor principal termine en 5 s y demuestra que el Job
> **se completa** aunque el sidecar sea un proceso infinito.

```bash
# Solución
cat <<'YAML' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-logs
  namespace: cka2-mid
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web-logs
  template:
    metadata:
      labels:
        app: web-logs
    spec:
      initContainers:
      - name: log-shipper
        image: busybox:1.36
        restartPolicy: Always     # ← esto lo convierte en sidecar nativo
        command: ["sh", "-c", "touch /var/log/nginx/access.log; tail -F /var/log/nginx/access.log"]
        volumeMounts:
        - name: logs
          mountPath: /var/log/nginx
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: logs
          mountPath: /var/log/nginx
      volumes:
      - name: logs
        emptyDir: {}
YAML
kubectl expose deployment web-logs -n cka2-mid --port=80

cat <<'YAML' | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: job-con-sidecar
  namespace: cka2-mid
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      initContainers:
      - name: proxy
        image: busybox:1.36
        restartPolicy: Always
        command: ["sh", "-c", "while true; do sleep 3600; done"]
      containers:
      - name: tarea
        image: busybox:1.36
        command: ["sh", "-c", "echo trabajando; sleep 5; echo listo"]
YAML
```

> En la imagen oficial de nginx `access.log` es un symlink a `/dev/stdout`; al montar un
> `emptyDir` en `/var/log/nginx` el symlink desaparece y nginx escribe un archivo real.

**Verificación:**
```bash
kubectl rollout status deployment/web-logs -n cka2-mid
kubectl get pod -n cka2-mid -l app=web-logs
# READY 2/2 → el sidecar cuenta como contenedor del pod aunque esté en initContainers

# Generar tráfico y leerlo desde el sidecar
kubectl run curl-test -n cka2-mid --rm -it --restart=Never --image=curlimages/curl:8.11.1 -- \
  sh -c 'for i in 1 2 3; do curl -s -o /dev/null http://web-logs/sidecar-$i; done'
kubectl logs -n cka2-mid deploy/web-logs -c log-shipper | grep sidecar-
# 3 líneas "GET /sidecar-1 ...", "GET /sidecar-2 ...", "GET /sidecar-3 ..."

# El Job termina: el kubelet para el sidecar cuando acaba el contenedor principal
kubectl wait --for=condition=Complete job/job-con-sidecar -n cka2-mid --timeout=60s
kubectl get job job-con-sidecar -n cka2-mid
# COMPLETIONS 1/1
```

> Con un sidecar "clásico" (segundo contenedor en `containers`) el Job se quedaría `Running`
> para siempre porque el pod nunca termina.

---

## Reto 4 — NetworkPolicy: namespaceSelector + podSelector (AND) y egress restringido (10 min)

> 1. En `cka2-mid` despliega `api` (`nginx:alpine`, label `app=api`) con su Service en el puerto 80.
> 2. Crea el namespace `cka2-front` con la label `equipo=front`.
> 3. Crea la NetworkPolicy `api-solo-front` en `cka2-mid` que permita el ingress al `api` en el
>    puerto 80 **solo** desde pods con `role=frontend` **que además** estén en namespaces con
>    `equipo=front`.
> 4. Crea la NetworkPolicy `front-egress` en `cka2-front` que limite el egress de los pods
>    `role=frontend` a: DNS (CoreDNS, 53 UDP/TCP) y el `api` de `cka2-mid` en el puerto 80.

```bash
# Solución
kubectl create deployment api -n cka2-mid --image=nginx:alpine
kubectl expose deployment api -n cka2-mid --port=80
kubectl create namespace cka2-front
kubectl label namespace cka2-front equipo=front

cat <<'YAML' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-solo-front
  namespace: cka2-mid
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: ["Ingress"]
  ingress:
  - from:
    - namespaceSelector:          # UN solo elemento con los dos selectores = AND
        matchLabels:
          equipo: front
      podSelector:
        matchLabels:
          role: frontend
    ports:
    - protocol: TCP
      port: 80
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: front-egress
  namespace: cka2-front
spec:
  podSelector:
    matchLabels:
      role: frontend
  policyTypes: ["Egress"]
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: cka2-mid
      podSelector:
        matchLabels:
          app: api
    ports:
    - protocol: TCP
      port: 80
YAML
```

> **Trampa clásica:** si escribes `- namespaceSelector: ...` y `- podSelector: ...` como **dos
> elementos** de la lista `from`, la regla pasa a ser OR (cualquier pod de `equipo=front` **o**
> cualquier pod `role=frontend` del propio `cka2-mid`).

**Verificación:**
```bash
kubectl run frontend -n cka2-front -l role=frontend --image=curlimages/curl:8.11.1 \
  --command -- sleep 3600
kubectl run intruso  -n cka2-front --image=curlimages/curl:8.11.1 --command -- sleep 3600
kubectl run frontend -n cka2-mid   -l role=frontend --image=curlimages/curl:8.11.1 \
  --command -- sleep 3600
kubectl wait --for=condition=Ready pod --all -n cka2-front --timeout=60s
kubectl wait --for=condition=Ready pod/frontend -n cka2-mid --timeout=60s

# ✅ role=frontend en ns equipo=front → 200
kubectl exec -n cka2-front frontend -- \
  curl -s -m 3 -o /dev/null -w "%{http_code}\n" http://api.cka2-mid
# ❌ sin role=frontend → timeout (exit 28)
kubectl exec -n cka2-front intruso -- curl -s -m 3 http://api.cka2-mid; echo "exit=$?"
# ❌ role=frontend pero en otro namespace → timeout
kubectl exec -n cka2-mid frontend -- curl -s -m 3 http://api; echo "exit=$?"

# Egress: DNS sí, Internet no
kubectl exec -n cka2-front frontend -- nslookup kubernetes.default.svc.cluster.local
kubectl exec -n cka2-front frontend -- curl -s -m 3 -I https://kubernetes.io; echo "exit=$?"
# exit=28 (bloqueado por front-egress)
```

---

## Reto 5 — Ingress por host y path con Traefik, Exact vs Prefix y default backend (10 min)

> En `cka2-mid` despliega tres apps con `hashicorp/http-echo:1.0` (puerto 5678), cada una
> respondiendo un texto distinto: `tienda`, `api-v1` y `por-defecto`. Crea un Ingress
> `ingress-cka2` (clase `traefik`) que:
> - `tienda.cka2.local/` (Prefix) → `tienda`
> - `tienda.cka2.local/api/v1` (**Exact**) → `api-v1`
> - cualquier otra petición → `por-defecto` (default backend)

```bash
# Solución
for app in tienda api-v1 por-defecto; do
  kubectl create deployment $app -n cka2-mid --image=hashicorp/http-echo:1.0 \
    -- /http-echo -text=$app -listen=:5678
  kubectl expose deployment $app -n cka2-mid --port=80 --target-port=5678
done

kubectl create ingress ingress-cka2 -n cka2-mid --class=traefik \
  --rule="tienda.cka2.local/*=tienda:80" \
  --rule="tienda.cka2.local/api/v1=api-v1:80" \
  --default-backend=por-defecto:80 \
  --dry-run=client -o yaml > ingress-cka2.yaml
# "/*" genera pathType Prefix; una ruta sin "*" genera pathType Exact
grep -B1 -A6 "path:" ingress-cka2.yaml
kubectl apply -f ingress-cka2.yaml
```

**Verificación:**
```bash
kubectl get ingress ingress-cka2 -n cka2-mid
# ADDRESS: IPs de los nodos (Service LoadBalancer de Traefik vía ServiceLB)
IP=192.168.252.3

curl -s -H "Host: tienda.cka2.local" http://$IP/            # tienda
curl -s -H "Host: tienda.cka2.local" http://$IP/carrito     # tienda   (Prefix)
curl -s -H "Host: tienda.cka2.local" http://$IP/api/v1      # api-v1   (Exact)
curl -s -H "Host: tienda.cka2.local" http://$IP/api/v1/x    # tienda   (Exact no casa con subrutas)
curl -s -H "Host: otro.local"        http://$IP/            # por-defecto
```

> **En el examen (kubeadm):** el controlador suele ser `nginx` (`--class=nginx`) y se accede por
> el NodePort del ingress-controller (`curl -H "Host: ..." http://<nodo>:<nodePort>`), no por el puerto 80.

---

## Reto 6 — Gateway API: HTTPRoute con pesos (canary 80/20) y match por header (10 min)

> Con el provider Gateway API de Traefik habilitado (ver módulo 12), crea en `cka2-mid` un
> `Gateway` `gw-cka2` (clase `traefik`, listener HTTP en el puerto 8000) y un `HTTPRoute`
> `canary` para `canary.cka2.local` que:
> - envíe las peticiones con el header `x-canary: si` **siempre** a `app-v2`
> - reparta el resto **80 %** a `app-v1` y **20 %** a `app-v2`

```bash
# Prerrequisito (una sola vez por cluster) — si no lo hiciste en el módulo 12
kubectl get gatewayclass traefik 2>/dev/null || \
  kubectl apply -f ../../12-seguridad-networking-avanzado/intermedio/habilitar-gateway-api.yaml
kubectl wait --for=condition=Accepted gatewayclass/traefik --timeout=120s

# Solución
for v in v1 v2; do
  kubectl create deployment app-$v -n cka2-mid --image=hashicorp/http-echo:1.0 \
    -- /http-echo -text=app-$v -listen=:5678
  kubectl expose deployment app-$v -n cka2-mid --port=80 --target-port=5678
done

cat <<'YAML' | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gw-cka2
  namespace: cka2-mid
spec:
  gatewayClassName: traefik
  listeners:
  - name: web
    port: 8000            # entrypoint "web" de Traefik (expuesto como :80 en el LoadBalancer)
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: canary
  namespace: cka2-mid
spec:
  parentRefs:
  - name: gw-cka2
  hostnames:
  - canary.cka2.local
  rules:
  - matches:                       # regla más específica: header
    - headers:
      - name: x-canary
        value: si
    backendRefs:
    - name: app-v2
      port: 80
  - backendRefs:                   # resto del tráfico: reparto por pesos
    - name: app-v1
      port: 80
      weight: 80
    - name: app-v2
      port: 80
      weight: 20
YAML
```

**Verificación:**
```bash
kubectl get gateway gw-cka2 -n cka2-mid
# PROGRAMMED True
kubectl get httproute canary -n cka2-mid \
  -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}{"\n"}'
# True

IP=192.168.252.2
for i in $(seq 1 100); do
  curl -s -H "Host: canary.cka2.local" http://$IP/
done | sort | uniq -c
# ~80 app-v1
# ~20 app-v2

for i in $(seq 1 10); do
  curl -s -H "Host: canary.cka2.local" -H "x-canary: si" http://$IP/
done | sort | uniq -c
# 10 app-v2
```

> Para "promocionar" el canary basta con `kubectl patch`/`edit` de los `weight` (p. ej. 0/100),
> sin tocar los Deployments.

---

## Reto 7 — PV estático `local` con Retain, binding explícito y expansión de PVC (10 min)

> 1. En el nodo `k3s-worker` crea el directorio `/srv/cka2-datos` con un archivo `semilla.txt`.
> 2. Crea un PV `pv-cka2` de 200Mi, tipo `local`, `ReadWriteOnce`, `persistentVolumeReclaimPolicy: Retain`,
>    sin StorageClass y con nodeAffinity a `k3s-worker`.
> 3. Crea un PVC `pvc-cka2` en `cka2-mid` que se enlace **exactamente** a ese PV y un pod `lector` que lo monte.
> 4. Intenta ampliar el PVC a 300Mi y explica el resultado.
> 5. Borra el PVC, comprueba el estado del PV y vuelve a dejarlo `Available` sin perder los datos.

```bash
# Solución
multipass exec k3s-worker -- sudo sh -c 'mkdir -p /srv/cka2-datos && echo "dato-original" > /srv/cka2-datos/semilla.txt'

cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-cka2
spec:
  capacity:
    storage: 200Mi
  accessModes: ["ReadWriteOnce"]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  local:
    path: /srv/cka2-datos
  nodeAffinity:                   # obligatorio para volúmenes "local"
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values: ["k3s-worker"]
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-cka2
  namespace: cka2-mid
spec:
  storageClassName: ""            # "" = no usar la StorageClass por defecto (local-path)
  volumeName: pv-cka2             # binding explícito
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 200Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: lector
  namespace: cka2-mid
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
    volumeMounts:
    - name: datos
      mountPath: /datos
  volumes:
  - name: datos
    persistentVolumeClaim:
      claimName: pvc-cka2
YAML
```

**Verificación:**
```bash
kubectl get pv pv-cka2
# STATUS Bound   CLAIM cka2-mid/pvc-cka2
kubectl get pod lector -n cka2-mid -o wide
# NODE k3s-worker (el scheduler respeta la nodeAffinity del PV)
kubectl exec -n cka2-mid lector -- cat /datos/semilla.txt
# dato-original
kubectl exec -n cka2-mid lector -- sh -c 'echo "escrito-desde-pod" > /datos/nuevo.txt'

# Expansión: rechazada
kubectl patch pvc pvc-cka2 -n cka2-mid -p '{"spec":{"resources":{"requests":{"storage":"300Mi"}}}}'
# Error ... only dynamically provisioned pvc can be resized and the storageclass
#           that provisions the pvc must support resize
kubectl get sc local-path -o jsonpath='{.allowVolumeExpansion}{"\n"}'
# (vacío/false) → local-path tampoco permite expandir sus PVC dinámicos

# Retain: el PV sobrevive al borrado del PVC
kubectl delete pod lector -n cka2-mid --grace-period=0 --force
kubectl delete pvc pvc-cka2 -n cka2-mid
kubectl get pv pv-cka2
# STATUS Released (sigue apuntando al claim borrado; no es reutilizable)

# Reciclar a mano: quitar el claimRef
kubectl patch pv pv-cka2 --type=json -p '[{"op":"remove","path":"/spec/claimRef"}]'
kubectl get pv pv-cka2
# STATUS Available
multipass exec k3s-worker -- cat /srv/cka2-datos/nuevo.txt
# escrito-desde-pod  ← los datos siguen en el nodo
```

> **En el examen (kubeadm):** para expandir un PVC la StorageClass debe tener
> `allowVolumeExpansion: true` y el driver CSI soportarlo; entonces basta con subir
> `spec.resources.requests.storage` (nunca se puede reducir). Comprueba el progreso con
> `kubectl get pvc -o jsonpath='{.status.capacity.storage}'` y las condiciones `FileSystemResizePending`.

---

## Reto 8 — Kustomize: base + overlays dev/prod (10 min)

> En `kustomize/` tienes una `base` (Deployment + Service `tienda` y un `configMapGenerator`)
> y un overlay `overlays/dev`. Crea el overlay `overlays/prod` que:
> - despliegue en el namespace `cka2-prod` con el prefijo `prod-`
> - añada la label `entorno=prod` (sin tocar los selectores)
> - use la imagen `nginx:1.28-alpine` y **3 réplicas**
> - sobrescriba `ENTORNO=produccion` en el ConfigMap generado
> - añada un límite de memoria de `128Mi` mediante un patch
>
> Despliega ambos overlays y comprueba que conviven sin pisarse.

```bash
# Inspeccionar lo que hay
cd kustomize
cat base/kustomization.yaml overlays/dev/kustomization.yaml
kubectl kustomize overlays/dev | grep -E "name:|namespace:|image:"

# Solución — overlays/prod/kustomization.yaml
mkdir -p overlays/prod
cat > overlays/prod/kustomization.yaml <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: cka2-prod
namePrefix: prod-
labels:
- pairs:
    entorno: prod
  includeSelectors: false
resources:
- ../../base
images:
- name: nginx
  newTag: 1.28-alpine
replicas:
- name: tienda
  count: 3
configMapGenerator:
- name: tienda-config
  behavior: merge
  literals:
  - ENTORNO=produccion
patches:
- path: recursos-prod.yaml
YAML

cat > overlays/prod/recursos-prod.yaml <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tienda              # nombre de la base (sin prefijo)
spec:
  template:
    spec:
      containers:
      - name: web
        resources:
          limits:
            memory: 128Mi
YAML

kubectl kustomize overlays/prod          # revisar antes de aplicar
kubectl create namespace cka2-dev
kubectl create namespace cka2-prod
kubectl apply -k overlays/dev
kubectl apply -k overlays/prod
cd ..
```

> El repo ya trae `overlays/prod` como solución de referencia; bórralo antes de empezar si quieres
> hacer el reto "en limpio" (`rm -r kustomize/overlays/prod`).

**Verificación:**
```bash
kubectl get deploy,svc,cm -n cka2-dev
kubectl get deploy,svc,cm -n cka2-prod
# dev-tienda (1 réplica) / prod-tienda (3 réplicas); ConfigMaps con sufijo hash

kubectl get deploy prod-tienda -n cka2-prod \
  -o jsonpath='{.spec.template.spec.containers[0].image} {.spec.template.spec.containers[0].resources.limits.memory}{"\n"}'
# nginx:1.28-alpine 128Mi

# La variable llega al contenedor desde el ConfigMap generado
kubectl exec -n cka2-prod deploy/prod-tienda -- printenv ENTORNO     # produccion
kubectl exec -n cka2-dev  deploy/dev-tienda  -- printenv ENTORNO     # desarrollo

# El Service de prod tiene endpoints (selector intacto) y responde
kubectl get endpoints prod-tienda -n cka2-prod
kubectl run curl-test -n cka2-prod --rm -it --restart=Never --image=curlimages/curl:8.11.1 -- \
  curl -s -o /dev/null -w "%{http_code}\n" http://prod-tienda
# 200
```

> Cambiar un literal del `configMapGenerator` cambia el hash del nombre del ConfigMap y, por tanto,
> provoca un rollout automático del Deployment: Kustomize resuelve así el clásico "cambié el
> ConfigMap y los pods no se enteraron".

---

## Reto 9 — Helm: instalar, actualizar de versión, inspeccionar y hacer rollback (10 min)

> 1. Añade el repo `podinfo` (`https://stefanprodan.github.io/podinfo`) e instala el chart `podinfo`
>    **versión 6.9.0** como release `web` en `cka2-helm` (créalo con Helm) con `replicaCount=2`
> 2. Actualiza a la versión **6.10.0** conservando tus valores y añadiendo `ui.message=v2`
> 3. Muestra los valores de usuario de cada revisión y vuelve a la **revisión 1**
> 4. Guarda en `/tmp/podinfo-values.yaml` los valores por defecto del chart 6.9.0

```bash
# Solución
helm repo add podinfo https://stefanprodan.github.io/podinfo
helm repo update
helm search repo podinfo/podinfo --versions | head -5

helm install web podinfo/podinfo --version 6.9.0 \
  -n cka2-helm --create-namespace --set replicaCount=2 --wait

# Actualizar de versión del chart conservando valores
helm upgrade web podinfo/podinfo --version 6.10.0 -n cka2-helm \
  --reset-then-reuse-values --set ui.message=v2 --wait

helm history web -n cka2-helm
helm get values web -n cka2-helm --revision 1      # replicaCount: 2
helm get values web -n cka2-helm --revision 2      # replicaCount: 2 + ui.message: v2

helm rollback web 1 -n cka2-helm --wait
helm show values podinfo/podinfo --version 6.9.0 > /tmp/podinfo-values.yaml
```

> **Trampa real:** `helm upgrade --reuse-values` hacia una versión **nueva** del chart reutiliza los
> valores *calculados* de la release anterior y descarta los defaults nuevos del chart → aquí falla con
> `nil pointer evaluating interface {}.enabled`. `--reset-then-reuse-values` (Helm ≥ 3.14) parte de los
> defaults del chart nuevo y aplica encima tus valores. Alternativa clásica: `-f mis-valores.yaml`.

**Verificación:**
```bash
helm list -n cka2-helm
# web  REVISION 3  deployed  podinfo-6.9.0  6.9.0
helm history web -n cka2-helm | tail -1          # 3 ... Rollback to 1
kubectl get deploy -n cka2-helm web-podinfo \
  -o jsonpath='{.spec.replicas} {.spec.template.spec.containers[0].image}{"\n"}'
# 2 ghcr.io/stefanprodan/podinfo:6.9.0
kubectl get secrets -n cka2-helm -l owner=helm     # Helm guarda cada revisión como Secret
grep -c "" /tmp/podinfo-values.yaml
```

---

## Reto 10 — CustomResourceDefinition y recursos personalizados (10 min)

> Crea la CRD `backups.cka2.example.com` (namespaced, kind `Backup`, nombre corto `bk`) con versión
> `v1` y un esquema que exija `spec.origen` (string) y `spec.retencionDias` (entero entre 1 y 30),
> y una columna extra `RETENCION` en `kubectl get`. Crea `bk-diario` en `cka2-mid` y demuestra que
> la API rechaza un `Backup` con `retencionDias: 90`.

```bash
# Solución
cat <<'EOF' | kubectl apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: backups.cka2.example.com        # <plural>.<grupo>
spec:
  group: cka2.example.com
  scope: Namespaced
  names:
    kind: Backup
    plural: backups
    singular: backup
    shortNames: ["bk"]
  versions:
  - name: v1
    served: true
    storage: true
    additionalPrinterColumns:
    - name: RETENCION
      type: integer
      jsonPath: .spec.retencionDias
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            required: ["origen", "retencionDias"]
            properties:
              origen:
                type: string
              retencionDias:
                type: integer
                minimum: 1
                maximum: 30
EOF

kubectl wait --for=condition=Established crd/backups.cka2.example.com
cat <<'EOF' | kubectl apply -f -
apiVersion: cka2.example.com/v1
kind: Backup
metadata:
  name: bk-diario
  namespace: cka2-mid
spec:
  origen: pvc/datos-kv-0
  retencionDias: 7
EOF
```

**Verificación:**
```bash
kubectl api-resources --api-group=cka2.example.com     # backups  bk  cka2.example.com/v1  true  Backup
kubectl get bk -n cka2-mid                             # NAME bk-diario  RETENCION 7
kubectl explain backup.spec                            # el esquema documenta la API
cat <<'EOF' | kubectl apply -f -
apiVersion: cka2.example.com/v1
kind: Backup
metadata:
  name: bk-malo
  namespace: cka2-mid
spec:
  origen: pvc/x
  retencionDias: 90
EOF
# The Backup "bk-malo" is invalid: spec.retencionDias: Invalid value: 90: ... should be less than or equal to 30
```

> Una CRD solo **almacena y valida** objetos; el comportamiento lo aporta un **operador** (controlador
> que observa esos objetos). En el examen te pueden pedir listar CRDs de un operador instalado
> (`kubectl get crd | grep <grupo>`) o crear/consultar sus recursos.

---

## Reto 11 — PriorityClass y preempción (10 min)

> 1. Crea las PriorityClasses `cka2-baja` (100) y `cka2-alta` (100000), ninguna por defecto
> 2. En `cka2-mid`, despliega `batch` (3 réplicas, `busybox:1.36 sleep 3600`, `cka2-baja`, request `500m` de CPU)
>    fijado a `k3s-worker2`
> 3. Crea el pod `critico` (`nginx:alpine`, `cka2-alta`, request `800m`) en el mismo nodo
> 4. Explica qué pasa con `batch` y por qué

```bash
# Solución
kubectl create priorityclass cka2-baja --value=100 --description="trabajos batch"
kubectl create priorityclass cka2-alta --value=100000 --description="servicios críticos"
kubectl get node k3s-worker2 -o jsonpath='{.status.allocatable.cpu}{"\n"}'      # 2

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: batch
  namespace: cka2-mid
spec:
  replicas: 3
  selector:
    matchLabels:
      app: batch
  template:
    metadata:
      labels:
        app: batch
    spec:
      priorityClassName: cka2-baja
      nodeSelector:
        kubernetes.io/hostname: k3s-worker2
      containers:
      - name: batch
        image: busybox:1.36
        command: ["sleep", "3600"]
        resources:
          requests:
            cpu: 500m
EOF
kubectl rollout status deploy/batch -n cka2-mid      # 3 × 500m = 1500m ocupados

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: critico
  namespace: cka2-mid
spec:
  priorityClassName: cka2-alta
  nodeSelector:
    kubernetes.io/hostname: k3s-worker2
  containers:
  - name: nginx
    image: nginx:alpine
    resources:
      requests:
        cpu: 800m
EOF
```

**Verificación:**
```bash
kubectl get events -n cka2-mid --field-selector reason=Preempted
# Preempted by pod ... on node k3s-worker2
kubectl get pods -n cka2-mid -o wide -l app=batch       # 2 Running + 1 Pending (sin hueco)
kubectl get pod critico -n cka2-mid -o jsonpath='{.spec.priority} {.status.phase}{"\n"}'
# 100000 Running   (el admission controller resuelve priorityClassName → spec.priority)
kubectl get pc
```

> El scheduler **desaloja** pods de menor prioridad para hacer hueco (respetando PDBs "en la medida de lo
> posible"). `preemptionPolicy: Never` da prioridad en la cola sin desalojar a nadie. El cluster ya trae
> `system-cluster-critical` y `system-node-critical`; usa una sola `globalDefault: true` como mucho.

---

## Reto 12 — ValidatingAdmissionPolicy (CEL) (10 min)

> En los namespaces con la label `politica=estricta`, rechaza Deployments que:
> - tengan más de **3 réplicas** (también al hacer `kubectl scale`)
> - usen imágenes **sin tag** o con tag `:latest`
>
> Aplícalo a `cka2-mid` y demuestra los tres rechazos.

```bash
# Solución
cat <<'EOF' | kubectl apply -f -
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: cka2-deploy-estricto
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
    - apiGroups: ["apps"]
      apiVersions: ["v1"]
      operations: ["CREATE", "UPDATE"]
      resources: ["deployments", "deployments/scale"]   # sin /scale, "kubectl scale" se la salta
  validations:
  - expression: "object.spec.replicas <= 3"
    message: "máximo 3 réplicas"
  - expression: >-
      !has(object.spec.template) ||
      object.spec.template.spec.containers.all(c, c.image.contains(':') && !c.image.endsWith(':latest'))
    messageExpression: "'imagen sin tag fijo en ' + object.metadata.name"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: cka2-deploy-estricto
spec:
  policyName: cka2-deploy-estricto
  validationActions: ["Deny"]
  matchResources:
    namespaceSelector:
      matchLabels:
        politica: estricta
EOF
kubectl label namespace cka2-mid politica=estricta
```

**Verificación:**
```bash
kubectl create deployment v1 -n cka2-mid --image=nginx:alpine --replicas=5
# denied request: máximo 3 réplicas
kubectl create deployment v2 -n cka2-mid --image=nginx
# denied request: imagen sin tag fijo en v2
kubectl create deployment v3 -n cka2-mid --image=nginx:alpine --replicas=2     # created
kubectl scale deployment v3 -n cka2-mid --replicas=6
# denied request: máximo 3 réplicas
kubectl create deployment v4 -n default --image=nginx --replicas=5             # created (namespace sin label)
kubectl delete deployment v4 -n default
```

> En `deployments/scale` el objeto es un `Scale` (sin `spec.template`): por eso la guarda `!has(object.spec.template)`.
> `validationActions` admite `Deny`, `Warn` y `Audit`: empieza con `Warn` en producción.

---

## Reto 13 — ClusterRole reutilizable, ServiceAccount y token de corta duración (10 min)

> 1. Crea la ClusterRole `cka2-lector-apps` (get/list/watch de deployments, replicasets y pods)
> 2. Concede esa ClusterRole a la ServiceAccount `ci-bot` **solo** en `cka2-mid` y `cka2-helm`
> 3. Genera un token de **10 minutos** para `ci-bot` y úsalo con `kubectl` sin tocar tu kubeconfig

```bash
# Solución
kubectl create clusterrole cka2-lector-apps --verb=get,list,watch \
  --resource=deployments.apps,replicasets.apps,pods
kubectl create serviceaccount ci-bot -n cka2-mid

# RoleBinding (namespaced) → la ClusterRole solo aplica en ESE namespace
kubectl create rolebinding ci-bot-lectura -n cka2-mid  --clusterrole=cka2-lector-apps --serviceaccount=cka2-mid:ci-bot
kubectl create rolebinding ci-bot-lectura -n cka2-helm --clusterrole=cka2-lector-apps --serviceaccount=cka2-mid:ci-bot

TOKEN=$(kubectl create token ci-bot -n cka2-mid --duration=10m)

# Tu kubeconfig ya trae un certificado de cliente, y el API server lo autentica ANTES que el token:
# para actuar como ci-bot usa un kubeconfig vacío con solo server + CA + token
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
kubectl config view --raw --minify \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > /tmp/ca.crt
kbot() { kubectl --kubeconfig=/dev/null --server="$SERVER" --certificate-authority=/tmp/ca.crt --token="$TOKEN" "$@"; }
```

**Verificación:**
```bash
kbot auth whoami                                       # system:serviceaccount:cka2-mid:ci-bot
kbot get deploy -n cka2-helm                           # permitido
kbot get deploy -n default                             # Forbidden
kbot delete pod --all -n cka2-mid                      # Forbidden
kubectl auth can-i --list -n cka2-mid --as=system:serviceaccount:cka2-mid:ci-bot | grep -E "deployments|pods"
echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | grep -o '"exp":[0-9]*'   # caduca en 10 min
rm /tmp/ca.crt
```

> **ClusterRole + RoleBinding** = definir los permisos una vez y concederlos namespace a namespace.
> **ClusterRole + ClusterRoleBinding** = en todo el cluster. Un Role nunca puede usarse en un ClusterRoleBinding.

---

## Reto 14 — Cambiar la StorageClass por defecto (10 min)

> Crea la StorageClass `cka2-retain` (provisioner `rancher.io/local-path`, `Retain`,
> `WaitForFirstConsumer`) y hazla la **única** StorageClass por defecto. Comprueba que un PVC
> **sin** `storageClassName` la usa. Al terminar, deja `local-path` otra vez como predeterminada.

```bash
# Solución
cat <<'EOF' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: cka2-retain
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: rancher.io/local-path
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
EOF
kubectl patch storageclass local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl get sc                    # solo cka2-retain (default)

kubectl create -n cka2-mid -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-sin-clase
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 32Mi
EOF
kubectl run usa-pvc -n cka2-mid --image=busybox:1.36 \
  --overrides='{"spec":{"volumes":[{"name":"d","persistentVolumeClaim":{"claimName":"pvc-sin-clase"}}],"containers":[{"name":"c","image":"busybox:1.36","command":["sleep","3600"],"volumeMounts":[{"name":"d","mountPath":"/d"}]}]}}'
```

**Verificación:**
```bash
kubectl get pvc pvc-sin-clase -n cka2-mid -o jsonpath='{.spec.storageClassName} {.status.phase}{"\n"}'
# cka2-retain Bound   (el admission controller DefaultStorageClass la asignó al crear el PVC)
kubectl get pv -o custom-columns='PV:.metadata.name,CLASE:.spec.storageClassName,RECLAIM:.spec.persistentVolumeReclaimPolicy' | grep cka2-retain

# Restaurar
kubectl patch storageclass local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl patch storageclass cka2-retain \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl get sc                    # local-path (default)
```

> En k3s, al reiniciar el server el addon vuelve a marcar `local-path` como default. Con **dos**
> StorageClasses por defecto, Kubernetes usa la más reciente: quita siempre la anotación de la otra.

---

## Reto 15 — Downward API y volumen proyectado (10 min)

> Crea el pod `info` en `cka2-mid` (`busybox:1.36`, label `equipo=plataforma`, request `50m`/`32Mi`, limit `64Mi`) que:
> - exponga como variables `NODO`, `POD_IP` y `CPU_REQ` (en milicores)
> - monte en `/etc/info` un **único** volumen proyectado con: las labels del pod (`labels`),
>   el ConfigMap `app-settings` (clave `modo`) y el Secret `db-cred` (clave `password`)

```bash
# Solución
kubectl create configmap app-settings -n cka2-mid --from-literal=modo=produccion
kubectl create secret generic db-cred -n cka2-mid --from-literal=password=Sup3rS3cr3t

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: info
  namespace: cka2-mid
  labels:
    equipo: plataforma
spec:
  containers:
  - name: info
    image: busybox:1.36
    command: ["sleep", "3600"]
    resources:
      requests:
        cpu: 50m
        memory: 32Mi
      limits:
        memory: 64Mi
    env:
    - name: NODO
      valueFrom:
        fieldRef:
          fieldPath: spec.nodeName
    - name: POD_IP
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
    - name: CPU_REQ
      valueFrom:
        resourceFieldRef:
          containerName: info
          resource: requests.cpu
          divisor: 1m
    volumeMounts:
    - name: todo
      mountPath: /etc/info
      readOnly: true
  volumes:
  - name: todo
    projected:
      sources:
      - downwardAPI:
          items:
          - path: labels
            fieldRef:
              fieldPath: metadata.labels
      - configMap:
          name: app-settings
          items:
          - key: modo
            path: modo
      - secret:
          name: db-cred
          items:
          - key: password
            path: password
EOF
kubectl wait --for=condition=Ready pod/info -n cka2-mid
```

**Verificación:**
```bash
kubectl exec -n cka2-mid info -- sh -c 'echo $NODO $POD_IP $CPU_REQ'
# k3s-worker 10.42.x.x 50
kubectl exec -n cka2-mid info -- ls /etc/info          # labels  modo  password
kubectl exec -n cka2-mid info -- cat /etc/info/labels  # equipo="plataforma"
kubectl label pod info -n cka2-mid version=2
sleep 60; kubectl exec -n cka2-mid info -- cat /etc/info/labels
# aparece version="2": el volumen se actualiza; las variables de entorno NO
```

---

## Reto 16 — Service sin selector + EndpointSlice manual hacia un servicio externo (10 min)

> Los pods de `cka2-mid` deben llegar a la "API heredada" (que es el API server, `<IP de k3s-server>:6443`)
> por el nombre `api-externa` en el puerto **443**, sin `ExternalName` (hay que apuntar a una IP).

```bash
# Solución
SERVER_IP=$(kubectl get node k3s-server -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: api-externa
  namespace: cka2-mid
spec:                     # sin selector: Kubernetes no gestiona sus endpoints
  ports:
  - name: https
    port: 443
    targetPort: 6443
---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: api-externa-1
  namespace: cka2-mid
  labels:
    kubernetes.io/service-name: api-externa            # así se asocia al Service
    endpointslice.kubernetes.io/managed-by: cka2-admin # cualquier valor distinto del controlador
addressType: IPv4
ports:
- name: https             # debe coincidir con el nombre del puerto del Service
  port: 6443
endpoints:
- addresses: ["$SERVER_IP"]
EOF
```

**Verificación:**
```bash
kubectl describe svc api-externa -n cka2-mid | grep -E "Selector|Endpoints"
# Selector: <none>   Endpoints: 192.168.252.2:6443
kubectl run t -n cka2-mid --rm -i --restart=Never --image=curlimages/curl:8.11.1 -- \
  curl -sk -m 5 -o /dev/null -w "%{http_code}\n" https://api-externa/version
# 401 → llegamos al API server (sin credenciales); la conexión funciona
```

> **ExternalName** solo crea un CNAME (no sirve para IPs ni remapea puertos). **Service sin selector +
> EndpointSlice** sí: es el patrón para BDs externas o migraciones graduales hacia el cluster.

---

## Limpieza final

```bash
kubectl config set-context --current --namespace=default
kubectl delete -k kustomize/overlays/dev --ignore-not-found
kubectl delete -k kustomize/overlays/prod --ignore-not-found
helm uninstall web -n cka2-helm 2>/dev/null; helm repo remove podinfo 2>/dev/null
kubectl delete namespace cka2-mid cka2-front cka2-dev cka2-prod cka2-helm --ignore-not-found
kubectl delete pv pv-cka2 --ignore-not-found
kubectl delete crd backups.cka2.example.com --ignore-not-found
kubectl delete priorityclass cka2-baja cka2-alta --ignore-not-found
kubectl delete validatingadmissionpolicybinding cka2-deploy-estricto --ignore-not-found
kubectl delete validatingadmissionpolicy cka2-deploy-estricto --ignore-not-found
kubectl delete clusterrole cka2-lector-apps --ignore-not-found
kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl delete storageclass cka2-retain --ignore-not-found
# Los PV Retain de cka2-retain quedan Released: bórralos a mano
kubectl get pv --no-headers | awk '$5=="Released" {print $1}' | xargs -r kubectl delete pv
rm -f /tmp/podinfo-values.yaml
multipass exec k3s-worker -- sudo rm -rf /srv/cka2-datos
# Los PVC datos-kv-* del Reto 1 se borran con el namespace; local-path borra sus directorios (Delete)
```

---

## Preguntas de reflexión para el instructor

1. ¿Por qué un StatefulSet necesita un Service headless y qué se pierde si usas un Service normal?
2. ¿Qué diferencia hay entre `completionMode: Indexed` y `NonIndexed`, y cuándo importa?
3. ¿Qué problema resolvieron los sidecars nativos que no tenían los sidecars en `containers`?
4. En una NetworkPolicy, ¿cómo distingues visualmente un AND de un OR entre `namespaceSelector` y `podSelector`?
5. ¿Qué ventaja tiene repartir tráfico por pesos en un `HTTPRoute` frente a jugar con el número de réplicas detrás de un mismo Service?
6. ¿Por qué un PV con `Retain` queda `Released` y no `Available` tras borrar el PVC?
7. ¿Por qué `helm upgrade --reuse-values` puede romper al cambiar de versión de chart y qué hace distinto `--reset-then-reuse-values`?
8. Una CRD sin operador, ¿para qué sirve? ¿Qué aporta el esquema OpenAPI?
9. ¿Qué riesgos tiene la preempción para cargas `batch` y cómo los mitigarías?
10. ¿Por qué una ValidatingAdmissionPolicy sobre `deployments` no ve un `kubectl scale`?
11. ¿Cuándo usarías ClusterRole + RoleBinding en vez de un Role por namespace?
12. ¿Qué diferencia hay entre un Service `ExternalName` y uno sin selector con EndpointSlice manual?
