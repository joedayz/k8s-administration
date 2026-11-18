# Módulo 10 — Simulacros CKA

## Rol del administrador

Este módulo final consolida todo lo aprendido con escenarios prácticos que replican el formato del examen CKA (Certified Kubernetes Administrator). Cada reto tiene:
- Un enunciado breve (como en el examen)
- Un tiempo límite
- La solución paso a paso
- Comandos de verificación

---

## Formato del examen CKA

- **Duración:** 2 horas
- **Tareas:** 15-20 ejercicios prácticos
- **Entorno:** terminal Linux con kubectl preconfigurado
- **Nota de aprobado:** 66%
- **Herramientas permitidas:** kubectl, documentación oficial de Kubernetes

### Dominios evaluados

| Dominio | Peso |
|---------|------|
| Cluster Architecture, Installation & Configuration | 25% |
| Workloads & Scheduling | 15% |
| Services & Networking | 20% |
| Storage | 10% |
| Troubleshooting | 30% |

---

## Teoría

> 🎨 Versión a color: [teoria.html](teoria.html)

### Estrategias para el examen CKA

1. **Gestiona el tiempo** — si un ejercicio te lleva más de 5 minutos, salta al siguiente
2. **Usa `kubectl` imperativo** cuando sea posible: `kubectl create`, `kubectl expose`, `kubectl scale`
3. **Familiarízate con JSONPath** — muchos ejercicios piden extraer datos específicos
4. **Guarda los manifiestos** — crea archivos YAML para poder re-aplicarlos si algo falla
5. **Usa `kubectl explain`** — es tu documentación offline durante el examen

### Atajos de kubectl para el examen

```bash
# Alias obligatorios
alias k=kubectl
alias kgp="kubectl get pods"
alias kgs="kubectl get svc"
alias kgd="kubectl get deploy"
alias kgno="kubectl get nodes"
alias kdn="kubectl describe node"

# Dry-run para generar YAMLs rápidamente
kubectl create deployment nginx --image=nginx --dry-run=client -o yaml > deploy.yaml

# Explain para ver la estructura de un recurso
kubectl explain pod.spec.containers.resources
kubectl explain deployment.spec.strategy.rollingUpdate

# JSONPath para extraer datos
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.namespace}{"\n"}{end}'
```

---

## Laboratorios

- [Lab Básico](basico/README.md) — Retos rápidos (5 min cada uno) — Workloads y Services
- [Lab Intermedio](intermedio/README.md) — Retos de dificultad media (10 min) — Networking, Storage y RBAC
- [Lab Avanzado](avanzado/README.md) — Retos completos estilo examen (15 min) — Troubleshooting y Cluster ops
