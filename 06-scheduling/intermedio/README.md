# Lab 06 — Intermedio: Node Affinity, Pod AntiAffinity y DaemonSets

## Objetivo
Garantizar alta disponibilidad distribuyendo réplicas entre nodos, restringir workloads a zonas específicas y desplegar agentes en todos los workers automáticamente.

## Duración estimada
60 minutos

---

## Paso 1 — Etiquetar los nodos por zona

```bash
# Simular zonas de red (como en un datacenter real)
kubectl label nodes k3s-worker  zona=interna entorno=produccion
kubectl label nodes k3s-worker2 zona=dmz     entorno=produccion

# Verificar
kubectl get nodes --show-labels | grep zona
```

---

## Paso 2 — NodeAffinity REQUIRED (obligatoria)

El pod SOLO arranca si hay un nodo que cumpla la condición:

```bash
kubectl create namespace scheduling
kubectl apply -f pod-affinity-dmz.yaml

sleep 5
kubectl get pod pod-affinity-dmz -n scheduling -o wide
# Debe aparecer en k3s-worker2 (zona=dmz)
```

---

## Paso 3 — NodeAffinity PREFERRED (preferida)

```bash
kubectl apply -f pod-affinity-preferida.yaml

sleep 5
kubectl get pod pod-affinity-preferida -n scheduling -o wide
# Intentará ir a zona=interna, pero si no puede, va a otro nodo
```

---

## Paso 4 — Pod AntiAffinity para Alta Disponibilidad

Este es uno de los patrones más importantes en producción: evitar que dos réplicas del mismo servicio estén en el mismo nodo.

```bash
kubectl apply -f deployment-web-ha.yaml

sleep 10
kubectl get pods -n scheduling -l app=web-ha -o wide
# Cada réplica debe estar en un nodo diferente
```

Escalar y verificar que el scheduler lo gestiona:

```bash
kubectl scale deployment web-ha --replicas=4 -n scheduling
sleep 8
kubectl get pods -n scheduling -l app=web-ha -o wide
# La 4ª réplica quedará Pending — solo hay 3 nodos y AntiAffinity es Required
kubectl describe pod -n scheduling -l app=web-ha | grep -A5 "Events:"
```

---

## Paso 5 — DaemonSet solo en workers

Un caso real: el agente de logs solo debe correr en nodos worker, no en el control-plane.

```bash
kubectl apply -f daemonset-log-collector.yaml

sleep 10
kubectl get pods -n scheduling -l app=log-collector -o wide
# Solo aparece en k3s-worker y k3s-worker2, NO en k3s-server
```

---

## Paso 6 — Actualizar un DaemonSet (rolling update)

```bash
# Cambiar la imagen del agente
kubectl set image daemonset/log-collector \
  collector=busybox:1.37 \
  -n scheduling

# Seguir el rollout
kubectl rollout status daemonset/log-collector -n scheduling

# Ver historial
kubectl rollout history daemonset/log-collector -n scheduling
```

---

## Limpieza

```bash
kubectl delete namespace scheduling
kubectl label nodes k3s-worker  zona- entorno-
kubectl label nodes k3s-worker2 zona- entorno-
```

---

## Preguntas de reflexión para el instructor

1. ¿Qué ocurre si escalo un Deployment con AntiAffinity `required` a más réplicas que nodos disponibles?
2. ¿Cuál es la diferencia entre un DaemonSet y un Deployment con `replicas: N`?
3. ¿Por qué usaríamos `preferredDuringScheduling` en lugar de `required`?
4. En un cluster de producción con 20 nodos en 3 zonas, ¿cómo distribuirías una app crítica?
