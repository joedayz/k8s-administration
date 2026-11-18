# Lab 100 — Básico: Retos Rápidos (Configuración, Rollouts y Scheduling)

## Objetivo
Resolver ejercicios cortos con límite de tiempo, estilo examen CKA. Cada reto dura ~5 minutos. Ninguno repite los retos del módulo 99.

## Duración estimada
60 minutos (10 retos × 5 min + revisión)

> Todos los retos usan el namespace `cka2` (salvo el Reto 9). Créalo una vez al inicio:
> ```bash
> kubectl create namespace cka2
> ```

---

## Reto 1 — ConfigMap montado como un solo archivo con subPath (4 min)

> Crea un ConfigMap `web-index` en el namespace `cka2` a partir de un archivo `index.html`
> con el contenido `<h1>Simulacro CKA II</h1>`. Crea un pod `web-subpath` (`nginx:alpine`)
> que monte **solo** esa clave en `/usr/share/nginx/html/index.html`, sin ocultar el resto
> de archivos del directorio (por ejemplo `50x.html`).

```bash
# Solución
echo '<h1>Simulacro CKA II</h1>' > index.html
kubectl create configmap web-index --from-file=index.html -n cka2
rm index.html

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: web-subpath
  namespace: cka2
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    volumeMounts:
    - name: index
      mountPath: /usr/share/nginx/html/index.html
      subPath: index.html
  volumes:
  - name: index
    configMap:
      name: web-index
EOF
```

**Verificación:**
```bash
kubectl exec web-subpath -n cka2 -- ls /usr/share/nginx/html
# Debe listar 50x.html e index.html (sin subPath, el montaje taparía 50x.html)
kubectl exec web-subpath -n cka2 -- wget -qO- http://localhost
# Debe mostrar: <h1>Simulacro CKA II</h1>
```

> ⚠️ Un volumen montado con `subPath` **no recibe actualizaciones** del ConfigMap: si lo cambias, hay que recrear el pod.

---

## Reto 2 — Variables de entorno desde claves concretas de ConfigMap y Secret (3 min)

> En el namespace `cka2`:
> - Crea el ConfigMap `app-settings` con `modo=produccion`
> - Crea el Secret `db-cred` con `password=Sup3rS3cr3t`
> - Crea el pod `env-pod` (`busybox:1.36`, comando `sleep 3600`) con **exactamente** dos variables:
>   `APP_MODE` (desde la clave `modo`) y `DB_PASS` (desde la clave `password`)

```bash
# Solución
kubectl create configmap app-settings --from-literal=modo=produccion -n cka2
kubectl create secret generic db-cred --from-literal=password=Sup3rS3cr3t -n cka2

kubectl run env-pod --image=busybox:1.36 -n cka2 \
  --dry-run=client -o yaml --command -- sleep 3600 > env-pod.yaml
# Editar para añadir env con valueFrom
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: env-pod
  namespace: cka2
spec:
  containers:
  - name: env-pod
    image: busybox:1.36
    command: ["sleep", "3600"]
    env:
    - name: APP_MODE
      valueFrom:
        configMapKeyRef:
          name: app-settings
          key: modo
    - name: DB_PASS
      valueFrom:
        secretKeyRef:
          name: db-cred
          key: password
```

```bash
kubectl apply -f env-pod.yaml && rm env-pod.yaml
```

**Verificación:**
```bash
kubectl exec env-pod -n cka2 -- env | grep -E 'APP_MODE|DB_PASS'
# APP_MODE=produccion
# DB_PASS=Sup3rS3cr3t
```

> A diferencia de `envFrom` (que importa todas las claves con su propio nombre), `valueFrom` permite **renombrar** y elegir claves sueltas.

---

## Reto 3 — Rolling update controlado y rollback a una revisión concreta (5 min)

> En el namespace `cka2`:
> 1. Crea el deployment `rolling` con 4 réplicas de `nginx:1.27-alpine`, con estrategia
>    `maxSurge: 1` y `maxUnavailable: 0`
> 2. Actualiza a `nginx:1.28-alpine` registrando el motivo del cambio
> 3. Actualiza a `nginx:9.9-noexiste` (rollout roto) y comprueba que la app **sigue sirviendo** 4 pods
> 4. Vuelve **a la revisión 1** (no a la anterior)

