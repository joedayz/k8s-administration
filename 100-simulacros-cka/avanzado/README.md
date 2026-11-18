# Lab 100 — Avanzado: Retos Completos estilo Examen CKA (Troubleshooting y Cluster Ops)

## Objetivo
Resolver escenarios de ~15 minutos que replican las preguntas de más peso del examen: troubleshooting de aplicaciones, DNS, nodos y control plane, mantenimiento con PDB, usuarios con certificados, backup/restore de etcd y tráfico de Services. Ninguno repite los retos del módulo 99 (allí ya se hicieron el troubleshooting de 4 problemas, el backup de SQLite, el drain sin PDB y el despliegue integral seguro).

## Duración estimada
150 minutos (10 retos × 15 min) — o dos sesiones de 5 retos

> **Reglas del simulacro**
> - Los archivos `escenario-*.yaml` y `romper-*.sh` **contienen las averías**: aplícalos/ejecútalos sin leerlos.
> - Usa solo `kubectl`, `ssh`/`multipass exec`, la documentación oficial y lo que haya en el nodo.
> - Los retos 6 y 7 rompen un nodo/el control plane: **no los hagas mientras otra persona usa el cluster**.

```bash
cd 100-simulacros-cka/avanzado
```

---

## Reto 1 — Troubleshooting de aplicaciones: 5 problemas en un namespace (15 min)

> Se ha desplegado una tienda en el namespace `cka2-trouble`. **Ningún Deployment está sano o accesible.**
> Deja los 5 Deployments con todos sus pods `Running`/`Ready` y los Services `catalogo-svc` y
> `pagos-svc` respondiendo `200`. Reglas: no cambies imágenes ni comandos, y los datos de
> `inventario` deben vivir en un PVC.

```bash
kubectl apply -f escenario-trouble.yaml
```

```bash
# Solución — diagnóstico de arriba abajo
kubectl get deploy,pods,svc,pvc -n cka2-trouble
kubectl get events -n cka2-trouble --field-selector type=Warning --sort-by=.lastTimestamp
```

**Problema A — `catalogo-svc` no responde aunque los pods están `Running`:**
```bash
kubectl get endpointslices -n cka2-trouble -l kubernetes.io/service-name=catalogo-svc
# ENDPOINTS 10.42.x.x... PORTS 8080   ← hay endpoints, pero al puerto equivocado
kubectl get pod -n cka2-trouble -l app=catalogo -o jsonpath='{.items[0].spec.containers[0].ports}{"\n"}'
# containerPort 80
kubectl patch svc catalogo-svc -n cka2-trouble -p '{"spec":{"ports":[{"port":80,"targetPort":80}]}}'
```

**Problema B — `pagos` está `Running` pero `0/1` y su Service no tiene endpoints:**
```bash
kubectl describe pod -n cka2-trouble -l app=pagos | grep -A3 Readiness
kubectl events -n cka2-trouble --for deployment/pagos 2>/dev/null; \
kubectl get events -n cka2-trouble --field-selector reason=Unhealthy | tail -2
# Readiness probe failed: HTTP probe failed with statuscode: 404   (/healthz no existe en nginx)
kubectl patch deploy pagos -n cka2-trouble --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/"}]'
```

**Problema C — `reportes` en `Pending`:**
```bash
kubectl describe pod -n cka2-trouble -l app=reportes | grep -A2 Events -m1; \
kubectl get events -n cka2-trouble --field-selector reason=FailedScheduling | grep reportes | tail -1
# 3 node(s) didn't match Pod's node affinity/selector
kubectl get deploy reportes -n cka2-trouble -o jsonpath='{.spec.template.spec.nodeSelector}{"\n"}'
# {"disktype":"nvme"}
kubectl get nodes -L disktype
# Opción 1 (cambiar la infraestructura): etiquetar el nodo que tiene el disco
kubectl label node k3s-worker2 disktype=nvme
# Opción 2 (cambiar la app): quitar el nodeSelector
# kubectl patch deploy reportes -n cka2-trouble --type=json -p '[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]'
```

**Problema D — `inventario` en `Pending` y el PVC también:**
```bash
kubectl describe pvc datos-inventario -n cka2-trouble | tail -3
# storageclass.storage.k8s.io "rapido" not found
kubectl get sc
# storageClassName es INMUTABLE en un PVC: hay que recrearlo
kubectl delete pvc datos-inventario -n cka2-trouble
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: datos-inventario
  namespace: cka2-trouble
spec:
  storageClassName: local-path
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 64Mi
EOF
# El pod Pending se programa solo en cuanto el PVC existe (no hace falta reiniciarlo)
```

**Problema E — `notificador` en `CreateContainerConfigError`:**
```bash
kubectl describe pod -n cka2-trouble -l app=notificador | grep -E "Error|Warning" | tail -2
# Error: couldn't find key password in Secret cka2-trouble/smtp-cred
kubectl get secret smtp-cred -n cka2-trouble -o jsonpath='{.data}' ; echo
# {"pass":"...","usuario":"..."}   ← la clave se llama "pass"
kubectl patch deploy notificador -n cka2-trouble --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/env/1/valueFrom/secretKeyRef/key","value":"pass"}]'
```

