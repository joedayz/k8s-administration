# Lab 08 — Intermedio: Troubleshooting de Servicios y Red

## Objetivo
Diagnosticar los problemas más frecuentes de conectividad entre servicios: selectores incorrectos, puertos erróneos, problemas de DNS y NetworkPolicies bloqueantes.

## Duración estimada
60 minutos

---

## Preparación

```bash
kubectl create namespace net-debug
kubectl apply -f app-rota.yaml
sleep 10
kubectl get all -n net-debug
```

---

## Escenario 1 — Service sin Endpoints (selector incorrecto)

Este es el problema más frecuente en Kubernetes.

```bash
# Intentar acceder al servicio
kubectl run debug --image=busybox:1.36 --rm -it -n net-debug \
  -- sh -c "wget -qO- http://svc-frontend:80 --timeout=3 || echo 'FALLO DE CONEXIÓN'"

# DIAGNÓSTICO — siempre empezar aquí:
kubectl get endpoints svc-frontend -n net-debug
# Si ENDPOINTS muestra <none> → el selector no coincide con ningún pod

# Ver qué labels tienen los pods
kubectl get pods -n net-debug --show-labels

# Ver qué selector tiene el service
kubectl get service svc-frontend -n net-debug -o yaml | grep -A5 selector

# Comparar — ¿coinciden los labels del pod con el selector del service?
```

Corregir el servicio:

```bash
# Parchear el selector para que coincida con los pods reales
kubectl patch service svc-frontend -n net-debug \
  --type=merge \
  -p '{"spec":{"selector":{"app":"frontend"}}}'

# Verificar que ahora hay endpoints
kubectl get endpoints svc-frontend -n net-debug
# Debe mostrar IPs de los pods

# Probar conectividad de nuevo
kubectl run debug --image=busybox:1.36 --rm -it -n net-debug \
  -- sh -c "wget -qO- http://svc-frontend:80 --timeout=5"
```

---

## Escenario 2 — Puerto incorrecto en el Service

```bash
kubectl get endpoints svc-backend -n net-debug
# Tiene endpoints (IPs) pero la conexión falla

kubectl run debug --image=busybox:1.36 --rm -it -n net-debug \
  -- sh -c "wget -qO- http://svc-backend:80 --timeout=3 || echo 'FALLO'"

# DIAGNÓSTICO:
kubectl describe service svc-backend -n net-debug
# Verificar: Port vs TargetPort

# Ver en qué puerto escucha realmente el pod
kubectl describe pod -n net-debug -l app=backend | grep -A5 "Ports:"

# SOLUCIÓN: corregir el targetPort
kubectl patch service svc-backend -n net-debug \
  --type=merge \
  -p '{"spec":{"ports":[{"port":80,"targetPort":8080}]}}'

kubectl run debug --image=busybox:1.36 --rm -it -n net-debug \
  -- sh -c "wget -qO- http://svc-backend:80 --timeout=5"
```

---

## Escenario 3 — Troubleshooting de DNS

```bash
# Verificar que CoreDNS está corriendo
kubectl get pods -n kube-system | grep coredns

# Desde un pod, probar resolución DNS
kubectl run dns-debug --image=busybox:1.36 --rm -it -n net-debug \
  -- sh -c "nslookup svc-frontend && nslookup svc-frontend.net-debug.svc.cluster.local"

# Formato completo del DNS en Kubernetes:
# <service>.<namespace>.svc.<cluster-domain>
# Ejemplo: svc-frontend.net-debug.svc.cluster.local

# Probar DNS de servicios en otro namespace
kubectl run dns-debug --image=busybox:1.36 --rm -it -n net-debug \
  -- sh -c "nslookup kubernetes.default.svc.cluster.local"

# En este k3s el selector de CoreDNS es k8s-app=kube-dns, no app=coredns
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20
```

---

## Escenario 4 — NetworkPolicy bloqueante

Este k3s usa Flannel. Flannel no aplica NetworkPolicies: el objeto se crea, pero el `wget` sigue funcionando. En un clúster con Calico, Cilium u OVN-Kubernetes (OpenShift) la misma política sí corta el tráfico.

```bash
kubectl apply -f networkpolicy-restrictiva.yaml

kubectl get networkpolicies -n net-debug
kubectl describe networkpolicy bloqueo-total -n net-debug
# PodSelector vacío + policyTypes Ingress y Egress, sin reglas = deny all
# en un CNI que las haga cumplir

# En este clúster la conexión sigue viva
kubectl run debug --image=busybox:1.36 --rm -it -n net-debug \
  -- sh -c "wget -qO- http://svc-frontend:80 --timeout=3 || echo 'BLOQUEADO'"

# La política de permiso es la que usarías donde el CNI sí filtra.
# Abre el tráfico dentro de net-debug y el DNS hacia kube-system (UDP/TCP 53).
kubectl apply -f networkpolicy-permitir.yaml
```

---

## Herramientas de debug de red

```bash
# Pod netshoot — la navaja suiza del networking en k8s
kubectl run netshoot --image=nicolaka/netshoot --rm -it -n net-debug \
  -- sh -c "curl -v http://svc-frontend:80; nslookup svc-frontend; ss -tlnp"

# En k3s las reglas las escribe el proceso k3s-agent, no un pod kube-proxy.
# El comentario de la cadena lleva namespace/servicio.
multipass exec k3s-worker -- sudo iptables -t nat -L KUBE-SERVICES | grep net-debug/svc-frontend

# Trazar la ruta de un paquete
kubectl run netshoot --image=nicolaka/netshoot --rm -it -n net-debug \
  -- traceroute svc-frontend
```

---

## Limpieza

```bash
kubectl delete namespace net-debug --ignore-not-found
```

---

## Para llevar a un clúster real

Estos comandos no se ejecutan en las VMs del curso. El orden del diagnóstico de un Service es el mismo: endpoints, labels, puerto, DNS.

**kubeadm.** CoreDNS también suele llevar `k8s-app=kube-dns`. kube-proxy es un DaemonSet y programa iptables o nftables, según cómo se instaló el clúster. Una NetworkPolicy solo corta tráfico si el CNI la implementa (Calico o Cilium; Flannel no).

```bash
kubectl get pods -n kube-system -l k8s-app=kube-proxy
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20
```

**OpenShift.** El DNS vive en `openshift-dns` y el CNI es OVN-Kubernetes, que sí aplica NetworkPolicies. El objeto equivalente al Service se inspecciona con `oc get endpoints` y las políticas con `oc get networkpolicy`.

```bash
oc get pods -n openshift-dns
oc get networkpolicy -n net-debug
oc describe networkpolicy bloqueo-total -n net-debug
```

---

## Preguntas de reflexión para el instructor

1. ¿Cuáles son los 3 pasos para diagnosticar "mi app no llega al servicio"?
2. ¿Qué es un EndpointSlice y en qué se diferencia de los Endpoints clásicos?
3. ¿Cómo debuggearías un problema de DNS en un namespace específico?
4. ¿Por qué una NetworkPolicy de "deny all" puede romper el tráfico hacia el DNS del cluster?