```bash
# Solución
kubectl create deployment rolling --image=nginx:1.27-alpine --replicas=4 -n cka2
kubectl patch deployment rolling -n cka2 \
  -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}'
kubectl rollout status deployment/rolling -n cka2

# Revisión 2
kubectl set image deployment/rolling nginx=nginx:1.28-alpine -n cka2
kubectl annotate deployment rolling -n cka2 kubernetes.io/change-cause="subir a 1.28"
kubectl rollout status deployment/rolling -n cka2

# Revisión 3 (rota)
kubectl set image deployment/rolling nginx=nginx:9.9-noexiste -n cka2
kubectl annotate deployment rolling -n cka2 kubernetes.io/change-cause="imagen rota" --overwrite
kubectl rollout status deployment/rolling -n cka2 --timeout=30s   # falla por timeout
kubectl get pods -n cka2 -l app=rolling
# 4 pods Running (1.28) + 1 pod ErrImagePull/ImagePullBackOff: maxUnavailable=0 protege la app

# Rollback a la revisión 1
kubectl rollout history deployment/rolling -n cka2
kubectl rollout history deployment/rolling -n cka2 --revision=1
kubectl rollout undo deployment/rolling -n cka2 --to-revision=1
kubectl rollout status deployment/rolling -n cka2
```

**Verificación:**
```bash
kubectl get deployment rolling -n cka2 \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
# nginx:1.27-alpine
kubectl rollout history deployment/rolling -n cka2
# La revisión 1 desaparece y reaparece como revisión 4
```

---

## Reto 4 — CronJob con política de concurrencia e historial (4 min)

> Crea un CronJob `limpieza` en el namespace `cka2` que:
> - Se ejecute cada 2 minutos en la zona horaria `America/Lima`
> - Use `busybox:1.36` con el comando `sh -c 'date; echo limpiando; sleep 20'`
> - **No** permita ejecuciones concurrentes
> - Conserve solo 2 jobs exitosos y 1 fallido
> - Lánzalo una vez manualmente sin esperar al horario

```bash
# Solución
kubectl create cronjob limpieza --image=busybox:1.36 \
  --schedule="*/2 * * * *" -n cka2 \
  --dry-run=client -o yaml -- sh -c 'date; echo limpiando; sleep 20' > cron.yaml
# Editar: timeZone, concurrencyPolicy e historial
```

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: limpieza
  namespace: cka2
spec:
  schedule: "*/2 * * * *"
  timeZone: "America/Lima"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: limpieza
            image: busybox:1.36
            command: ["sh", "-c", "date; echo limpiando; sleep 20"]
```

```bash
kubectl apply -f cron.yaml && rm cron.yaml

# Ejecución manual a partir del CronJob
kubectl create job limpieza-manual --from=cronjob/limpieza -n cka2
```

**Verificación:**
```bash
kubectl get cronjob limpieza -n cka2 \
  -o jsonpath='{.spec.concurrencyPolicy} {.spec.successfulJobsHistoryLimit} {.spec.failedJobsHistoryLimit} {.spec.timeZone}{"\n"}'
# Forbid 2 1 America/Lima
kubectl logs job/limpieza-manual -n cka2
# Pasados unos minutos, nunca habrá más de 2 jobs "Complete" del CronJob
kubectl get jobs -n cka2 -w
```

---

## Reto 5 — Startup, readiness y liveness probes (4 min)

> Crea el pod `probes` (`nginx:alpine`) en el namespace `cka2` con:
> - **startupProbe**: TCP al puerto 80, cada 2 s, hasta 30 fallos
> - **livenessProbe**: HTTP GET `/` al puerto 80, cada 10 s
> - **readinessProbe**: el pod solo está listo si existe el archivo `/tmp/ready` (cada 3 s)
>
> Comprueba que arranca `0/1`, márcalo como listo y luego quítale la marca: **no debe reiniciarse**.

```bash
# Solución
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: probes
  namespace: cka2
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    startupProbe:
      tcpSocket:
        port: 80
      periodSeconds: 2
      failureThreshold: 30
    livenessProbe:
      httpGet:
        path: /
        port: 80
      periodSeconds: 10
    readinessProbe:
      exec:
        command: ["cat", "/tmp/ready"]
      periodSeconds: 3
EOF

kubectl get pod probes -n cka2          # READY 0/1, STATUS Running
kubectl exec probes -n cka2 -- touch /tmp/ready
sleep 5
kubectl get pod probes -n cka2          # READY 1/1
kubectl exec probes -n cka2 -- rm /tmp/ready
sleep 5
kubectl get pod probes -n cka2          # READY 0/1, RESTARTS 0
```

**Verificación:**
```bash
kubectl get pod probes -n cka2 -o jsonpath='{.status.containerStatuses[0].restartCount}{"\n"}'
# 0 → la readiness solo saca el pod de los endpoints; la liveness es la que reinicia
kubectl describe pod probes -n cka2 | grep -E 'Liveness|Readiness|Startup'
```

---

## Reto 6 — Nodo dedicado: taint + toleration + nodeSelector (4 min)

> El nodo `k3s-worker2` se dedicará a bases de datos:
> 1. Etiquétalo con `disco=ssd` y aplícale el taint `dedicado=bd:NoSchedule`
> 2. Crea el pod `bd-redis` (`redis:alpine`) en `cka2` que se ejecute **obligatoriamente** en ese nodo
> 3. Demuestra que un pod con el `nodeSelector` pero **sin** toleración queda Pending

```bash
# Solución
kubectl label node k3s-worker2 disco=ssd
kubectl taint node k3s-worker2 dedicado=bd:NoSchedule

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: bd-redis
  namespace: cka2