**Verificación:**
```bash
kubectl get pods,pvc -n cka2-trouble
# 7 pods Running y 1/1; PVC Bound (local-path)
kubectl run t -n cka2-trouble --rm -i --restart=Never --image=curlimages/curl:8.11.1 -- \
  sh -c 'curl -s -o /dev/null -w "catalogo %{http_code}\n" http://catalogo-svc; curl -s -o /dev/null -w "pagos %{http_code}\n" http://pagos-svc'
# catalogo 200 / pagos 200
kubectl exec -n cka2-trouble deploy/notificador -- printenv SMTP_PASSWORD
```

> **Método:** `Pending` → scheduling (eventos `FailedScheduling`, PVC, recursos); `CreateContainerConfigError` → ConfigMap/Secret;
> `Running 0/1` → readiness; `Running 1/1` pero sin respuesta → Service (selector/targetPort, mira las EndpointSlices).

---

## Reto 2 — DNS roto en tres capas (15 min)

> Las aplicaciones del cluster han dejado de resolver nombres. El Deployment `cliente` del
> namespace `cka2-dns` debe llegar a `http://backend` (sus logs deben mostrar `200`).
> Arregla **todo** lo necesario, también lo que esté roto en `kube-system`.

```bash
# Preparación: averiar CoreDNS (ejecútalo sin leerlo; guarda un respaldo por si acaso)
kubectl get cm coredns -n kube-system -o yaml > /tmp/coredns-respaldo.yaml
kubectl -n kube-system patch svc kube-dns -p '{"spec":{"selector":{"k8s-app":"kube-dns-v2"}}}'
kubectl -n kube-system get cm coredns -o yaml \
  | sed 's/kubernetes cluster.local/kubernetes cluster.lan/' | kubectl replace -f -
kubectl apply -f escenario-dns.yaml
```

```bash
# Solución — capa 1: el propio pod
kubectl logs -n cka2-dns deploy/cliente --tail=3                     # FALLO / 000
kubectl exec -n cka2-dns deploy/cliente -- cat /etc/resolv.conf
# nameserver = el DNS del NODO, sin "search cka2-dns.svc.cluster.local"
kubectl get deploy cliente -n cka2-dns -o jsonpath='{.spec.template.spec.dnsPolicy}{"\n"}'
# Default  ← hereda el resolv.conf del nodo (no usa CoreDNS)
kubectl patch deploy cliente -n cka2-dns -p '{"spec":{"template":{"spec":{"dnsPolicy":"ClusterFirst"}}}}'

# Capa 2: ¿llega el pod a CoreDNS?
kubectl run dnstest -n cka2-dns --rm -i --restart=Never --image=busybox:1.36 -- nslookup -timeout=2 backend
# ;; connection timed out; no servers could be reached
kubectl get svc kube-dns -n kube-system -o wide                       # ClusterIP 10.43.0.10
kubectl get endpointslices -n kube-system -l kubernetes.io/service-name=kube-dns
# ENDPOINTS <unset>  ← el Service no selecciona ningún pod
kubectl get svc kube-dns -n kube-system -o jsonpath='{.spec.selector}{"\n"}'   # k8s-app=kube-dns-v2
kubectl get pods -n kube-system --show-labels | grep coredns                    # k8s-app=kube-dns
kubectl -n kube-system patch svc kube-dns -p '{"spec":{"selector":{"k8s-app":"kube-dns"}}}'

# Capa 3: CoreDNS responde, pero NXDOMAIN para todo lo del cluster
kubectl run dnstest -n cka2-dns --rm -i --restart=Never --image=busybox:1.36 -- \
  nslookup backend.cka2-dns.svc.cluster.local
# ** server can't find backend.cka2-dns.svc.cluster.local: NXDOMAIN
kubectl get cm coredns -n kube-system -o jsonpath='{.data.Corefile}' | grep kubernetes
# kubernetes cluster.lan in-addr.arpa ip6.arpa {   ← dominio equivocado
kubectl edit cm coredns -n kube-system                 # cluster.lan → cluster.local
# El plugin "reload" aplica el cambio en ~30-45 s (no hace falta reiniciar CoreDNS)
kubectl logs -n kube-system deploy/coredns --tail=3    # [INFO] Reloading complete
```

**Verificación:**
```bash
kubectl run dnstest -n cka2-dns --rm -i --restart=Never --image=busybox:1.36 -- nslookup backend
# Name: backend.cka2-dns.svc.cluster.local  Address: 10.43.x.x
kubectl logs -n cka2-dns deploy/cliente --tail=3
# 200 (si aún ves FALLO, espera: CoreDNS cachea las respuestas negativas 30 s)
```

> **En el examen (kubeadm):** mismas capas. Recuerda que en kubeadm el ConfigMap es `coredns` y en k3s
> lo gestiona el propio k3s (`# File managed by k3s`): para personalizaciones **persistentes** usa el
> ConfigMap `coredns-custom` (claves `*.override` / `*.server`), porque un reinicio de k3s reescribe `coredns`.

---

