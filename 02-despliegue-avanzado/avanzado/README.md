# Lab 02 — Avanzado: Helm y Kustomize para gestión multi-entorno

## Objetivo
Gestionar despliegues complejos usando Helm (instalación de software del cluster) y Kustomize (personalización por entorno), las herramientas que un admin usa en el día a día.

## Duración estimada
75 minutos

---

## Parte A — Helm

### Paso 1 — Instalar Helm

```bash
# En macOS
brew install helm

# En Ubuntu/Debian
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verificar
helm version
```

### Paso 2 — Explorar repositorios y charts

```bash
# Agregar repositorios populares
helm repo add stable https://charts.helm.sh/stable
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Buscar un chart
helm search repo nginx
helm search repo redis

# Ver información de un chart antes de instalarlo
helm show chart bitnami/nginx
helm show values bitnami/nginx   # todos los parámetros configurables
```

### Paso 3 — Instalar una aplicación con Helm

```bash
# Instalar nginx con valores personalizados
helm install mi-nginx bitnami/nginx \
  --namespace desarrollo \
  --set replicaCount=2 \
  --set service.type=ClusterIP

# Ver el estado del release
helm status mi-nginx -n desarrollo
helm list -n desarrollo

# Ver los recursos creados
kubectl get all -n desarrollo -l app.kubernetes.io/instance=mi-nginx
```

### Paso 4 — Actualizar y hacer rollback con Helm

```bash
# Actualizar configuración
helm upgrade mi-nginx bitnami/nginx \
  --namespace desarrollo \
  --set replicaCount=3

# Ver historial de versiones del release
helm history mi-nginx -n desarrollo

# Rollback a la revisión anterior
helm rollback mi-nginx 1 -n desarrollo

# Verificar
helm history mi-nginx -n desarrollo
```

### Paso 5 — Instalar con values file

```bash
# Instalar usando el archivo de valores personalizado
helm install redis-cache bitnami/redis \
  --namespace produccion \
  --values helm-redis-values.yaml

helm status redis-cache -n produccion
```

### Paso 6 — Desinstalar

```bash
helm uninstall mi-nginx -n desarrollo
helm uninstall redis-cache -n produccion
```

---

## Parte B — Kustomize

Kustomize está integrado en kubectl (no requiere instalación adicional).

### Paso 7 — Estructura de Kustomize

```bash
ls -la kustomize/
# base/          -> configuración común
# overlays/dev/  -> diferencias para desarrollo
# overlays/prod/ -> diferencias para producción
```

### Paso 8 — Ver qué va a desplegar sin aplicar (dry-run)

```bash
# Ver los manifiestos finales para dev
kubectl kustomize kustomize/overlays/dev

# Ver los manifiestos finales para prod
kubectl kustomize kustomize/overlays/prod
```

**Observa las diferencias:** réplicas, recursos, labels de entorno.

### Paso 9 — Desplegar por entorno

```bash
# Desplegar en desarrollo
kubectl apply -k kustomize/overlays/dev

# Verificar
kubectl get all -n desarrollo -l app=api-backend

# Desplegar en producción
kubectl apply -k kustomize/overlays/prod

# Verificar diferencias entre entornos
kubectl get deployment -n desarrollo api-backend -o jsonpath='{.spec.replicas}'
kubectl get deployment -n produccion api-backend -o jsonpath='{.spec.replicas}'
```

### Paso 10 — Limpiar

```bash
kubectl delete -k kustomize/overlays/dev
kubectl delete -k kustomize/overlays/prod
```

---

## Verificación

```bash
helm list -A   # no debe haber releases activos
kubectl get all -n desarrollo
kubectl get all -n produccion
```

---

## Preguntas de reflexión para el instructor

1. ¿Cuándo usarías Helm vs Kustomize? ¿Son excluyentes?
2. ¿Por qué es importante el `helm history` para un admin?
3. ¿Qué riesgo tiene usar `helm upgrade` sin revisar los cambios antes?
4. ¿Cómo gestionas secretos en Helm sin meterlos en el values.yaml?
