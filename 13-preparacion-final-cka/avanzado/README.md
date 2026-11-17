# Lab 13 — Avanzado: Vertical Pod Autoscaler (VPA)

## Objetivo
Instalar el VPA en el cluster y usarlo en **modo recomendación** (`updateMode: Off`) para que analice un workload que pide muy pocos recursos pero consume muchos, y proponga los `requests` correctos. Esto cierra el trío de autoescalado: HPA (módulo 05) + In-place Resize (módulo 11) + VPA (aquí).

## Duración estimada
50 minutos

> **Requisito:** el `metrics-server` debe estar corriendo (`kubectl top nodes` debe funcionar). En k3s ya viene instalado.

---

## Teoría rápida — los modos del VPA

| `updateMode` | Qué hace |
|--------------|----------|
| `Off` | Solo **recomienda** (no modifica pods). El más seguro y el más usado para analizar. |
| `Initial` | Aplica recomendaciones solo al crear pods nuevos. |
| `Recreate` | Expulsa y recrea pods para aplicar nuevos requests. |
| `Auto` | Como Recreate (en el futuro usará in-place resize). |

VPA ≠ HPA: **HPA escala réplicas (horizontal); VPA ajusta CPU/memoria de cada pod (vertical).** No se deben usar ambos sobre la misma métrica (CPU/mem) a la vez.

---

## Paso 1 — Instalar los componentes de VPA

El VPA no viene con Kubernetes; se instala desde el repo `kubernetes/autoscaler`. Para el modo recomendación solo necesitas los **CRDs + RBAC + recommender** (el `admission-controller` y el `updater` solo hacen falta para los modos que modifican pods).

```bash
git clone --depth 1 --branch vpa-release-1.4 https://github.com/kubernetes/autoscaler.git
cd autoscaler/vertical-pod-autoscaler/deploy

# CRDs y RBAC
kubectl apply -f vpa-v1-crd-gen.yaml
kubectl apply -f vpa-rbac.yaml

# Recommender (fija el tag de imagen explícitamente)
sed 's#vpa-recommender:[^ ]*#vpa-recommender:1.4.2#' recommender-deployment.yaml | kubectl apply -f -
kubectl rollout status deployment/vpa-recommender -n kube-system --timeout=90s
```

Verifica:

```bash
kubectl get crd | grep verticalpod
kubectl get pods -n kube-system -l app=vpa-recommender
```

> Si prefieres el instalador completo (incluye updater + admission-controller con TLS), usa `./hack/vpa-up.sh` desde `vertical-pod-autoscaler/`. Para este lab el recommender basta.

---

## Paso 2 — Desplegar un workload mal dimensionado + su VPA

`app-y-vpa.yaml` despliega una app que **pide 50m CPU / 32Mi** pero en realidad consume mucho más (genera carga con `stress`), y un VPA en modo `Off` que la observa:

```bash
kubectl create namespace cka-vpa
kubectl apply -f app-y-vpa.yaml
kubectl rollout status deployment/app-hambrienta -n cka-vpa --timeout=90s
```

---

## Paso 3 — Esperar y leer las recomendaciones

El recommender necesita ~1-2 minutos de métricas antes de proponer valores:

```bash
sleep 90

kubectl describe vpa vpa-app-hambrienta -n cka-vpa | grep -A20 "Recommendation:"
```

Salida esperada (tus números variarán según la carga):

```
  Recommendation:
    Container Recommendations:
      Container Name:  stress
      Lower Bound:
        Cpu:     25m
        Memory:  262144k
      Target:
        Cpu:     2162m        <-- ¡vs. los 50m que pedía!
        Memory:  262144k      <-- ~256Mi vs. los 32Mi que pedía
      Uncapped Target:
        Cpu:     2162m
```

| Campo | Significado |
|-------|-------------|
| **Target** | El valor que VPA recomienda poner en `requests` |
| **Lower / Upper Bound** | El rango aceptable antes de que VPA sugiera cambiar |
| **Uncapped Target** | El target sin aplicar límites de `minAllowed`/`maxAllowed` |

En modo `Off`, VPA **no toca** los pods — solo te da el número. Tú decides si editas el Deployment. Confirma que los pods siguen con los requests originales:

```bash
kubectl get pods -n cka-vpa -o custom-columns='POD:.metadata.name,CPU_REQ:.spec.containers[0].resources.requests.cpu'
```

---

## Limpieza

```bash
kubectl delete namespace cka-vpa

# Los componentes de VPA pueden quedarse para reusar. Para desinstalarlos:
# cd autoscaler/vertical-pod-autoscaler && ./hack/vpa-down.sh
# o: kubectl delete -f deploy/recommender-deployment.yaml -f deploy/vpa-rbac.yaml -f deploy/vpa-v1-crd-gen.yaml
```

---

## Verificación final

```bash
kubectl get ns | grep cka-vpa   # no debe devolver nada
```

---

## Preguntas de reflexión para el instructor

1. ¿Por qué no debes usar HPA y VPA sobre la misma métrica (CPU) a la vez? ¿Qué pasaría?
2. ¿Qué ventaja tiene `updateMode: Off` en producción frente a `Auto`? ¿Qué riesgo tiene `Recreate`?
3. ¿En qué se complementan VPA y el In-place Resize (módulo 11)? (pista: VPA dice *cuánto*, el in-place resize permite aplicarlo *sin reiniciar*)
4. ¿Por qué el VPA necesita al `metrics-server`? ¿De dónde saca el consumo real de los pods?