## Reto 3 — Mantenimiento de un nodo con un PDB que bloquea el drain (15 min)

> En `cka2-ops` corre `critico` (2 réplicas, una por worker) protegido por el PDB `critico-pdb`.
> Debes drenar `k3s-worker` para mantenimiento **sin borrar ni editar el PDB** y **sin que haya
> nunca menos de 2 pods `Ready`**. Al terminar, el nodo vuelve al servicio y `critico` queda repartido.

```bash
kubectl apply -f escenario-pdb.yaml
kubectl rollout status deploy/critico -n cka2-ops
```

```bash
# Solución
kubectl get pdb critico-pdb -n cka2-ops
# MIN AVAILABLE 2   ALLOWED DISRUPTIONS 0   ← con 2 réplicas, ninguna eviction es posible

kubectl drain k3s-worker --ignore-daemonsets --delete-emptydir-data --timeout=30s
# error when evicting ... Cannot evict pod as it would violate the pod's disruption budget.
# El drain falla pero deja el nodo CORDONED (SchedulingDisabled)

# Dar margen al PDB: una réplica más
kubectl scale deploy critico -n cka2-ops --replicas=3
kubectl rollout status deploy/critico -n cka2-ops
kubectl get pdb critico-pdb -n cka2-ops          # ALLOWED DISRUPTIONS 1

kubectl drain k3s-worker --ignore-daemonsets --delete-emptydir-data
# node/k3s-worker drained
kubectl get pods -n cka2-ops -o wide
# 2 Running en k3s-worker2 + 1 Pending
```

**Investigar el pod `Pending`:**
```bash
kubectl get events -n cka2-ops --field-selector reason=FailedScheduling | tail -1
# 1 node(s) didn't match Pod's node affinity/selector,      ← k3s-server excluido por la app
# 1 node(s) didn't match pod topology spread constraints,  ← k3s-worker2
# 1 node(s) were unschedulable                              ← k3s-worker (cordoned)
```

> `topologySpreadConstraints` con `nodeTaintsPolicy: Ignore` (por defecto) **sigue contando como dominio**
> al nodo cordoned (con 0 pods), así que meter un tercer pod en `k3s-worker2` daría skew 2 > 1.
> El PDB sigue satisfecho (2 disponibles), así que no es un problema durante la ventana; si quieres
> que el pod se reprograme, añade `nodeTaintsPolicy: Honor` a la restricción (los nodos con taints
> no tolerados dejan de contar como dominio).

```bash
# "Mantenimiento" terminado
kubectl uncordon k3s-worker
kubectl get pods -n cka2-ops -o wide            # el Pending se programa en k3s-worker
kubectl scale deploy critico -n cka2-ops --replicas=2
```

**Verificación:**
```bash
kubectl get nodes                                # k3s-worker Ready, sin SchedulingDisabled
kubectl get pods -n cka2-ops -o wide             # 1 pod por worker
kubectl get pdb critico-pdb -n cka2-ops -o jsonpath='{.spec.minAvailable}{"\n"}'   # 2 (intacto)
```

> **Alternativas válidas:** cambiar a `maxUnavailable: 1` (prohibido aquí: editar el PDB) o
> `kubectl drain --disable-eviction` (salta el PDB: **viola** el requisito). Nunca uses `--force`
> como atajo: solo sirve para pods sin controlador.

---

## Reto 4 — Usuario con CertificateSigningRequest, kubeconfig propio y RBAC por grupo (15 min)

> Da acceso al cluster a `ana`, del grupo `auditores`:
> 1. Genera su clave y CSR con `CN=ana` y `O=auditores`, apruébalo en Kubernetes (validez 24 h)
> 2. Crea `~/ana.kubeconfig` con contexto `ana@k3s`, namespace por defecto `cka2-sec` y **certificados embebidos**
> 3. El **grupo** `auditores` puede `get/list/watch` pods y sus logs en `cka2-sec`, nada más
> 4. Demuestra que funciona con `ana.kubeconfig` y con `--as`

```bash
# Solución
cd ~ && mkdir -p cka2-ana && cd cka2-ana
openssl genrsa -out ana.key 2048
openssl req -new -key ana.key -out ana.csr -subj "/CN=ana/O=auditores"

cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ana
spec:
  request: $(base64 < ana.csr | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages: ["client auth"]
EOF
kubectl get csr ana                              # Pending
kubectl certificate approve ana
kubectl get csr ana -o jsonpath='{.status.certificate}' | base64 -d > ana.crt
openssl x509 -in ana.crt -noout -subject -enddate
# subject=O=auditores, CN=ana   notAfter=<mañana>

# RBAC al GRUPO, no al usuario
kubectl create namespace cka2-sec
kubectl create role lector-pods -n cka2-sec --verb=get,list,watch --resource=pods,pods/log
kubectl create rolebinding auditores-lectura -n cka2-sec --role=lector-pods --group=auditores

# kubeconfig independiente
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
kubectl config view --raw --minify \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > ca.crt
K=~/ana.kubeconfig
kubectl config set-cluster k3s --server=$SERVER --certificate-authority=ca.crt --embed-certs --kubeconfig=$K
kubectl config set-credentials ana --client-certificate=ana.crt --client-key=ana.key --embed-certs --kubeconfig=$K
kubectl config set-context ana@k3s --cluster=k3s --user=ana --namespace=cka2-sec --kubeconfig=$K
kubectl config use-context ana@k3s --kubeconfig=$K
cd ~
```

