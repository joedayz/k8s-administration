# Lab 05 — Básico: HPA, escalado y PodDisruptionBudget

## Objetivo
Configurar escalado automático horizontal y garantizar disponibilidad durante operaciones de mantenimiento con PodDisruptionBudgets.

## Duración estimada
45 minutos

---

## Paso 1 — Desplegar aplicación para escalar

```bash
kubectl apply -f deployment-escalable.yaml

kubectl get deployment app-escalable -n produccion
kubectl get pods -n produccion -l app=app-escalable
```

---

## Paso 2 — Configurar HPA (Horizontal Pod Autoscaler)

```bash
kubectl apply -f hpa.yaml

# Ver el HPA
kubectl get hpa -n produccion
kubectl describe hpa app-escalable-hpa -n produccion
```

El HPA necesita metrics-server para leer el consumo de CPU (en k3s viene incluido).

---

## Paso 3 — Generar carga para disparar el escalado

```bash
# En una terminal: observar el HPA en tiempo real
kubectl get hpa app-escalable-hpa -n produccion -w

# En otra terminal: generar carga con VARIOS clientes concurrentes.
# Un solo wget secuencial (sin keep-alive) no sostiene suficiente CPU:
# además, el HPA tiene una banda de tolerancia del 10% por defecto y
# NO escala si el uso está entre 45%-55% con un target de 50%. Por eso
# usamos 5 pods generando carga en paralelo, para superar claramente
# ese umbral.
for i in 1 2 3 4 5; do
  kubectl run generador-carga-$i \
    --image=busybox:1.36 \
    --restart=Never \
    --labels=app=generador-carga \
    -n produccion \
    -- sh -c "while true; do wget -qO- http://app-escalable-svc.produccion.svc.cluster.local; done"
done

# Observar cómo el HPA aumenta las réplicas automáticamente
# Con carga concurrente la CPU debería superar el 55% y disparar el escalado

# Detener la carga
kubectl delete pod -n produccion -l app=generador-carga

# Observar cómo el HPA reduce las réplicas (tarda unos minutos, por el
# stabilizationWindowSeconds de scaleDown en hpa.yaml)
kubectl get hpa app-escalable-hpa -n produccion -w
```

---

## Paso 4 — PodDisruptionBudget

El PDB garantiza que durante un `drain` del nodo, siempre quede un mínimo de pods disponibles.

```bash
kubectl apply -f pdb.yaml

# Ver el PDB
kubectl get pdb -n produccion
kubectl describe pdb app-escalable-pdb -n produccion
```

**Probar el PDB durante un drain:**

```bash
# Escalar a 3 réplicas para tener margen
kubectl scale deployment app-escalable --replicas=3 -n produccion

# Intentar drenar el nodo (el PDB debe limitar la operación)
# En single-node esto es más visual, en multi-node se ve cómo respeta el mínimo
kubectl drain k3s-server --ignore-daemonsets --delete-emptydir-data --dry-run

# Restaurar el nodo
kubectl uncordon k3s-server
```

---

## Paso 5 — Verificar métricas de escalado

```bash
# Ver consumo actual de pods
kubectl top pods -n produccion -l app=app-escalable

# Ver métricas del HPA
kubectl describe hpa app-escalable-hpa -n produccion | grep -A10 "Metrics:"
```

---

## Verificación

```bash
kubectl get hpa -n produccion
kubectl get pdb -n produccion
```

---

## Limpieza

Estos recursos son exclusivos de este lab: ningún nivel intermedio o avanzado de este módulo los reutiliza. `produccion` es un namespace compartido con otros labs, así que no se borra — solo los objetos creados aquí.

```bash
kubectl delete hpa app-escalable-hpa -n produccion
kubectl delete pdb app-escalable-pdb -n produccion
kubectl delete deployment app-escalable -n produccion
kubectl delete service app-escalable-svc -n produccion

# Por si quedó algún generador de carga sin borrar
kubectl delete pod -n produccion -l app=generador-carga --ignore-not-found
```

---

## Preguntas de reflexión para el instructor

1. ¿Qué pasa si el metrics-server no está disponible? ¿El HPA sigue funcionando?
2. ¿Cuál es el tiempo de espera (cooldown) por defecto antes de que el HPA reduzca réplicas?
3. ¿Qué pasa si el PDB dice `minAvailable: 3` pero solo hay 2 pods?
4. ¿Cuándo usarías VPA en lugar de HPA?
