# Módulo 04 — Seguridad y Observabilidad

## Rol del administrador

La seguridad y la observabilidad son el núcleo del trabajo de un admin en producción:
- Controlar **quién** puede hacer **qué** en el cluster (RBAC)
- Gestionar **credenciales y configuración** de forma segura (Secrets, ConfigMaps)
- Garantizar que el cluster es **observable**: métricas, logs y alertas
- Responder a incidentes con datos, no con suposiciones

---

## Teoría

> 🎨 Versión a color: [teoria.html](teoria.html)

### RBAC — Control de Acceso Basado en Roles

RBAC responde a la pregunta: ¿quién puede hacer qué sobre qué recursos?

```
Subject (¿quién?)     Verb (¿qué?)     Resource (¿sobre qué?)
──────────────────    ─────────────    ──────────────────────
User / ServiceAccount get, list,       pods, deployments,
Group                 create, delete,  services, secrets,
                      update, patch,   nodes, namespaces...
                      watch
```

**Objetos RBAC:**
- `Role` / `ClusterRole`: define los permisos
- `RoleBinding` / `ClusterRoleBinding`: asigna los permisos a un subject

| Objeto | Alcance |
|--------|---------|
| `Role` | Un namespace |
| `ClusterRole` | Todo el cluster |
| `RoleBinding` | Asigna Role o ClusterRole en un namespace |
| `ClusterRoleBinding` | Asigna ClusterRole en todo el cluster |

### Secrets y ConfigMaps

| Objeto | Para qué | Cómo se monta |
|--------|----------|---------------|
| `ConfigMap` | Configuración no sensible | Variables de entorno o archivos |
| `Secret` | Credenciales, tokens, certificados | Variables de entorno o archivos |

**Importante:** Los Secrets en Kubernetes están codificados en base64, NO cifrados por defecto. Para cifrado real se usa Sealed Secrets, Vault o cifrado en reposo de etcd.

### Observabilidad — Los tres pilares

1. **Métricas**: datos numéricos a lo largo del tiempo → Prometheus + Grafana
2. **Logs**: eventos de texto de los componentes → Loki, Elasticsearch
3. **Trazas**: flujo de una petición entre servicios → Jaeger, Tempo

En k3s, el stack mínimo de observabilidad es:
- `metrics-server` (incluido) → `kubectl top`
- Prometheus + Grafana → se instala con Helm

---

## Laboratorios

- [Lab Básico](basico/README.md) — RBAC: usuarios, roles y permisos
- [Lab Intermedio](intermedio/README.md) — Secrets, ConfigMaps y Pod Security
- [Lab Avanzado](avanzado/README.md) — Prometheus, Grafana y alertas