**Verificación:**
```bash
kubectl --kubeconfig ~/ana.kubeconfig auth whoami
# Username ana   Groups [auditores system:authenticated]
kubectl --kubeconfig ~/ana.kubeconfig get pods                 # No resources found in cka2-sec namespace.
kubectl --kubeconfig ~/ana.kubeconfig get secrets              # Forbidden
kubectl --kubeconfig ~/ana.kubeconfig get pods -n default      # Forbidden

kubectl auth can-i list pods -n cka2-sec --as=ana --as-group=auditores   # yes
kubectl auth can-i list pods -n cka2-sec --as=ana                        # no ← el permiso viene del grupo
grep -c "certificate-data" ~/ana.kubeconfig                              # 2 (CA + cliente embebidos)
```

> Kubernetes **no tiene objetos User ni Group**: el usuario es el `CN` y los grupos son los `O` del
> certificado. Por eso un certificado emitido no se puede "revocar" con RBAC salvo quitando los bindings
> (o rotando la CA). Usa `expirationSeconds` cortos.

---

## Reto 5 — Backup y restore de etcd con `etcdctl`/`etcdutl` (15 min)

> En `k3s-worker2` hay un etcd "estilo kubeadm" como static pod (certificados en
> `/etc/kubernetes/pki/etcd/`, datos en `/var/lib/etcd`). Contiene las claves `/empresa/...`.
> 1. Guarda un snapshot en `/opt/cka2/etcd-snap.db` y muestra su estado en tabla
> 2. Simula el desastre (abajo)
> 3. Restaura el snapshot en `/var/lib/etcd-restaurado` y haz que el static pod lo use
> 4. Comprueba que vuelven las 4 claves originales y no está la del intruso

```bash
# Preparación (k3s usa SQLite: montamos un etcd con TLS para practicar)
multipass transfer preparar-etcd.sh k3s-worker2:/tmp/
multipass exec k3s-worker2 -- sudo bash /tmp/preparar-etcd.sh
kubectl get pod -n kube-system etcd-k3s-worker2      # mirror pod Running
multipass shell k3s-worker2                          # el resto del reto, DENTRO del nodo
sudo -i
```

```bash
# Solución (dentro del nodo, como root)
# Las rutas de los certificados salen del manifiesto del static pod
grep -E "cert-file|key-file|trusted-ca|listen-client" /var/lib/rancher/k3s/agent/pod-manifests/etcd.yaml
# kubeadm: /etc/kubernetes/manifests/etcd.yaml

export ETCDCTL_ENDPOINTS=https://127.0.0.1:2379
export ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt
export ETCDCTL_CERT=/etc/kubernetes/pki/etcd/server.crt
export ETCDCTL_KEY=/etc/kubernetes/pki/etcd/server.key
etcdctl endpoint health
etcdctl get /empresa --prefix --keys-only

# 1. Backup
etcdctl snapshot save /opt/cka2/etcd-snap.db
etcdutl snapshot status /opt/cka2/etcd-snap.db -w table
# | HASH | REVISION | TOTAL KEYS | TOTAL SIZE | VERSION |

# 2. Desastre
etcdctl del /empresa --prefix
etcdctl put /empresa/apps/malware "estado=intruso"

# 3. Restore a un data-dir NUEVO (nunca encima del que está en uso)
etcdutl snapshot restore /opt/cka2/etcd-snap.db --data-dir=/var/lib/etcd-restaurado

# Apuntar el static pod al nuevo directorio: basta con cambiar el hostPath del volumen
vi /var/lib/rancher/k3s/agent/pod-manifests/etcd.yaml
#   volumes:
#   - name: etcd-data
#     hostPath:
#       path: /var/lib/etcd-restaurado      ← antes /var/lib/etcd
# El kubelet detecta el cambio y recrea el pod (20-40 s)
watch -n2 'crictl ps --name etcd'                    # Ctrl+C cuando aparezca el contenedor nuevo
```

**Verificación:**
```bash
etcdctl endpoint health                              # is healthy
etcdctl get /empresa --prefix --keys-only
# /empresa/apps/catalogo  /empresa/apps/inventario  /empresa/apps/pagos  /empresa/config/version
# (sin /empresa/apps/malware)
exit; exit                                           # salir del nodo
```

> **etcd 3.6:** `etcdctl snapshot status/restore` **ya no existen**; se usa `etcdutl` (offline, sin certificados).
> `ETCDCTL_API=3` ya no hace falta (genera un warning). En clusters con etcd 3.5 aún verás ambos
> comandos con `etcdctl` y un aviso de deprecación.
>
> **En kubeadm:** como el cambio de hostPath recrea etcd **y** el kube-apiserver depende de él, espera
> a que `kubectl get pods -n kube-system` responda de nuevo (1-2 min). Si cambias `--data-dir` en vez del
> hostPath, cambia también el `mountPath` o el contenedor no verá los datos.

