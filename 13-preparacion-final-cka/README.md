# Módulo 13 — Preparación Final CKA (Tácticas de Examen)

## Rol del administrador

Este módulo no introduce arquitectura nueva: es la **última clase antes del examen**. El CKA no se pierde por no saber los conceptos — se pierde por **tiempo**. Dos candidatos con el mismo conocimiento aprueban o reprueban según lo rápido que generen YAML, filtren salida y cambien de contexto. Aquí consolidamos:
- La velocidad imperativa y el filtrado de salida (JSONPath, custom-columns, sort-by) que ahorran minutos en cada pregunta
- Dos temas de scheduling que el examen incluye y que no vimos a fondo: **Multiple Schedulers** y **Scheduler Profiles**
- El tercer pilar del autoescalado: **VPA** (ya vimos HPA en el módulo 05 y el in-place resize en el 11)

---

## Teoría

### Por qué la velocidad gana el CKA

El examen da ~15-20 tareas en 2 horas. Escribir un pod YAML a mano cuesta ~2 min; generarlo con `--dry-run=client -o yaml` cuesta ~10 segundos. Multiplica por 20 preguntas y entenderás por qué el filtrado y la generación imperativa son el tema #1.

```
kubectl run / create / expose  --dry-run=client -o yaml > base.yaml   ← genera el esqueleto
kubectl explain <recurso>.<campo> --recursive                         ← recuerda la estructura sin docs
kubectl get ... -o jsonpath / custom-columns / --sort-by             ← extrae solo lo que la pregunta pide
kubectl config use-context <ctx>                                      ← ¡SIEMPRE el primer comando de cada pregunta!
```

### Los tres niveles de autoescalado

| Mecanismo | Qué ajusta | Módulo |
|-----------|-----------|--------|
| **HPA** (Horizontal) | Número de réplicas | 05 |
| **In-place Resize** | CPU/memoria de un pod sin reiniciarlo | 11 |
| **VPA** (Vertical) | Recomienda/ajusta requests y limits de un workload | **este** |

### Multiple Schedulers

El `kube-scheduler` por defecto no es el único posible: puedes desplegar un **segundo scheduler** con su propia lógica y hacer que pods específicos lo usen vía `spec.schedulerName`. Los **Scheduler Profiles** son la evolución moderna: un mismo binario de scheduler puede exponer varios perfiles (cada uno con su nombre y sus plugins activados/desactivados) sin desplegar procesos separados.

```
Pod sin schedulerName          ──▶  default-scheduler
Pod con schedulerName: mi-sched ──▶  tu scheduler / perfil personalizado
```

---

## Laboratorios

- [Lab Básico](basico/README.md) — Aceleración con kubectl: JSONPath, custom-columns, sort-by, generación imperativa, explain, contexts y ServiceAccount tokens
- [Lab Intermedio](intermedio/README.md) — Multiple Schedulers y Scheduler Profiles
- [Lab Avanzado](avanzado/README.md) — Vertical Pod Autoscaler (VPA)
