# Lab 05 — Intermedio: Backup con Velero y GitOps con Argo CD

## Objetivo
Implementar backup y restauración del cluster con Velero, y configurar un flujo GitOps básico con Argo CD para despliegues automatizados.

## Duración estimada
90 minutos

---

## Parte A — Backup con Velero

### Paso 1 — Instalar Velero CLI

```bash
# macOS
brew install velero

# Ubuntu/Linux
VELERO_VERSION=v1.13.0
curl -L https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-linux-amd64.tar.gz | tar xz
sudo mv velero-${VELERO_VERSION}-linux-amd64/velero /usr/local/bin/
velero version --client-only
```

### Paso 2 — Instalar Velero en el cluster (con MinIO como storage local)

Para el lab usamos MinIO como backend de almacenamiento S3-compatible.

```bash
# Instalar MinIO como storage backend
kubectl apply -f minio.yaml

# Esperar a que MinIO esté listo
kubectl rollout status deployment/minio -n velero

# Esperar a que el Job cree el bucket "velero-backups"
kubectl wait --for=condition=complete job/minio-setup -n velero --timeout=2m

# Instalar Velero apuntando a MinIO
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.9.0 \
  --bucket velero-backups \
  --secret-file ./velero-credentials \
  --use-volume-snapshots=false \
  --backup-location-config region=minio,s3ForcePathStyle=true,s3Url=http://minio.velero.svc.cluster.local:9000

kubectl get pods -n velero
```

### Paso 2.1 — Exponer MinIO para el cliente de Velero

`s3Url` (arriba) solo es resoluble **dentro del cluster** (lo usa el servidor de Velero). Comandos ejecutados desde tu Mac, como `velero backup describe` y `velero backup logs`, generan una URL firmada y la resuelven con el DNS de tu máquina — por eso fallan con `dial tcp: lookup minio.velero.svc.cluster.local: no such host`.

La solución de Velero es exponer MinIO con `port-forward` y configurar un `publicUrl` adicional, solo para el cliente:

```bash
# Dejar corriendo en una terminal aparte (o en background)
kubectl port-forward -n velero svc/minio 9000:9000

# En otra terminal: indicarle al CLI cómo llegar a MinIO desde fuera del cluster
kubectl patch backupstoragelocation default -n velero \
  --type merge \
  -p '{"spec":{"config":{"publicUrl":"http://localhost:9000"}}}'
```

Con el `port-forward` activo, `velero backup describe`/`logs` ya pueden descargar los objetos.

### Paso 3 — Crear un backup

```bash
# Backup de un namespace completo
velero backup create backup-produccion \
  --include-namespaces produccion \
  --wait

# Ver el estado del backup
velero backup get
velero backup describe backup-produccion
velero backup logs backup-produccion
```

### Paso 4 — Simular pérdida de datos y restaurar

```bash
# Simular desastre: eliminar el namespace
kubectl delete namespace produccion

# Verificar que se fue
kubectl get namespace produccion   # debe dar error

# Restaurar desde el backup
velero restore create restauracion-produccion \
  --from-backup backup-produccion \
  --wait

# Verificar la restauración
kubectl get all -n produccion
velero restore describe restauracion-produccion
```

### Paso 5 — Backup programado

```bash
# Backup diario a las 3:00 AM con retención de 7 días
velero schedule create backup-diario \
  --schedule="0 3 * * *" \
  --include-namespaces produccion,staging \
  --ttl 168h

velero schedule get
```

---

## Parte B — GitOps con Argo CD

### Paso 6 — Instalar Argo CD

```bash
kubectl create namespace argocd

# --server-side: el manifiesto de Argo CD es muy grande y con un apply
# normal (client-side) puede fallar porque el annotation
# "kubectl.kubernetes.io/last-applied-configuration" supera el límite de
# tamaño de metadata. El modo server-side delega el merge al API server
# y evita ese error.
kubectl apply --server-side -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Esperar a que todos los pods estén listos
kubectl rollout status deployment/argocd-server -n argocd --timeout=3m

kubectl get pods -n argocd
```

### Paso 7 — Acceder a la UI de Argo CD

```bash
# Obtener contraseña inicial
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d
echo

# Port-forward
kubectl port-forward svc/argocd-server 8080:443 -n argocd
```

Abre: https://localhost:8080 (acepta el certificado autofirmado)
- Usuario: `admin`
- Contraseña: la del comando anterior

### Paso 8 — Crear una aplicación en Argo CD

Desde la UI o con la CLI:

```bash
# Instalar Argo CD CLI
brew install argocd  # macOS

# Login
argocd login localhost:8080 --username admin --insecure

# Crear aplicación apuntando a tu repositorio Git
argocd app create app-produccion \
  --repo https://github.com/<tu-usuario>/k8SAdms.git \
  --path 02-despliegue-avanzado/basico \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace desarrollo \
  --sync-policy automated \
  --auto-prune \
  --self-heal

# Ver el estado
argocd app get app-produccion
argocd app list
```

### Paso 9 — Ver el flujo GitOps en acción

```bash
# Hacer un cambio en el repositorio (por ejemplo, cambiar réplicas)
# git commit && git push

# Argo CD detecta el cambio y sincroniza automáticamente
argocd app sync app-produccion

# Ver el historial de sincronizaciones
argocd app history app-produccion
```

---

## Verificación

```bash
velero backup get
velero schedule get
argocd app list
```

---

## Limpieza

Estos recursos son exclusivos de este lab: ningún otro módulo reutiliza `velero`, `minio` o `argocd`.

```bash
# Si dejaste corriendo el port-forward del Paso 2.1, detenlo con Ctrl+C

# Velero (borra CRDs, ClusterRoleBinding, el Deployment y el namespace "velero")
velero uninstall --force

# MinIO queda en el mismo namespace "velero", así que ya se borró con lo anterior;
# si lo instalaste por separado o quedó algo suelto, confírmalo con:
kubectl delete namespace velero --ignore-not-found

# Argo CD
kubectl delete --server-side -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --ignore-not-found
kubectl delete namespace argocd --ignore-not-found

# Si la Application "app-produccion" no tenía auto-prune efectivo, revisa
# que no haya quedado nada desplegado por GitOps en "desarrollo"
kubectl get all -n desarrollo
```

---

## Preguntas de reflexión para el instructor

1. ¿Qué pasa si el backup incluye Secrets? ¿Están seguros en MinIO?
2. ¿Cuál es la diferencia entre GitOps y CI/CD tradicional?
3. ¿Cómo manejarías un conflicto entre lo que hay en Git y lo que hay en el cluster?
4. ¿Cada cuánto deberías hacer backups en producción?
