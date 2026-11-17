# Módulo 11 — Lifecycle de Pods y Patrones Multi-Container

## Rol del administrador

Un pod no es "un contenedor" — es un ciclo de vida con fases bien definidas y, muy a menudo, varios contenedores colaborando. Como admin necesitas:
- Saber diagnosticar por qué un pod se queda atascado en `Init:0/1` o similar
- Reconocer los patrones de diseño multi-container (sidecar, ambassador, adapter) cuando los ves en producción, y saber cuándo recomendarlos
- Aprovechar el redimensionamiento en caliente de pods para ajustar recursos sin el downtime de un restart

---

## Teoría

### Fases del ciclo de vida de un Pod

```
Pending ──▶ Init containers (secuencial, uno a la vez) ──▶ Containers principales (paralelo) ──▶ Running ──▶ Succeeded / Failed
```

| Fase | Qué significa |
|------|----------------|
| `Pending` | El pod fue aceptado pero algún contenedor (init o principal) aún no arrancó |
| `Init:N/M` | Van N de M init containers completados |
| `Running` | Todos los init containers terminaron y al menos un contenedor principal está corriendo |
| `Succeeded` / `Failed` | Todos los contenedores terminaron (para Jobs, principalmente) |

### Init Containers

Corren **antes** que los contenedores principales, **uno tras otro** (no en paralelo), y deben terminar con éxito (`exit 0`) para que el pod avance. Si uno falla, Kubernetes lo reintenta según la `restartPolicy` del pod — el pod entero se queda bloqueado en esa fase.

Casos de uso típicos:
- Esperar a que una dependencia esté lista (`wait-for-db`)
- Clonar código o descargar configuración antes de arrancar la app
- Preparar permisos/directorios en un volumen compartido

### Patrones Multi-Container

Varios contenedores en el mismo pod comparten red (localhost) y, opcionalmente, volúmenes. Tres patrones clásicos:

| Patrón | Qué hace | Ejemplo real |
|--------|----------|--------------|
| **Sidecar** | Contenedor auxiliar que extiende/monitorea al principal | Recolector de logs, proxy de service mesh (Envoy) |
| **Ambassador** | Proxy que simplifica cómo el contenedor principal habla con el exterior | Conectar a una réplica de Redis sin que la app sepa la IP real |
| **Adapter** | Normaliza la salida del contenedor principal a un formato estándar | Convertir métricas propietarias a formato Prometheus |

Desde Kubernetes 1.29 (GA en 1.29+), los *sidecars* pueden declararse como `initContainers` con `restartPolicy: Always` — arrancan antes que el contenedor principal y Kubernetes los mantiene vivos durante toda la vida del pod.

### In-place Pod Resize (GA desde 1.33)

Tradicionalmente, cambiar `resources.requests/limits` de un pod obligaba a recrearlo. Desde que esta feature es GA, puedes hacer `kubectl patch` sobre `spec.containers[].resources` de un pod **ya corriendo**, y Kubernetes intenta aplicar el cambio sin reiniciar el contenedor (si el *resize policy* del contenedor lo permite).

```
kubectl patch pod ... --subresource resize --patch '...'
   │
   ▼
¿El nodo tiene capacidad?  ──No──▶  Pod queda en status.resize: Infeasible
   │ Sí
   ▼
¿resizePolicy permite sin restart?  ──No──▶  Kubernetes reinicia el contenedor con los nuevos valores
   │ Sí
   ▼
Recursos actualizados en caliente, sin restart
```

---

## Laboratorios

- [Lab Básico](basico/README.md) — Init Containers
- [Lab Intermedio](intermedio/README.md) — Patrones Sidecar, Ambassador y Adapter
- [Lab Avanzado](avanzado/README.md) — In-place Pod Resize
