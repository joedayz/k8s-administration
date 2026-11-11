# Módulo 05 — Operación y Automatización

## Rol del administrador

Este módulo es el más crítico para el día a día de un admin:
- Garantizar que las aplicaciones escalen cuando hay carga
- Mantener el cluster saludable con backups y actualizaciones
- Automatizar despliegues con GitOps para reducir errores humanos
- Extender Kubernetes con operadores para gestionar software complejo
- Diagnosticar y resolver problemas en producción bajo presión

---

## Teoría

> 🎨 Versión a color: [teoria.html](teoria.html)

### Escalado en Kubernetes

| Tipo | Qué escala | Cuándo usarlo |
|------|-----------|---------------|
| Manual | Réplicas de un Deployment | Mantenimiento, ajustes puntuales |
| **HPA** (Horizontal Pod Autoscaler) | Número de pods | Carga variable en aplicaciones |
| **VPA** (Vertical Pod Autoscaler) | CPU/RAM de pods existentes | Optimizar recursos sin escalar réplicas |
| **Cluster Autoscaler** | Nodos del cluster | Cloud: añadir/quitar VMs automáticamente |

### GitOps

GitOps es el paradigma donde **Git es la fuente de verdad** del estado del cluster. Nadie aplica YAMLs manualmente en producción — todo pasa por Git.

```
Developer → git push → Git repo → Argo CD/Flux → Kubernetes cluster
```

Ventajas para el admin:
- Auditoría completa: quién cambió qué y cuándo
- Rollback = `git revert`
- Menor riesgo de errores manuales

### CRDs y Operadores

- **CRD (Custom Resource Definition)**: extiende la API de Kubernetes con nuevos tipos de objetos
- **Operador**: controlador que gestiona aplicaciones complejas usando CRDs

Ejemplo: el operador de PostgreSQL gestiona clusters de bases de datos como si fueran objetos nativos de Kubernetes.

### Troubleshooting — Metodología del admin

```
1. ¿Qué está fallando?    → kubectl get pods/nodes
2. ¿Por qué falla?        → kubectl describe / kubectl logs
3. ¿Cuándo empezó?        → kubectl get events --sort-by=lastTimestamp
4. ¿Qué cambió?           → git log / helm history
5. ¿Cómo lo resuelvo?     → Según el diagnóstico
6. ¿Cómo lo prevengo?     → Alertas, probes, recursos adecuados
```

---

## Laboratorios

- [Lab Básico](basico/README.md) — HPA, escalado manual y PodDisruptionBudget
- [Lab Intermedio](intermedio/README.md) — Backup con Velero y GitOps con Argo CD
- [Lab Avanzado](avanzado/README.md) — CRDs, operadores y troubleshooting avanzado
