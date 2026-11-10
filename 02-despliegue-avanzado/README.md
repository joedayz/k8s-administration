# Módulo 02 — Despliegue Avanzado y Configuración

## Rol del administrador

Como admin, no diseñas los Deployments — pero sí eres responsable de que:
- Las aplicaciones se actualicen sin downtime
- Los Jobs y CronJobs completen correctamente
- Las aplicaciones con estado (bases de datos) tengan almacenamiento persistente
- La configuración se gestione de forma consistente y segura

---

## Teoría

> 🎨 Versión a color: [teoria.html](teoria.html)

### Deployments y estrategias de actualización

Un Deployment gestiona el ciclo de vida de pods sin estado. Dos estrategias:

| Estrategia | Cómo funciona | Cuándo usarla |
|-----------|---------------|---------------|
| `RollingUpdate` | Reemplaza pods gradualmente | Aplicaciones web, APIs |
| `Recreate` | Mata todos y levanta nuevos | Apps que no soportan múltiples versiones simultáneas |

**Parámetros clave para el admin:**
- `maxUnavailable`: cuántos pods pueden estar caídos durante la actualización
- `maxSurge`: cuántos pods extra se crean temporalmente

### StatefulSets — Para aplicaciones con estado

Diferencias críticas con Deployments:
- Los pods tienen **identidad estable** (nombre predecible: `pod-0`, `pod-1`)
- Cada pod tiene su propio **PersistentVolume**
- Se crean y eliminan **en orden**
- Usan un **Headless Service** para DNS estable

**Cuándo lo verá un admin:** Bases de datos (MySQL, PostgreSQL, MongoDB, Redis), Elasticsearch, Kafka.

### Jobs y CronJobs

- **Job**: tarea que se ejecuta una vez y termina (migraciones, backups puntuales)
- **CronJob**: Job programado (backups nocturnos, reportes, limpieza de datos)

**El admin debe verificar:**
- Que los Jobs completan exitosamente
- Que los Jobs fallidos no acumulan pods muertos
- Que los CronJobs no se solapan

### Helm — Gestor de paquetes de Kubernetes

Helm es al admin de k8s lo que apt/yum es al admin de Linux. Permite:
- Instalar aplicaciones complejas con un comando
- Gestionar versiones y hacer rollback
- Personalizar configuración sin modificar YAMLs directamente

### Kustomize — Personalización sin templates

Alternativa a Helm integrada en kubectl. Permite tener una base común y aplicar "patches" por entorno (dev, staging, prod) sin duplicar YAMLs.

---

## Laboratorios

- [Lab Básico](basico/README.md) — Deployments, actualizaciones y rollback
- [Lab Intermedio](intermedio/README.md) — StatefulSets, Jobs y CronJobs
- [Lab Avanzado](avanzado/README.md) — Helm y Kustomize para gestión multi-entorno
