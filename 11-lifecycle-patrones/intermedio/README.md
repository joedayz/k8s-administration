# Lab 11 — Intermedio: Patrones Sidecar, Ambassador y Adapter

## Objetivo
Implementar los tres patrones clásicos de diseño multi-container y verificar, con evidencia real, qué problema resuelve cada uno.

## Duración estimada
60 minutos

---

## Paso 1 — Crear el namespace de trabajo

```bash
kubectl create namespace lifecycle-patrones
```

---

## Parte A — Patrón Sidecar

Un contenedor principal escribe logs a un archivo; un sidecar los "tailea" en tiempo real desde el mismo volumen — así es como funcionan en la práctica los recolectores de logs (Fluentd, Filebeat) sin tocar la app.

```bash
kubectl apply -f patron-sidecar.yaml

sleep 8
kubectl get pod patron-sidecar -n lifecycle-patrones
# READY debe ser 2/2 (dos contenedores)

kubectl logs patron-sidecar -n lifecycle-patrones -c sidecar-log-shipper --tail=5
```

Resultado esperado — el sidecar ve exactamente lo que el contenedor principal escribió, sin que la app sepa que existe:

```
linea de log 0 ...
linea de log 1 ...
linea de log 2 ...
```

---

## Parte B — Patrón Ambassador

Un ambassador es un proxy local que simplifica cómo el contenedor principal habla con un servicio externo — la app solo conoce `127.0.0.1:6380`, nunca la dirección real del backend.

```bash
kubectl apply -f patron-ambassador.yaml

sleep 20
kubectl logs patron-ambassador -n lifecycle-patrones -c app-principal
```

Resultado esperado:

```
OK
hola-desde-la-app
```

Confirma que el dato llegó al backend **real** (no fue un redis local inexistente):

```bash
kubectl exec backend-redis -n lifecycle-patrones -- redis-cli get saludo
# hola-desde-la-app
```

La app nunca tuvo que saber el nombre DNS `backend-redis` — ese conocimiento vive solo en el contenedor `ambassador`.

---

## Parte C — Patrón Adapter

Un adapter normaliza una salida de métricas en formato propietario a algo estándar (formato Prometheus), sin modificar el contenedor principal.

```bash
kubectl apply -f patron-adapter.yaml

sleep 10
kubectl exec patron-adapter -n lifecycle-patrones -c adapter-prometheus -- cat /metrics/formato-prometheus.txt
```

Resultado esperado:

```
# HELP app_peticiones_total Peticiones procesadas
# TYPE app_peticiones_total counter
app_peticiones_total 42
app_errores_total 3
app_latencia_ms 120
```

El contenedor `app-principal` sigue escribiendo su formato propio (`peticiones=42 errores=3 ...`); el adapter es el único que entiende ambos formatos.

```bash
kubectl exec patron-adapter -n lifecycle-patrones -c app-principal -- cat /metrics/raw.txt
```

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

1. ¿Qué tienen en común los tres patrones a nivel de red de Kubernetes? (pista: todos los contenedores de un pod comparten el mismo `localhost`)
2. ¿Por qué el patrón ambassador es tan común en migraciones legacy → cloud-native (apps que no pueden modificarse)?
3. Si el sidecar de logs se cae, ¿se cae también el contenedor principal? ¿Qué `restartPolicy` aplica a cada uno?
4. ¿En qué se diferencia un sidecar "clásico" (como aquí) de un sidecar declarado como `initContainers` con `restartPolicy: Always` (Kubernetes 1.29+)?