spec:
  nodeSelector:
    disco: ssd
  tolerations:
  - key: dedicado
    operator: Equal
    value: bd
    effect: NoSchedule
  containers:
  - name: redis
    image: redis:alpine
EOF

# Pod de control: nodeSelector sin toleración
kubectl run sin-toleracion --image=redis:alpine -n cka2 \
  --overrides='{"spec":{"nodeSelector":{"disco":"ssd"}}}'
```

**Verificación:**
```bash
kubectl get pod bd-redis sin-toleracion -n cka2 -o wide
# bd-redis       Running  k3s-worker2
# sin-toleracion Pending  <none>
kubectl events -n cka2 --for pod/sin-toleracion
# ... untolerated taint {dedicado: bd} ...

# Limpieza del nodo
kubectl delete pod sin-toleracion -n cka2
kubectl taint node k3s-worker2 dedicado=bd:NoSchedule-
kubectl label node k3s-worker2 disco-
```

> La toleración **permite** entrar al nodo pero no **obliga**; el `nodeSelector` obliga pero no basta si hay taint. Un nodo dedicado necesita ambos.

---

## Reto 7 — custom-columns, sort-by y eventos (3 min)

> 1. Guarda en `nodos.txt` una tabla con columnas `NOMBRE`, `IP_INTERNA`, `KUBELET` y `SO` de todos los nodos
> 2. Muestra los 3 pods del cluster con **más reinicios** (ordenados)
> 3. Guarda en `warnings.txt` los eventos `Warning` del namespace `kube-system`, del más antiguo al más reciente

```bash
# Solución
kubectl get nodes -o custom-columns='NOMBRE:.metadata.name,IP_INTERNA:.status.addresses[?(@.type=="InternalIP")].address,KUBELET:.status.nodeInfo.kubeletVersion,SO:.status.nodeInfo.osImage' > nodos.txt
cat nodos.txt

kubectl get pods -A --sort-by='.status.containerStatuses[0].restartCount' | tail -3

kubectl get events -n kube-system --field-selector type=Warning \
  --sort-by=.lastTimestamp > warnings.txt
cat warnings.txt
```

**Verificación:**
```bash
head -1 nodos.txt
# NOMBRE   IP_INTERNA   KUBELET   SO
grep k3s-server nodos.txt
# k3s-server   192.168.252.2   v1.37.x+k3s1   Ubuntu 22.04.x LTS
rm nodos.txt warnings.txt
```

> Con `kubectl events` (subcomando moderno) el equivalente es `kubectl events -n kube-system --types=Warning`, que ya ordena por tiempo.

---

## Reto 8 — Static pod en un worker (4 min)

> Crea un static pod `static-cache` (`redis:alpine`, namespace `cka2`, label `tipo=estatico`)
> en el nodo `k3s-worker2`. Demuestra que borrarlo con kubectl no lo elimina y luego retíralo correctamente.

```bash
# Solución — en k3s el kubelet de cada nodo lee /var/lib/rancher/k3s/agent/pod-manifests
multipass exec k3s-worker2 -- sudo tee /var/lib/rancher/k3s/agent/pod-manifests/static-cache.yaml > /dev/null <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: static-cache
  namespace: cka2
  labels:
    tipo: estatico
spec:
  containers:
  - name: redis
    image: redis:alpine
EOF

sleep 15
kubectl get pods -n cka2 -l tipo=estatico -o wide
# static-cache-k3s-worker2   Running   k3s-worker2   ← "mirror pod": nombre + sufijo del nodo

# El dueño del mirror pod es el nodo, no un controlador
kubectl get pod static-cache-k3s-worker2 -n cka2 \
  -o jsonpath='{.metadata.ownerReferences[0].kind}{"\n"}'
# Node

# Intentar borrarlo desde la API
kubectl delete pod static-cache-k3s-worker2 -n cka2
sleep 5
kubectl get pods -n cka2 -l tipo=estatico      # ¡vuelve a aparecer!

