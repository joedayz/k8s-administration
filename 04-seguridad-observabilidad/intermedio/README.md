# Lab 04 — Intermedio: Secrets, ConfigMaps y seguridad de pods

## Objetivo
Gestionar configuración y credenciales de forma segura, y aplicar restricciones de seguridad a nivel de pod.

## Duración estimada
60 minutos

---

## Parte A — ConfigMaps y Secrets

### Paso 1 — Crear ConfigMaps

```bash
kubectl apply -f configmap-app.yaml

# Verificar el contenido
kubectl get configmap app-config -n produccion
kubectl describe configmap app-config -n produccion
```

### Paso 2 — Crear Secrets

```bash
kubectl apply -f secret-app.yaml

# Ver el Secret (los valores aparecen en base64)
kubectl get secret app-credentials -n produccion
kubectl describe secret app-credentials -n produccion

# Decodificar un valor puntual (útil para verificar sin exponer todo)
kubectl get secret app-credentials -n produccion \
  -o jsonpath='{.data.db-password}' | base64 -d
echo   # salto de línea
```

### Paso 3 — Consumir ConfigMap y Secret en un pod

```bash
kubectl apply -f pod-con-config.yaml

# Verificar que las variables de entorno están disponibles
kubectl exec -n produccion pod-configurado -- env | grep -E "DB_|APP_"

# Verificar que el archivo de config fue montado
kubectl exec -n produccion pod-configurado -- cat /etc/config/app.properties

# Limpiar
kubectl delete pod pod-configurado -n produccion
```

### Paso 4 — Actualizar un ConfigMap y recargar la configuración

```bash
# Actualizar el ConfigMap
kubectl patch configmap app-config -n produccion \
  --type merge \
  -p '{"data":{"APP_LOG_LEVEL":"DEBUG"}}'

# Los archivos montados se actualizan automáticamente (en ~60s)
# Las variables de entorno NO se actualizan — requieren reinicio del pod
```

---

## Parte B — Seguridad de pods (SecurityContext)

### Paso 5 — Pod sin restricciones vs pod seguro

```bash
# Pod sin restricciones (inseguro)
kubectl apply -f pod-inseguro.yaml
kubectl exec -n desarrollo pod-inseguro -- id   # corre como root

# Pod con SecurityContext apropiado
kubectl apply -f pod-seguro.yaml
kubectl exec -n desarrollo pod-seguro -- id   # corre como usuario no-root

# Intentar escalar privilegios en el pod seguro (debe fallar)
kubectl exec -n desarrollo pod-seguro -- sh -c "echo test > /etc/hosts"
```

### Paso 6 — Aplicar Pod Security Standards

Kubernetes tiene tres niveles de seguridad para namespaces:
- `privileged`: sin restricciones
- `baseline`: restricciones mínimas
- `restricted`: máxima seguridad

```bash
# Aplicar nivel "baseline" al namespace staging
kubectl label namespace staging \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/warn=restricted

# Intentar crear un pod privilegiado en staging (debe ser rechazado)
kubectl run pod-privilegiado \
  --image=nginx \
  --overrides='{"spec":{"containers":[{"name":"nginx","image":"nginx","securityContext":{"privileged":true}}]}}' \
  -n staging

# Ver el error de admisión
```

---

## Verificación

```bash
kubectl get configmaps -n produccion
kubectl get secrets -n produccion
kubectl get pods -n desarrollo
```

---

## Preguntas de reflexión para el instructor

1. ¿Por qué base64 NO es cifrado? ¿Qué alternativas existen para cifrar Secrets?
2. ¿Cuándo se actualizan los valores de un Secret montado como archivo vs variable de entorno?
3. ¿Qué riesgo hay en correr contenedores como root?
4. ¿Cómo implementarías rotación de credenciales en Kubernetes?
