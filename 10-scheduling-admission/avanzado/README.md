# Lab 10 — Avanzado: ValidatingAdmissionPolicy y Webhooks personalizados

## Objetivo
Implementar dos mecanismos distintos para extender la admisión de Kubernetes con reglas propias: una política declarativa en CEL (`ValidatingAdmissionPolicy`, sin infraestructura externa) y un webhook HTTP tradicional con TLS (`ValidatingWebhookConfiguration`).

## Duración estimada
90 minutos

---

## Parte A — ValidatingAdmissionPolicy (CEL, sin servidor externo)

Vamos a exigir que todo pod creado en el namespace `vap-demo` tenga el label `equipo` definido — una regla de gobierno típica en organizaciones grandes.

```bash
kubectl create namespace vap-demo
kubectl apply -f validating-admission-policy.yaml

# El API server tarda unos segundos en compilar y propagar la política —
# si pruebas inmediatamente, el pod se creará como si la policy no existiera.
sleep 5
```

### Paso 1 — Probar el rechazo

```bash
kubectl run pod-sin-label --image=nginx:alpine -n vap-demo
```

Resultado esperado:

```
The pods "pod-sin-label" is invalid: : ValidatingAdmissionPolicy 'exigir-label-equipo'
with binding 'exigir-label-equipo-binding' denied request:
Todo pod debe tener el label 'equipo' que identifique al dueño
```

### Paso 2 — Probar que sí funciona con el label

```bash
kubectl run pod-con-label --image=nginx:alpine -n vap-demo --labels=equipo=plataforma
kubectl get pod pod-con-label -n vap-demo
```

### Limpiar la política antes de pasar a la Parte B

```bash
kubectl delete -f validating-admission-policy.yaml
kubectl delete pod pod-con-label -n vap-demo --ignore-not-found
```

> ⚠️ Es importante borrarla ahora: si la dejas activa, bloqueará también los pods del webhook que vamos a desplegar en la Parte B si vivieran en este mismo namespace.

---

## Parte B — Webhook de validación personalizado

Vamos a construir un webhook real que rechace cualquier pod cuya imagen use el tag `:latest` (o no tenga tag) — una de las malas prácticas más comunes que se piden auditar en producción.

### Paso 3 — Generar certificados y desplegar el servidor del webhook

El webhook **debe vivir en su propio namespace** (`webhook-system`), nunca en el namespace que vigila — si no, al reiniciarse sus propios pods pasarían por su propio webhook y, si el único pod existente se cae, nadie puede reemplazarlo (`no endpoints available for service`, un auto-bloqueo real que puede dejar el webhook sin forma de recuperarse).

```bash
chmod +x generar-certificados.sh
./generar-certificados.sh
```

Esto crea el namespace `webhook-system`, el secreto TLS, e imprime el `CA_BUNDLE` en base64 que necesitas en el paso 5.

Ahora despliega el código del webhook (un servidor HTTPS minimalista en Python, sin build de imagen) y el Deployment/Service:

```bash
kubectl create configmap webhook-server-code --from-file=webhook_server.py -n webhook-system
kubectl apply -f deployment-webhook.yaml

kubectl rollout status deployment/admission-webhook -n webhook-system --timeout=60s
```

### Paso 4 — Revisar la lógica del webhook

`webhook_server.py` recibe un `AdmissionReview`, inspecciona `spec.containers[].image`, y responde `allowed: false` si el tag es `:latest` o no existe. Es el mismo contrato HTTP que usan OPA Gatekeeper o Kyverno por debajo.

### Paso 5 — Registrar el ValidatingWebhookConfiguration

Sustituye el placeholder del CA bundle (impreso por el script del paso 3) y aplica:

```bash
CA_BUNDLE="<pega aquí el valor impreso por generar-certificados.sh>"
sed "s|CA_BUNDLE_PLACEHOLDER|$CA_BUNDLE|" validating-webhook-config.yaml | kubectl apply -f -
```

Fíjate en el `namespaceSelector`: solo aplica a `vap-demo`, **no** a `webhook-system` (donde corre el propio webhook) ni al resto del cluster.

### Paso 6 — Probar el rechazo y la aceptación

```bash
# Debe RECHAZARSE
kubectl run pod-latest --image=nginx:latest -n vap-demo

# Debe ACEPTARSE (tag fijo)
kubectl run pod-pinned --image=nginx:1.27-alpine -n vap-demo

# Debe ACEPTARSE (namespace fuera del alcance del webhook)
kubectl run pod-latest-otro --image=nginx:latest -n default
```

Resultado esperado para el primero:

```
Error from server: admission webhook "prohibir-tag-latest.webhook-system.svc" denied the request:
Imagen 'nginx:latest' usa tag ':latest' (o ninguno) — prohibido por politica de admision
```

---

## Limpieza

```bash
kubectl delete validatingwebhookconfiguration prohibir-tag-latest --ignore-not-found
kubectl delete validatingadmissionpolicybinding exigir-label-equipo-binding --ignore-not-found
kubectl delete validatingadmissionpolicy exigir-label-equipo --ignore-not-found
kubectl delete namespace vap-demo webhook-system --wait=false
kubectl delete pod pod-latest-otro -n default --ignore-not-found
```

---

## Verificación final

```bash
kubectl get validatingwebhookconfigurations | grep prohibir-tag-latest
kubectl get validatingadmissionpolicies | grep exigir-label-equipo
# Ninguno de los dos comandos debe devolver resultados
```

---

## Preguntas de reflexión para el instructor

1. ¿Cuándo preferirías `ValidatingAdmissionPolicy` (CEL) sobre un webhook tradicional? ¿Qué pierdes al usar CEL (piensa en llamadas a sistemas externos)?
2. ¿Qué pasa si el webhook está caído y `failurePolicy: Fail`? ¿Y si fuera `Ignore`? ¿Cuál es más seguro y cuál más disponible?
3. ¿Por qué el webhook necesita vivir en un namespace distinto al que vigila? Reconstruye mentalmente la secuencia de fallos que viste si lo desplegaras en `vap-demo`.
4. Un `MutatingWebhookConfiguration` corre antes que los `ValidatingWebhookConfiguration`. ¿Por qué ese orden importa para un caso como inyectar sidecars (Istio, Linkerd)?
