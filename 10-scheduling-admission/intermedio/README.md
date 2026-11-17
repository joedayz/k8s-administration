# Lab 10 — Intermedio: Admission Controllers built-in

## Objetivo
Observar en la práctica el efecto de cuatro admission controllers que ya están activos en tu cluster por defecto: `NamespaceLifecycle`, `PodSecurity`, `ResourceQuota` y `LimitRanger` (mutante).

## Duración estimada
55 minutos

---

## Parte A — PodSecurity (Validating, con labels por namespace)

PodSecurity se activa por **label en el namespace**, no por flag global. El nivel `restricted` exige `securityContext` no privilegiado, sin capabilities extra, `runAsNonRoot` y seccomp.

```bash
kubectl create namespace admission-demo
kubectl label namespace admission-demo pod-security.kubernetes.io/enforce=restricted

kubectl apply -f pod-privilegiado.yaml -n admission-demo
```

Resultado esperado — **rechazado** por el API server, antes de llegar a etcd:

```
Error from server (Forbidden): error when creating "pod-privilegiado.yaml":
pods "pod-privilegiado" is forbidden: violates PodSecurity "restricted:latest":
privileged (container "nginx" must not set securityContext.privileged=true),
allowPrivilegeEscalation != false ...
```

```bash
kubectl delete namespace admission-demo --wait=false
```

---

## Parte B — ResourceQuota (Validating) + LimitRanger (Mutating)

```bash
kubectl create namespace quota-demo
kubectl apply -f quota-y-limitrange.yaml
```

### Paso 1 — LimitRanger inyecta límites por defecto

Crea un pod **sin** especificar `resources` y observa qué le inyectó el admission controller:

```bash
kubectl run pod-sin-limits --image=nginx:alpine -n quota-demo

sleep 3
kubectl get pod pod-sin-limits -n quota-demo -o jsonpath='{.spec.containers[0].resources}'
```

Resultado esperado — el objeto guardado en etcd **ya trae** los defaults de `limits-default`, aunque el YAML original no los tenía:

```json
{"limits":{"cpu":"100m","memory":"128Mi"},"requests":{"cpu":"50m","memory":"64Mi"}}
```

### Paso 2 — ResourceQuota frena en seco al tercer pod

La quota permite `pods: "2"` como máximo:

```bash
kubectl run pod-extra1 --image=nginx:alpine -n quota-demo     # 2/2 — OK
kubectl run pod-extra2 --image=nginx:alpine -n quota-demo     # debe fallar
```

Resultado esperado para el tercero:

```
Error from server (Forbidden): pods "pod-extra2" is forbidden:
exceeded quota: quota-pods, requested: pods=1, used: pods=2, limited: pods=2
```

```bash
kubectl describe resourcequota quota-pods -n quota-demo
```

---

## Parte C — NamespaceLifecycle

Este admission controller protege la integridad del ciclo de vida de los namespaces: impide crear objetos en namespaces inexistentes o en terminación, y protege los namespaces del sistema.

```bash
# 1. Namespace que no existe
kubectl run pod-fantasma --image=nginx:alpine -n namespace-inexistente
# Error from server (NotFound): namespaces "namespace-inexistente" not found

# 2. Namespaces protegidos no se pueden borrar
kubectl delete namespace default
# Error from server (Forbidden): namespaces "default" is forbidden: this namespace may not be deleted

# 3. Namespace en Terminating rechaza nuevo contenido
kubectl delete namespace quota-demo --wait=false
kubectl run pod-tardio --image=nginx:alpine -n quota-demo
# Error from server (Forbidden): pods "pod-tardio" is forbidden:
# unable to create new content in namespace quota-demo because it is being terminated
```

---

## Limpieza

```bash
kubectl delete namespace quota-demo admission-demo --wait=false 2>/dev/null
```

---

## Verificación final

```bash
kubectl get ns | grep -E "quota-demo|admission-demo"
# No debe devolver nada (o deben estar en Terminating)
```

---

## Preguntas de reflexión para el instructor

1. ¿Por qué PodSecurity se aplica a nivel de namespace (label) y no de cluster global?
2. ¿En qué orden se ejecutan los admission controllers mutantes vs. los validadores? ¿Por qué importa ese orden?
3. Si `LimitRanger` y `ResourceQuota` están ambos activos, ¿cuál corre primero y por qué eso evita que la quota se calcule mal?
4. ¿Qué pasaría si un pod ya corriendo consume más de lo que permite un `LimitRange` creado *después*?
