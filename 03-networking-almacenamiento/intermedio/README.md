# Lab 03 — Intermedio: Ingress con TLS y Network Policies

## Objetivo
Configurar acceso externo seguro mediante Ingress y aislar el tráfico de red entre namespaces con Network Policies.

## Duración estimada
60 minutos

---

## Parte A — Ingress con Traefik (k3s)

### Paso 1 — Verificar que Traefik está corriendo

```bash
# Traefik es el Ingress Controller por defecto en k3s
kubectl get pods -n kube-system | grep traefik
kubectl get service -n kube-system | grep traefik
```

### Paso 2 — Desplegar dos aplicaciones

```bash
kubectl apply -f apps-ingress.yaml

kubectl get pods -n desarrollo
kubectl get services -n desarrollo
```

### Paso 3 — Configurar Ingress por path

```bash
kubectl apply -f ingress-paths.yaml

# Ver el Ingress
kubectl get ingress -n desarrollo
kubectl describe ingress app-ingress -n desarrollo
```

Probar desde tu Mac:

```bash
# Obtener la IP del nodo
kubectl get nodes -o wide

# Probar los paths (reemplaza IP por la IP del nodo)
curl -H "Host: app.lab.local" http://<IP-NODO>/frontend
curl -H "Host: app.lab.local" http://<IP-NODO>/backend

# O agregar a /etc/hosts en tu Mac:
# <IP-NODO>  app.lab.local
# Luego: curl http://app.lab.local/frontend
```

### Paso 4 — TLS con certificado autofirmado

```bash
# Generar certificado autofirmado
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key \
  -out tls.crt \
  -subj "/CN=app.lab.local/O=laboratorio"

# Crear Secret con el certificado
kubectl create secret tls app-tls \
  --cert=tls.crt \
  --key=tls.key \
  -n desarrollo

# Verificar
kubectl get secret app-tls -n desarrollo

# Aplicar Ingress con TLS
kubectl apply -f ingress-tls.yaml

# Probar HTTPS
curl -k -H "Host: app.lab.local" https://<IP-NODO>/frontend

# Limpiar archivos temporales
rm tls.key tls.crt
```

---

## Parte B — Network Policies

### Paso 5 — Demostrar tráfico sin restricciones (situación inicial)

```bash
# Sin Network Policies, cualquier pod puede hablar con cualquier otro
kubectl run test-libre --image=busybox:1.36 --restart=Never -n staging -- \
  wget -qO- --timeout=5 http://backend-svc.desarrollo.svc.cluster.local

kubectl logs test-libre -n staging
kubectl delete pod test-libre -n staging
```

### Paso 6 — Aplicar Network Policy de aislamiento

```bash
kubectl apply -f network-policy.yaml

# Ahora el namespace staging NO puede acceder al namespace desarrollo
kubectl run test-bloqueado --image=busybox:1.36 --restart=Never -n staging -- \
  wget -qO- --timeout=5 http://backend-svc.desarrollo.svc.cluster.local

kubectl logs test-bloqueado -n staging   # debe mostrar timeout
kubectl delete pod test-bloqueado -n staging

# Pero los pods dentro de desarrollo SÍ pueden comunicarse
kubectl run test-permitido --image=busybox:1.36 --restart=Never -n desarrollo -- \
  wget -qO- --timeout=5 http://backend-svc.desarrollo.svc.cluster.local

kubectl logs test-permitido -n desarrollo   # debe funcionar
kubectl delete pod test-permitido -n desarrollo
```

### Paso 7 — Política de egress (tráfico saliente)

```bash
kubectl apply -f network-policy-egress.yaml

# Los pods de producción solo pueden salir hacia el namespace de staging
# Tráfico hacia internet bloqueado (excepto DNS)
```

---

## Verificación

```bash
kubectl get ingress -A
kubectl get networkpolicy -A
```

---

## Preguntas de reflexión para el instructor

1. ¿Por qué Traefik en lugar de nginx como Ingress Controller?
2. ¿Qué pasa si no hay ninguna NetworkPolicy en un namespace?
3. ¿Una NetworkPolicy de ingress afecta el tráfico saliente del pod?
4. ¿Cómo gestionas la renovación de certificados TLS en producción?
