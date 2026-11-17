# Módulo 10 — Scheduling Manual y Admission Control

## Rol del administrador

El scheduler y la cadena de admission control son los dos puntos donde Kubernetes decide, respectivamente, **dónde** corre un pod y **si se le permite existir tal como fue enviado**. Como admin necesitas:
- Entender qué hace el kube-scheduler realmente por debajo (Binding API), para poder depurarlo cuando falla
- Saber qué admission controllers están activos en tu cluster y qué efecto tiene cada uno
- Poder bloquear o mutar objetos en el API server antes de que lleguen a etcd (políticas de organización, seguridad, cuotas)

---

## Teoría

### ¿Qué hace realmente el scheduler?

Cuando creas un pod sin `nodeName`, el flujo es:

```
1. kube-scheduler ve un pod con spec.nodeName vacío (Pending)
2. Filtra nodos candidatos + los puntúa
3. Llama al endpoint /binding del API server:
   POST /api/v1/namespaces/<ns>/pods/<pod>/binding
4. El API server escribe spec.nodeName en el pod
5. El kubelet del nodo asignado ve el pod y lo arranca
```

Un admin puede **saltarse el scheduler por completo** escribiendo `spec.nodeName` directamente, o llamando al mismo endpoint `/binding` a mano — es el mecanismo que usan los schedulers personalizados.

### La cadena de admission control

Toda petición de escritura al API server pasa por esta tubería, **después** de autenticación/autorización y **antes** de persistir en etcd:

```
Request ──▶ Autenticación ──▶ Autorización (RBAC) ──▶ Mutating Admission ──▶ Validación de esquema ──▶ Validating Admission ──▶ etcd
```

| Tipo | Qué hace | Ejemplos built-in |
|------|----------|--------------------|
| **Mutating** | Modifica el objeto antes de guardarlo | `DefaultStorageClass`, `ServiceAccount` (inyecta token) |
| **Validating** | Acepta o rechaza el objeto (no lo modifica) | `ResourceQuota`, `NamespaceLifecycle`, `PodSecurity` |

Desde Kubernetes 1.30 (GA), además de los webhooks tradicionales existe **ValidatingAdmissionPolicy**: reglas declarativas en CEL que corren *dentro* del API server, sin necesidad de levantar un servidor webhook externo.

```
Webhook tradicional:          API server ──HTTPS──▶ tu servidor (TLS, disponibilidad, latencia)
ValidatingAdmissionPolicy:    API server ──evalúa CEL in-process──▶ decisión
```

---

## Laboratorios

- [Lab Básico](basico/README.md) — Manual Scheduling: `nodeName` y la Binding API
- [Lab Intermedio](intermedio/README.md) — Admission Controllers built-in: NamespaceLifecycle, ResourceQuota, LimitRanger, PodSecurity
- [Lab Avanzado](avanzado/README.md) — ValidatingAdmissionPolicy (CEL) y ValidatingWebhookConfiguration personalizado