---

## Reto 6 — Worker `NotReady` (15 min)

> `k3s-worker` aparece `NotReady`. Devuélvelo a `Ready` de forma **persistente** (debe sobrevivir
> a un reinicio de la VM) **sin perder** los ajustes de tuning del kubelet que el equipo de
> operaciones dejó configurados.

```bash
# Preparación — NO lo hagas si alguien más usa el cluster
multipass transfer romper-nodo.sh k3s-worker:/tmp/
multipass exec k3s-worker -- sudo bash /tmp/romper-nodo.sh
# espera ~40 s
```

```bash
# Solución — desde kubectl
kubectl get nodes                                         # k3s-worker NotReady
kubectl describe node k3s-worker | grep -A6 Conditions
# Ready Unknown ... NodeStatusUnknown   Kubelet stopped posting node status.
kubectl describe node k3s-worker | grep -A1 Taints
# node.kubernetes.io/unreachable:NoExecute  ← en 5 min sus pods serán desalojados

# En el nodo
multipass shell k3s-worker              # examen: ssh k3s-worker
sudo -i
systemctl status k3s-agent              # kubeadm: systemctl status kubelet
# Active: inactive (dead)   ...; disabled;   ← parado Y deshabilitado
systemctl start k3s-agent
systemctl status k3s-agent              # activating (auto-restart) → sigue fallando
journalctl -u k3s-agent --no-pager -n 50 | grep -iE "error|fatal"
# Error: failed to parse kubelet flag: unknown flag: --node-status-update-frequncy

# ¿De dónde sale ese flag?
grep -rn "frequncy" /etc/rancher/k3s/ /etc/systemd/system/k3s-agent.service*
# /etc/rancher/k3s/config.yaml.d/50-tuning.yaml: - "node-status-update-frequncy=10s"
sed -i 's/frequncy/frequency/' /etc/rancher/k3s/config.yaml.d/50-tuning.yaml   # corregir, no borrar

systemctl enable --now k3s-agent        # enable = persistente tras reinicio
systemctl is-active k3s-agent; systemctl is-enabled k3s-agent
exit; exit
```

**Verificación:**
```bash
kubectl get nodes                                          # k3s-worker Ready
kubectl describe node k3s-worker | grep Taints             # <none>
kubectl get node k3s-worker -o jsonpath='{.status.allocatable.pods}{"\n"}'   # 110 (el tuning sigue)
```

> **En el examen (kubeadm)** los equivalentes son `systemctl status kubelet`, `journalctl -u kubelet`,
> `/var/lib/kubelet/config.yaml`, `/etc/kubernetes/kubelet.conf` y el drop-in
> `/usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf`. Fallos típicos: ruta del binario,
> CA o `staticPodPath` incorrectos, swap activada, servicio deshabilitado.

---

## Reto 7 — "Los pods nuevos se quedan en Pending y no hay eventos" (15 min)

> Desde un cambio del equipo de plataforma, **ningún pod nuevo arranca**. Mientras investigas,
> pon en marcha **ya** el pod urgente `urgente` (`nginx:alpine`, namespace `cka2-sched`) en `k3s-worker2`.
> Después encuentra la causa y arréglala de forma persistente.

```bash
# Preparación — NO lo hagas si alguien más usa el cluster
multipass transfer romper-scheduler.sh k3s-server:/tmp/
multipass exec k3s-server -- sudo bash /tmp/romper-scheduler.sh
sleep 30
kubectl create namespace cka2-sched
kubectl create deployment web --image=nginx:alpine --replicas=2 -n cka2-sched
```

```bash
# Solución — síntomas
kubectl get pods -n cka2-sched -o wide
# Pending, NODE <none>
kubectl events -n cka2-sched
# Solo SuccessfulCreate/ScalingReplicaSet: NO hay "FailedScheduling" ni "Scheduled"
# → no es que el scheduler no encuentre nodo: es que nadie está programando
kubectl get pod -n cka2-sched -l app=web -o jsonpath='{.items[0].spec.schedulerName}{"\n"}'
# default-scheduler (no es un schedulerName inexistente)

# Workaround inmediato: nodeName salta el scheduler (el kubelet acepta el pod directamente)
kubectl run urgente -n cka2-sched --image=nginx:alpine \
  --overrides='{"spec":{"nodeName":"k3s-worker2"}}'
kubectl get pod urgente -n cka2-sched -o wide              # Running en k3s-worker2

# Causa
kubectl get node k3s-server -o jsonpath='{.metadata.annotations.k3s\.io/node-args}{"\n"}'
# [..., "--disable-scheduler", "true"]
multipass exec k3s-server -- sudo bash -c \
  'journalctl -u k3s -b --no-pager | grep -c "Running kube-scheduler"; grep -rn scheduler /etc/rancher/k3s/'
# /etc/rancher/k3s/config.yaml.d/60-ha-externo.yaml:2:disable-scheduler: true
multipass exec k3s-server -- sudo bash -c \
  'rm /etc/rancher/k3s/config.yaml.d/60-ha-externo.yaml && systemctl restart k3s'
sleep 30
```

