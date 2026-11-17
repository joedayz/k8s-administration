# Lab 11 — Básico: Init Containers

## Objetivo
Entender el ciclo de vida secuencial de los init containers: cómo preparan el entorno antes del contenedor principal, cómo comparten volúmenes con él, y qué pasa cuando uno falla.

## Duración estimada
40 minutos

---

## Paso 1 — Crear el namespace de trabajo

```bash
kubectl create namespace lifecycle-patrones
```

---

## Paso 2 — Desplegar un pod con dos init containers

`pod-con-init.yaml` define dos init containers que corren **en orden**: primero `esperar-config` (simula esperar una dependencia), luego `descargar-contenido` (escribe un archivo en un volumen compartido). Solo cuando ambos terminan con éxito arranca `nginx`.

```bash
kubectl apply -f pod-con-init.yaml
```

---

## Paso 3 — Observar las fases del ciclo de vida

```bash
# Repite este comando cada 2 segundos y observa cómo cambia STATUS
kubectl get pod pod-con-init -n lifecycle-patrones -w
```

Deberías ver esta secuencia:

```
Pending  →  Init:0/2  →  Init:1/2  →  PodInitializing  →  Running
```

Corta el `-w` con Ctrl+C cuando llegue a `Running`.

---

## Paso 4 — Verificar que el contenido del init container llegó al contenedor principal

```bash
kubectl exec pod-con-init -n lifecycle-patrones -c nginx -- cat /usr/share/nginx/html/index.html
# Debe imprimir: generado en init
```

Revisa los logs de cada init container por separado (ya terminaron, pero Kubernetes los conserva):

```bash
kubectl logs pod-con-init -n lifecycle-patrones -c esperar-config
kubectl logs pod-con-init -n lifecycle-patrones -c descargar-contenido
```

---

## Paso 5 — Qué pasa cuando un init container falla

```bash
kubectl apply -f pod-init-falla.yaml

sleep 8
kubectl get pod pod-init-falla -n lifecycle-patrones
# STATUS: Init:Error o Init:CrashLoopBackOff

kubectl describe pod pod-init-falla -n lifecycle-patrones | grep -A5 "Events:"
```

El contenedor principal (`nginx`) **nunca llega a crearse** — Kubernetes reintenta el init container indefinidamente según la `restartPolicy` del pod (`Always` por defecto).

---

## Limpieza

```bash
kubectl delete namespace lifecycle-patrones
```

---

## Verificación final

```bash
kubectl get pods -A | grep lifecycle-patrones
# No debe devolver nada
```

---

## Preguntas de reflexión para el instructor

1. ¿Por qué los init containers corren secuencialmente y los containers principales en paralelo?
2. Si tienes 3 init containers y el segundo falla, ¿se vuelve a ejecutar el primero en el siguiente reintento?
3. ¿Qué diferencia hay entre usar un init container para "esperar a una dependencia" y usar un `readinessProbe` en el contenedor principal?
4. ¿Los init containers consumen `resources.requests` del nodo mientras corren? ¿Qué implica eso para el scheduling del pod?
