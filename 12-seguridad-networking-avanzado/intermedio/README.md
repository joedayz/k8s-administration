# Lab 12 — Intermedio: Gateway API (GatewayClass, Gateway, HTTPRoute)

## Objetivo
Enrutar tráfico HTTP a una app usando Gateway API — el sucesor declarado de Ingress — aprovechando el Traefik que k3s ya trae instalado.

## Duración estimada
55 minutos

> **IP de referencia:** este lab usa `192.168.252.2` (la IP de `k3s-server`). Ajusta el valor según tu entorno.

---

## Paso 1 — Verificar que las CRDs de Gateway API ya existen

k3s instala las CRDs de Gateway API junto con Traefik por defecto:

```bash
kubectl get crd | grep gateway.networking.k8s.io
```

---

## Paso 2 — Habilitar el provider de Gateway API en Traefik

Por defecto Traefik solo escucha Ingress y sus propios CRDs — hay que activar explícitamente el provider de Gateway API:

```bash
kubectl apply -f habilitar-gateway-api.yaml

# Espera a que Traefik se reinicie con el nuevo provider
sleep 20
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik
```

### Paso 3 — Confirmar que apareció la GatewayClass

Al activar `gateway.enabled: true`, el propio chart de Traefik crea una `GatewayClass` administrada por su controlador:

```bash
kubectl get gatewayclass
# NAME      CONTROLLER                      ACCEPTED
# traefik   traefik.io/gateway-controller   True
```

---

## Paso 4 — Crear tu propio Gateway

En vez de usar el `Gateway` que Traefik crea en `kube-system` (que solo acepta rutas de su mismo namespace), crea el tuyo en un namespace de trabajo:

```bash
kubectl create namespace gateway-demo
kubectl apply -f gateway.yaml

sleep 5
kubectl get gateway gateway-demo -n gateway-demo
# PROGRAMMED debe ser True, y ADDRESS debe mostrar una IP de nodo
```

---

## Paso 5 — Desplegar la app y el HTTPRoute

```bash
kubectl apply -f app-y-httproute.yaml

kubectl rollout status deployment/app-gateway-demo -n gateway-demo --timeout=60s

kubectl get httproute ruta-app-demo -n gateway-demo -o yaml | grep -A3 "type: Accepted"
```

---

## Paso 6 — Probar el enrutamiento por hostname

El `HTTPRoute` solo acepta tráfico con el header `Host: demo.gateway.local` — así es como Gateway API (igual que Ingress) hace *virtual hosting* sobre una sola IP.

```bash
# Con el host correcto -> responde la app
curl -s -H "Host: demo.gateway.local" http://192.168.252.2:80/

# Con cualquier otro host -> 404, no hay ruta que matchee
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: otro-host.local" http://192.168.252.2:80/
```

---

## Limpieza

```bash
kubectl delete namespace gateway-demo
```

---

## Verificación final

```bash
kubectl get pods -A | grep gateway-demo
# No debe devolver nada
```

---

## Preguntas de reflexión para el instructor

1. ¿Qué problema de gobernanza resuelve separar `GatewayClass` (del admin de plataforma) de `HTTPRoute` (del equipo de la app) que Ingress no resolvía bien?
2. ¿Por qué el `Gateway` en `kube-system` tiene `allowedRoutes.namespaces.from: Same` por defecto? ¿Qué pasaría si fuera `All`?
3. Si tuvieras dos equipos compartiendo el mismo `Gateway`, ¿cómo evitarías que un `HTTPRoute` de un equipo capture el tráfico destinado al otro?
4. ¿Qué ventaja tiene Gateway API sobre Ingress para soportar protocolos más allá de HTTP (gRPC, TCP, TLS passthrough)?