**Verificación:**
```bash
kubectl get pods -n cka2-sched -o wide                     # web-* Running con NODE asignado
kubectl events -n cka2-sched | grep Scheduled              # Successfully assigned ...
multipass exec k3s-server -- sudo bash -c \
  'journalctl -u k3s --since "-5min" --no-pager | grep -o "Running kube-scheduler" | head -1'
```

> **En el examen (kubeadm):** el scheduler es el static pod `kube-scheduler-<nodo>` en `kube-system`.
> Si está en `CrashLoopBackOff`/no existe, revisa `/etc/kubernetes/manifests/kube-scheduler.yaml`
> (comando, flags, ruta del kubeconfig) y `crictl ps -a | grep scheduler` + `crictl logs <id>`
> si la API no sirve sus logs. Mismo método para `kube-controller-manager` (síntoma: Deployments sin ReplicaSets).

---

## Reto 8 — Tres pods que se reinician por tres motivos distintos (15 min)

> En `cka2-crash` hay tres Deployments que no paran de reiniciarse.
> 1. Guarda en `/tmp/cka2-reinicios.txt` los pods ordenados por número de reinicios con
>    columnas `POD`, `REINICIOS`, `RAZON` y `EXIT`
> 2. Encuentra la causa de cada uno y arréglalo **sin cambiar imagen ni comando**

```bash
kubectl apply -f escenario-crash.yaml
sleep 60
```

```bash
# Solución — 1. vista general
kubectl get pods -n cka2-crash \
  -o custom-columns='POD:.metadata.name,REINICIOS:.status.containerStatuses[0].restartCount,RAZON:.status.containerStatuses[0].lastState.terminated.reason,EXIT:.status.containerStatuses[0].lastState.terminated.exitCode' \
  --sort-by='.status.containerStatuses[0].restartCount' | tee /tmp/cka2-reinicios.txt
# cache-...       OOMKilled  137
# facturador-...  Error      3
# indexador-...   Error      137   ← 137 = SIGKILL (128+9): lo mató el kubelet o el kernel
```

**`cache` — OOMKilled:**
```bash
kubectl describe pod -n cka2-crash -l app=cache | grep -A4 "Last State"
# Reason: OOMKilled   Exit Code: 137
kubectl get deploy cache -n cka2-crash -o jsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'
# limits.memory 32Mi, pero el proceso necesita ~60M (args: --vm-bytes 60M)
kubectl set resources deploy cache -n cka2-crash --requests=memory=96Mi --limits=memory=128Mi
```

**`indexador` — exit 137 sin OOM: lo mata la liveness:**
```bash
kubectl get events -n cka2-crash --field-selector reason=Unhealthy | grep indexador | tail -2
# Liveness probe failed: cat: can't open '/tmp/listo'
# ... Container app failed liveness probe, will be restarted
kubectl logs -n cka2-crash deploy/indexador
# "cargando índice..." → tarda 25 s en crear /tmp/listo; la liveness lo mata a los ~10 s
# Arreglo correcto: una startupProbe (la liveness no actúa hasta que la startup tenga éxito)
kubectl patch deploy indexador -n cka2-crash --type=json -p '[{"op":"add",
  "path":"/spec/template/spec/containers/0/startupProbe",
  "value":{"exec":{"command":["cat","/tmp/listo"]},"periodSeconds":5,"failureThreshold":12}}]'
```

**`facturador` — exit 3 (error de la aplicación):**
```bash
kubectl logs -n cka2-crash deploy/facturador
# facturador v2 arrancando
# ERROR: falta la variable MODO
kubectl get cm -n cka2-crash                     # facturador-config tiene MODO=produccion
kubectl set env deploy/facturador -n cka2-crash --from=configmap/facturador-config
```

> **`kubectl logs` vs `--previous`:** si el pod está en `CrashLoopBackOff`/`Error`, el contenedor
> "actual" **es** el que falló: usa `kubectl logs` sin más (el kubelet solo conserva un contenedor
> muerto, así que `--previous` puede responder `unable to retrieve container logs`). Usa `--previous`
> cuando el contenedor reiniciado ya está `Running` y quieres ver por qué murió el anterior.

**Verificación:**
```bash
sleep 45
kubectl get pods -n cka2-crash                   # 3 pods Running 1/1, RESTARTS 0
kubectl logs -n cka2-crash deploy/facturador     # modo=produccion
cat /tmp/cka2-reinicios.txt
```

---

## Reto 9 — NodePort que solo responde en algunos nodos (15 min)

> Crea en `cka2-net` el Deployment `eco` (`nginx:alpine`) expuesto como NodePort `30180`.
> Requisitos del equipo de seguridad:
> - la aplicación debe registrar la **IP real del cliente** (no la de un nodo)
> - el NodePort debe responder `200` **en los 3 nodos**, también durante un rollout
>
> Explica por qué la primera aproximación (1 réplica) no cumple ambos requisitos.

