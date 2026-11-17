# Lab 13 — Básico: Aceleración con kubectl (el tema que gana el CKA)

## Objetivo
Dominar las herramientas de velocidad que marcan la diferencia en el examen: generación imperativa de YAML, filtrado con JSONPath / custom-columns / sort-by, `explain`, cambio de contexto, y creación rápida de ServiceAccounts con tokens.

## Duración estimada
60 minutos (y repetir hasta que salga sin pensar)

---

## Regla de oro del examen

> **El primer comando de CADA pregunta es `kubectl config use-context <el-que-pida-la-pregunta>`.** Resolver la tarea en el cluster equivocado = 0 puntos aunque la respuesta sea perfecta.

```bash
kubectl config get-contexts        # ver los disponibles
kubectl config current-context     # confirmar dónde estás
kubectl config use-context <ctx>   # cambiar
```

---

## Paso 1 — Preparar el terreno

```bash
kubectl create namespace cka-tacticas
kubectl apply -f web-deployment.yaml
sleep 6
kubectl get pods -n cka-tacticas
```

---

## Parte A — Generación imperativa (deja de escribir YAML a mano)

Todos estos generan el esqueleto en segundos; luego editas solo lo que falta.

```bash
# Pod
kubectl run testpod --image=nginx --dry-run=client -o yaml

# Deployment con réplicas
kubectl create deployment api --image=nginx --replicas=2 --dry-run=client -o yaml

# Service que expone un deployment
kubectl expose deployment web --port=80 --target-port=80 -n cka-tacticas --dry-run=client -o yaml

# Guardarlo para editar
kubectl run testpod --image=nginx --dry-run=client -o yaml > pod.yaml
```

> **Truco:** define un alias al inicio del examen → `alias k=kubectl` y `export do="--dry-run=client -o yaml"`. Luego: `k run x --image=nginx $do`.

---

## Parte B — `kubectl explain` (la estructura sin abrir el navegador)

```bash
# ¿Cómo se llama el campo exacto? explain recursivo
kubectl explain pod.spec.containers.resizePolicy
kubectl explain deployment.spec.strategy --recursive | head -20
```

---

## Parte C — JSONPath (extraer exactamente lo que piden)

```bash
# Las IPs de todos los pods, separadas por espacio
kubectl get pods -n cka-tacticas -o jsonpath='{.items[*].status.podIP}'

# Una línea por pod: nombre + fase (el patrón range/end es el más útil)
kubectl get pods -n cka-tacticas \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}'
```

Salida esperada del segundo:

```
web-xxxxx-aaaaa	Running
web-xxxxx-bbbbb	Running
web-xxxxx-ccccc	Running
```

---

## Parte D — custom-columns y sort-by (tablas a medida)

```bash
# Tabla con solo las columnas que importan
kubectl get pods -n cka-tacticas \
  -o custom-columns='NOMBRE:.metadata.name,NODO:.spec.nodeName,IP:.status.podIP'

# Ordenar por antigüedad (clásico: "lista los pods por fecha de creación")
kubectl get pods -n cka-tacticas --sort-by=.metadata.creationTimestamp

# Ordenar nodos por capacidad de CPU
kubectl get nodes --sort-by=.status.capacity.cpu
```

---

## Parte E — ServiceAccounts y tokens (tarea recurrente)

```bash
# Crear el SA
kubectl create serviceaccount ci-bot -n cka-tacticas

# Token efímero (TokenRequest API — reemplaza a los secrets de SA de versiones viejas)
kubectl create token ci-bot -n cka-tacticas --duration=1h

# ¿Qué puede hacer este SA AHORA? (sin permisos → no)
kubectl auth can-i list pods -n cka-tacticas \
  --as=system:serviceaccount:cka-tacticas:ci-bot
```

### Darle permisos con RBAC (todo imperativo)

```bash
kubectl create role lector-pods --verb=get,list,watch --resource=pods -n cka-tacticas
kubectl create rolebinding ci-bot-lector --role=lector-pods \
  --serviceaccount=cka-tacticas:ci-bot -n cka-tacticas

# Ahora sí
kubectl auth can-i list pods -n cka-tacticas \
  --as=system:serviceaccount:cka-tacticas:ci-bot      # yes
kubectl auth can-i delete pods -n cka-tacticas \
  --as=system:serviceaccount:cka-tacticas:ci-bot      # no (no se lo dimos)
```

> **Nota:** `kubectl auth can-i --as=...` (impersonation) es la forma más rápida de verificar RBAC sin tener que loguearte como el usuario/SA. En el examen te ahorra montar un kubeconfig completo solo para comprobar permisos.

---

## Limpieza

```bash
kubectl delete namespace cka-tacticas
rm -f pod.yaml
```

---

## Verificación final

```bash
kubectl get ns | grep cka-tacticas   # no debe devolver nada
```

---

## Preguntas de reflexión para el instructor

1. ¿Por qué `kubectl auth can-i --as=system:serviceaccount:...` es más rápido que generar un kubeconfig con el token del SA para verificar permisos?
2. En JSONPath, ¿cuándo necesitas el patrón `{range .items[*]}...{end}` en vez de `{.items[*].campo}`?
3. ¿Qué ventaja tiene `kubectl create token` (TokenRequest API) sobre el Secret de tipo `kubernetes.io/service-account-token` que se usaba antes?
4. Si una pregunta del examen dice "en el namespace X", ¿qué dos cosas debes fijar ANTES de empezar a teclear la solución? (pista: contexto y namespace)