# Retirarlo de verdad: borrar el manifiesto en el nodo
multipass exec k3s-worker2 -- sudo rm /var/lib/rancher/k3s/agent/pod-manifests/static-cache.yaml
```

**Verificación:**
```bash
sleep 10
kubectl get pods -n cka2 -l tipo=estatico
# No resources found
```

> **En el examen (kubeadm):** entra por `ssh` al nodo, busca la ruta con `grep staticPodPath /var/lib/kubelet/config.yaml` (normalmente `/etc/kubernetes/manifests`) y deja ahí el YAML. Puedes generarlo con `kubectl run static-cache --image=redis:alpine --dry-run=client -o yaml`.

---

## Reto 9 — LimitRange + ResourceQuota (5 min)

> En un namespace nuevo `cka2-quota`:
> 1. Crea un LimitRange que asigne por defecto `requests` de `100m`/`64Mi` y `limits` de `200m`/`128Mi` a cada contenedor
> 2. Crea una ResourceQuota `cuota-cka2` con máximo `3` pods, `requests.cpu=500m` y `limits.memory=1Gi`
> 3. Crea el deployment `cuota-app` con 5 réplicas de `nginx:alpine` **sin** resources
> 4. Explica por qué solo hay 3 pods y qué resources tienen

```bash
# Solución
kubectl create namespace cka2-quota

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: LimitRange
metadata:
  name: defaults-cka2
  namespace: cka2-quota
spec:
  limits:
  - type: Container
    defaultRequest:
      cpu: 100m
      memory: 64Mi
    default:
      cpu: 200m
      memory: 128Mi
EOF

kubectl create quota cuota-cka2 -n cka2-quota \
  --hard=pods=3,requests.cpu=500m,limits.memory=1Gi

kubectl create deployment cuota-app --image=nginx:alpine --replicas=5 -n cka2-quota
```

**Verificación:**
```bash
kubectl get pods -n cka2-quota
# Solo 3 pods
kubectl describe quota cuota-cka2 -n cka2-quota
# pods 3/3, requests.cpu 300m/500m, limits.memory 384Mi/1Gi
kubectl get events -n cka2-quota --field-selector reason=FailedCreate
# ... exceeded quota: cuota-cka2, requested: pods=1, used: pods=3, limited: pods=3
kubectl get pod -n cka2-quota -l app=cuota-app \
  -o jsonpath='{.items[0].spec.containers[0].resources}{"\n"}'
# Los requests/limits los inyectó el LimitRange
```

> Crea el LimitRange **antes** que la cuota: si una ResourceQuota limita `requests.cpu` y no hay defaults, los pods sin `requests` son **rechazados** ("must specify requests.cpu").

---

## Reto 10 — HPA imperativo (3 min)

> En `cka2`, crea el deployment `hpa-web` (`nginx:alpine`, request de CPU `50m`), expónlo como
> Service `hpa-web` en el puerto 80 y crea un HPA que mantenga la CPU al **50%** con entre **2 y 6** réplicas.
> Genera carga y observa cómo escala.

```bash
# Solución
kubectl create deployment hpa-web --image=nginx:alpine -n cka2
kubectl set resources deployment hpa-web -n cka2 --requests=cpu=50m
kubectl expose deployment hpa-web --port=80 -n cka2

kubectl autoscale deployment hpa-web -n cka2 --cpu-percent=50 --min=2 --max=6
# En kubectl recientes --cpu-percent está deprecado en favor de --cpu=50%
# (comprueba con: kubectl autoscale --help)

# Generar carga
kubectl run carga --image=busybox:1.36 -n cka2 -- \
  sh -c "while true; do wget -qO- http://hpa-web > /dev/null; done"
```

**Verificación:**
```bash
kubectl get hpa hpa-web -n cka2 -w
# TARGETS pasa de cpu: 0%/50% a >50% y REPLICAS sube hacia 6 (1-2 min)
kubectl top pods -n cka2 -l app=hpa-web

kubectl delete pod carga -n cka2
# El scale-down tarda ~5 min (stabilizationWindowSeconds por defecto)
```

> k3s trae **metrics-server** instalado; sin él, el HPA mostraría `<unknown>/50%`.

---

## Limpieza final

```bash
kubectl delete namespace cka2 cka2-quota
# Por si el Reto 6 quedó a medias:
kubectl taint node k3s-worker2 dedicado=bd:NoSchedule- 2>/dev/null
kubectl label node k3s-worker2 disco- 2>/dev/null
multipass exec k3s-worker2 -- sudo rm -f /var/lib/rancher/k3s/agent/pod-manifests/static-cache.yaml
```

---

## Preguntas de reflexión para el instructor

1. ¿Cuándo usarías `subPath` y cuándo montar el ConfigMap entero en un directorio?
2. ¿Qué diferencia hay entre `kubectl rollout undo` y `kubectl rollout undo --to-revision=N`?
3. ¿Por qué un fallo de readiness no reinicia el contenedor y uno de liveness sí?
4. ¿Qué pasaría con un deployment si creas una ResourceQuota de CPU sin LimitRange en el namespace?