```bash
# Solución — primera aproximación
kubectl create namespace cka2-net
kubectl create deployment eco --image=nginx:alpine -n cka2-net
kubectl expose deployment eco -n cka2-net --type=NodePort --port=80
kubectl patch svc eco -n cka2-net -p '{"spec":{"externalTrafficPolicy":"Local","ports":[{"port":80,"nodePort":30180}]}}'
kubectl rollout status deploy/eco -n cka2-net

for ip in $(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'); do
  printf "%s -> " $ip; curl -s -m 3 -o /dev/null -w "%{http_code}\n" http://$ip:30180 || echo TIMEOUT
done
# Solo responde (200) el nodo que tiene el pod; los demás → TIMEOUT
kubectl logs -n cka2-net deploy/eco --tail=1
# 192.168.252.1 - - "GET / ..."   ← IP real del host (en macOS, el bridge de multipass)
```

> `externalTrafficPolicy: Local` → kube-proxy **solo** envía a pods del **mismo** nodo y no hace SNAT
> (se conserva la IP de origen). Si el nodo no tiene pods, descarta el tráfico.
> Con `Cluster` (por defecto) cualquier nodo reenvía a cualquier pod, pero hace SNAT y la app ve la IP de un nodo/del CNI.

```bash
# Solución — un pod por nodo, también durante los rollouts
kubectl scale deploy eco -n cka2-net --replicas=3
kubectl patch deploy eco -n cka2-net --type=json -p '[{"op":"add",
  "path":"/spec/template/spec/topologySpreadConstraints",
  "value":[{"maxSkew":1,"topologyKey":"kubernetes.io/hostname","whenUnsatisfiable":"DoNotSchedule",
            "labelSelector":{"matchLabels":{"app":"eco"}},
            "matchLabelKeys":["pod-template-hash"]}]}]'
kubectl rollout status deploy/eco -n cka2-net
kubectl get pods -n cka2-net -o wide             # uno en cada nodo
```

> **¿Por qué `matchLabelKeys: [pod-template-hash]`?** Sin él, durante el rollout los pods **viejos**
> también cuentan para el spread y el nuevo ReplicaSet puede quedar 2/1/0 cuando terminan.
> Con él, cada ReplicaSet se reparte por su cuenta. (Un DaemonSet también cumpliría el requisito.)

**Verificación:**
```bash
for ip in $(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'); do
  printf "%s -> " $ip; curl -s -m 3 -o /dev/null -w "%{http_code}\n" http://$ip:30180
done
# 200 en los tres
kubectl get svc eco -n cka2-net -o jsonpath='{.spec.externalTrafficPolicy}{"\n"}'     # Local
for p in $(kubectl get pods -n cka2-net -l app=eco -o name); do kubectl logs -n cka2-net $p --tail=1 | cut -d' ' -f1; done
# la IP de tu host, no 10.42.x.x
```

---

## Reto 10 — Mini examen integral: 6 tareas encadenadas (15 min)

> Todo en el namespace `cka2-final`:
> 1. ServiceAccount `api-sa` **sin** montaje automático del token, con permiso para leer ConfigMaps del namespace
> 2. Deployment `api` (2 réplicas, `nginxinc/nginx-unprivileged:alpine`, puerto `8080` con nombre `http`) que:
>    use `api-sa`, corra como **no root** (`runAsNonRoot`, UID `101`), sin escalada de privilegios,
>    con requests `50m`/`64Mi`, readinessProbe HTTP a `/` y un PVC `api-datos` de `100Mi` montado en `/datos`
> 3. Service ClusterIP `api` en el puerto `80` hacia el puerto **con nombre** `http`
> 4. Ingress `api` (clase `traefik`) para el host `api.cka2.local` → `api:80`
> 5. NetworkPolicy `api-ingress`: al puerto 8080 de `api` solo llegan pods con `rol=frontend` del
>    namespace **y** el Ingress Controller (namespace `kube-system`)
> 6. Escribe en `/tmp/cka2-final.txt` la imagen y el nodo de cada pod de `api`

```bash
# Solución
kubectl create namespace cka2-final
kubectl config set-context --current --namespace=cka2-final

# 1
kubectl create serviceaccount api-sa
kubectl patch serviceaccount api-sa -p '{"automountServiceAccountToken":false}'
kubectl create role leer-config --verb=get,list,watch --resource=configmaps
kubectl create rolebinding api-sa-leer-config --role=leer-config --serviceaccount=cka2-final:api-sa

# 2 y 3
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: api-datos
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 100Mi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      serviceAccountName: api-sa
      securityContext:
        runAsNonRoot: true
        runAsUser: 101
        fsGroup: 101
      containers:
      - name: api
        image: nginxinc/nginx-unprivileged:alpine
        ports:
        - name: http
          containerPort: 8080
        securityContext:
          allowPrivilegeEscalation: false
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
        readinessProbe:
          httpGet:
            path: /
            port: http
        volumeMounts:
        - name: datos
          mountPath: /datos
      volumes:
      - name: datos
        persistentVolumeClaim:
          claimName: api-datos
---
apiVersion: v1
kind: Service
metadata:
  name: api
spec:
  selector:
    app: api
  ports:
  - port: 80
    targetPort: http
EOF
# Nota: local-path es RWO y WaitForFirstConsumer: las 2 réplicas acaban en el MISMO nodo que el PV

# 4
kubectl create ingress api --class=traefik --rule="api.cka2.local/*=api:80"

# 5
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-ingress
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: ["Ingress"]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          rol: frontend
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - port: 8080
EOF

kubectl rollout status deploy/api

# 6
kubectl get pods -l app=api \
  -o custom-columns='POD:.metadata.name,IMAGEN:.spec.containers[0].image,NODO:.spec.nodeName' > /tmp/cka2-final.txt
cat /tmp/cka2-final.txt
```

