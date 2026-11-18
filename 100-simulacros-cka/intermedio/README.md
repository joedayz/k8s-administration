# Lab 100 — Intermedio: Retos de Dificultad Media (Workloads, Red y Almacenamiento)

## Objetivo
Resolver ejercicios de ~10 minutos que combinan varios objetos de Kubernetes: StatefulSets, Jobs, sidecars nativos, NetworkPolicy, Ingress, Gateway API, PV estáticos y Kustomize. Ninguno repite los retos del módulo 99 (allí ya se hicieron SA+Role, Ingress TLS, PVC dinámico, deny-all con DNS y ClusterRole de nodos).

## Duración estimada
90 minutos (8 retos × 10 min + revisión)

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

## Limpieza final

```bash
kubectl config set-context --current --namespace=default
kubectl delete -k kustomize/overlays/dev --ignore-not-found
kubectl delete -k kustomize/overlays/prod --ignore-not-found
kubectl delete namespace cka2-mid cka2-front cka2-dev cka2-prod
kubectl delete pv pv-cka2
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
