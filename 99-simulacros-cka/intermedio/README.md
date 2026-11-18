# Lab 10 — Intermedio: Retos de Networking, Storage y RBAC

## Objetivo
Resolver ejercicios de dificultad media que combinan varios conceptos. Cada reto dura ~10 minutos.

## Duración estimada
60 minutos (5 retos × 10 min + revisión)

---

## Reto 1 — ServiceAccount + Role + RoleBinding (10 min)

> En el namespace `cka-net`:
> 1. Crea un ServiceAccount llamado `monitor-sa`
> 2. Crea un Role llamado `monitor-role` que permita `get, list, watch` sobre `pods, services, endpoints`
> 3. Crea un RoleBinding llamado `monitor-binding` que asigne el Role al ServiceAccount
> 4. Verifica con `auth can-i` que el SA puede listar pods pero NO eliminarlos

```bash
kubectl create namespace cka-net

# ServiceAccount
kubectl create serviceaccount monitor-sa -n cka-net

# Role
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: monitor-role
  namespace: cka-net
rules:
- apiGroups: [""]
  resources: ["pods", "services", "endpoints"]
  verbs: ["get", "list", "watch"]
EOF

# RoleBinding
kubectl create rolebinding monitor-binding \
  --role=monitor-role \
  --serviceaccount=cka-net:monitor-sa \
  -n cka-net

# Verificación
kubectl auth can-i list pods \
  --as=system:serviceaccount:cka-net:monitor-sa \
  -n cka-net      # → yes

kubectl auth can-i delete pods \
  --as=system:serviceaccount:cka-net:monitor-sa \
  -n cka-net      # → no
```

---

## Reto 2 — Ingress con TLS (10 min)

> En el namespace `cka-net`:
> 1. Crea un deployment `api` con 2 réplicas de `nginx:alpine`
> 2. Crea un Service ClusterIP `api-svc` en el puerto 80
> 3. Crea un Ingress `api-ingress` que enrute `api.cka.local` → `api-svc:80`
> 4. Crea un Secret TLS con un certificado self-signed
> 5. Configura el Ingress para usar TLS

```bash
# Deployment y Service
kubectl create deployment api --image=nginx:alpine --replicas=2 -n cka-net
kubectl expose deployment api --name=api-svc --port=80 -n cka-net

# Generar certificado self-signed
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout tls.key -out tls.crt \
  -days 365 -subj "/CN=api.cka.local" 2>/dev/null

# Crear Secret TLS
kubectl create secret tls api-tls \
  --cert=tls.crt --key=tls.key \
  -n cka-net

# Ingress
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress
  namespace: cka-net
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
spec:
  tls:
  - hosts:
    - api.cka.local
    secretName: api-tls
  rules:
  - host: api.cka.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-svc
            port:
              number: 80
EOF

# Limpiar certificados temporales
rm tls.key tls.crt
```

**Verificación:**
```bash
kubectl get ingress -n cka-net
kubectl describe ingress api-ingress -n cka-net
```

---

## Reto 3 — PVC + Pod con almacenamiento persistente (10 min)

> En el namespace `cka-net`:
> 1. Crea un PersistentVolumeClaim de 500Mi con storageClass `local-path`
> 2. Crea un pod `data-pod` con imagen `alpine:3.19` que monte el PVC en `/data`
> 3. Escribe un archivo en `/data/test.txt`
> 4. Elimina el pod y crea uno nuevo con el mismo PVC
> 5. Verifica que el archivo sigue ahí

```bash
# PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-pvc
  namespace: cka-net
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 500Mi
  storageClassName: local-path
EOF

# Pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: data-pod
  namespace: cka-net
spec:
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: data-pvc
  containers:
  - name: alpine
    image: alpine:3.19
    command: ["sleep", "3600"]
    volumeMounts:
    - name: data
      mountPath: /data
EOF

sleep 10

# Escribir archivo
kubectl exec data-pod -n cka-net -- sh -c 'echo "datos persistentes" > /data/test.txt'
kubectl exec data-pod -n cka-net -- cat /data/test.txt

# Eliminar el pod
kubectl delete pod data-pod -n cka-net

# Crear uno nuevo con el mismo PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: data-pod-2
  namespace: cka-net
spec:
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: data-pvc
  containers:
  - name: alpine
    image: alpine:3.19
    command: ["sleep", "3600"]
    volumeMounts:
    - name: data
      mountPath: /data
EOF

sleep 10

# Verificar que los datos persisten
kubectl exec data-pod-2 -n cka-net -- cat /data/test.txt
# Debe mostrar: datos persistentes
```

---

## Reto 4 — NetworkPolicy que bloquea todo excepto DNS (10 min)

> En el namespace `cka-net`:
> 1. Crea una NetworkPolicy que bloquee TODO el tráfico entrante y saliente
> 2. Permite salidad DNS hacia kube-system (puerto 53 TCP y UDP)
> 3. Permite tráfico entrante desde el mismo namespace
> 4. Verifica con un pod de debug

```bash
# Primero crear un pod de prueba
kubectl run web-cka --image=nginx:alpine -n cka-net
sleep 5

# NetworkPolicy
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: restrict-net
  namespace: cka-net
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: cka-net
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: cka-net
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
EOF

# Verificar que DNS sigue funcionando
kubectl run dns-cka --image=busybox:1.36 --rm -it -n cka-net \
  -- nslookup kubernetes.default

# Verificar que el tráfico a otros namespaces está bloqueado
kubectl run test-cka --image=busybox:1.36 --rm -it -n cka-net \
  -- sh -c "wget -qO- http://kubernetes.default --timeout=3 || echo 'BLOQUEADO'"
```

---

## Reto 5 — ClusterRole para ver nodos (10 min)

> Crea un ClusterRole y ClusterRoleBinding que permita a un ServiceAccount
> del namespace `cka-net` listar y describir nodos del cluster (pero no modificarlos).

```bash
# ServiceAccount
kubectl create serviceaccount node-viewer -n cka-net

# ClusterRole
kubectl create clusterrole node-reader \
  --verb=get,list,watch \
  --resource=nodes

# ClusterRoleBinding
kubectl create clusterrolebinding node-reader-binding \
  --clusterrole=node-reader \
  --serviceaccount=cka-net:node-viewer

# Verificación
kubectl auth can-i list nodes \
  --as=system:serviceaccount:cka-net:node-viewer     # → yes
kubectl auth can-i delete nodes \
  --as=system:serviceaccount:cka-net:node-viewer     # → no
kubectl auth can-i patch nodes \
  --as=system:serviceaccount:cka-net:node-viewer     # → no
```

---

## Limpieza final

El ClusterRole y el ClusterRoleBinding del Reto 5 son recursos cluster-scoped — no se borran al eliminar el namespace.

```bash
kubectl delete namespace cka-net
kubectl delete clusterrolebinding node-reader-binding
kubectl delete clusterrole node-reader
```

---

## Preguntas de reflexión para el instructor

1. ¿Qué tipo de recursos requieren ClusterRole en lugar de Role?
2. ¿Cómo verificas que una NetworkPolicy está funcionando correctamente?
3. ¿Qué pasa con un PVC cuando eliminas el pod que lo usa?
4. ¿Cómo rotarías un certificado TLS de un Ingress sin downtime?