**Verificación:**
```bash
kubectl get pods -l app=api                                         # 2/2 Ready
kubectl exec deploy/api -- id                                       # uid=101(nginx)
kubectl exec deploy/api -- ls /var/run/secrets/kubernetes.io 2>&1   # No such file (sin token)
kubectl auth can-i list configmaps --as=system:serviceaccount:cka2-final:api-sa   # yes
kubectl auth can-i list secrets    --as=system:serviceaccount:cka2-final:api-sa   # no
kubectl get endpointslices -l kubernetes.io/service-name=api        # 2 IPs, puerto 8080

# NetworkPolicy (el "sleep 5" da tiempo al controlador de políticas a registrar la IP del pod nuevo)
kubectl run front -l rol=frontend --rm -i --restart=Never --image=curlimages/curl:8.11.1 -- \
  sh -c 'sleep 5; curl -s -m 3 -o /dev/null -w "%{http_code}\n" http://api'   # 200
kubectl run otro --rm -i --restart=Never --image=curlimages/curl:8.11.1 -- \
  sh -c 'sleep 5; curl -s -m 3 -o /dev/null -w "%{http_code}\n" http://api'   # 000 (timeout)

# Ingress a través de Traefik (kube-system)
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: api.cka2.local" http://$NODE_IP   # 200

kubectl config set-context --current --namespace=default
```

---

## Limpieza final

```bash
kubectl config set-context --current --namespace=default
kubectl delete namespace cka2-trouble cka2-dns cka2-ops cka2-sec cka2-sched cka2-crash cka2-net cka2-final --ignore-not-found
kubectl delete csr ana --ignore-not-found
rm -rf ~/cka2-ana ~/ana.kubeconfig /tmp/cka2-reinicios.txt /tmp/cka2-final.txt

# Reto 1
kubectl label node k3s-worker2 disktype- 2>/dev/null

# Reto 2 — si algo de CoreDNS quedó a medias, reinicia k3s en el server: reescribe sus addons
kubectl -n kube-system patch svc kube-dns -p '{"spec":{"selector":{"k8s-app":"kube-dns"}}}'
kubectl get cm coredns -n kube-system -o jsonpath='{.data.Corefile}' | grep -q "cluster.local in-addr" \
  || kubectl replace -f /tmp/coredns-respaldo.yaml
rm -f /tmp/coredns-respaldo.yaml

# Reto 3
kubectl uncordon k3s-worker

# Reto 5 — etcd de práctica
multipass exec k3s-worker2 -- sudo bash -c 'rm -f /var/lib/rancher/k3s/agent/pod-manifests/etcd.yaml; \
  rm -rf /var/lib/etcd /var/lib/etcd-restaurado /opt/cka2 /etc/kubernetes /usr/local/bin/etcdctl /usr/local/bin/etcdutl'

# Reto 6 — el drop-in de tuning es parte del escenario: retíralo
multipass exec k3s-worker -- sudo bash -c 'rm -f /etc/rancher/k3s/config.yaml.d/50-tuning.yaml; \
  systemctl enable k3s-agent; systemctl restart k3s-agent'

# Reto 7
multipass exec k3s-server -- sudo bash -c '[ -f /etc/rancher/k3s/config.yaml.d/60-ha-externo.yaml ] && \
  rm /etc/rancher/k3s/config.yaml.d/60-ha-externo.yaml && systemctl restart k3s || true'

kubectl get nodes          # 3 nodos Ready
```

---

## Preguntas de reflexión para el instructor

1. Ante un pod que no funciona, ¿qué te dice cada estado (`Pending`, `CreateContainerConfigError`, `CrashLoopBackOff`, `Running 0/1`) sobre dónde mirar primero?
2. ¿Por qué `dnsPolicy: Default` no significa "el DNS por defecto de Kubernetes"?
3. ¿Qué diferencia hay entre un drain bloqueado por un PDB y uno que termina pero deja pods `Pending`? ¿Cuál es más peligroso?
4. Si `ana` deja la empresa, ¿cómo le quitas el acceso si su certificado aún no ha caducado?
5. ¿Por qué se restaura etcd en un `data-dir` nuevo y no encima del actual?
6. ¿Por qué un pod con `nodeName` arranca aunque el scheduler esté caído? ¿Qué validaciones se salta?
7. Un contenedor termina con `exit 137` sin `OOMKilled`: ¿qué otras causas hay?
8. ¿Cuándo preferirías `externalTrafficPolicy: Local` aunque obligue a repartir pods por todos los nodos?
