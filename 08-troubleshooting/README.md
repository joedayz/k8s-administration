# Módulo 08 — Troubleshooting

## Rol del administrador

El troubleshooting representa el **30% del examen CKA** y es la habilidad más valorada en producción. El admin necesita:
- Diagnosticar y resolver problemas de pods en segundos bajo presión
- Identificar fallos del control plane cuando el cluster no responde
- Debuggear problemas de red entre servicios y namespaces
- Reconstruir un cluster parcialmente roto

---

## Teoría

> 🎨 Versión a color: [teoria.html](teoria.html)

El laboratorio se ejecuta en k3s. Debajo de cada tema está el mismo diagnóstico en kubeadm (Kubernetes vanilla) y en OpenShift. Esos comandos no se corren en las VMs de este curso.

### Metodología de troubleshooting (en orden)

```
¿El problema es de pod, nodo, red o control plane?
        │
        ├── POD: kubectl describe pod → kubectl logs → kubectl exec
        ├── NODO: kubectl describe node → journalctl -u k3s-agent (worker) o -u k3s (server)
        ├── RED: kubectl get endpoints → nslookup desde pod
        └── CONTROL PLANE: systemctl status k3s → journalctl -u k3s
                           los pods de kube-system son solo CoreDNS, Traefik y metrics-server
```

### Los 6 estados problemáticos de un pod

| Estado | Causa más común | Diagnóstico |
|--------|----------------|-------------|
| `Pending` | Sin nodos disponibles, falta de recursos, PVC sin bind | `kubectl describe pod` → Events |
| `ImagePullBackOff` | Imagen no existe, credenciales incorrectas | `kubectl describe pod` → Events |
| `CrashLoopBackOff` | Aplicación falla al arrancar, error de config | `kubectl logs --previous` |
| `OOMKilled` | Supera el límite de memoria (exit code 137) | `kubectl describe pod` → `Last State` |
| `Terminating` (atascado) | Finalizer pendiente, nodo caído | `kubectl patch` para forzar |
| `Error` / `RunContainerError` | Error en entrypoint, permisos | `kubectl describe` + `kubectl logs` |

### Troubleshooting de servicios: el patrón más frecuente

```
Síntoma: "mi app no llega al servicio"
Diagnóstico:
  1. kubectl get endpoints <svc>    → ¿hay IPs? Si no: selector incorrecto
  2. kubectl get pods -l <selector> → ¿los pods están Running?
  3. nslookup <svc>.<ns>.svc.cluster.local → ¿el DNS resuelve?
  4. curl desde otro pod             → ¿el puerto es correcto?
```

### Troubleshooting de nodos

```bash
# Nodo NotReady — siempre empezar aquí:
kubectl describe node <nodo>          # Conditions, Events, Taints

# En este clúster el agente no es la unidad kubelet:
# worker → k3s-agent    server → k3s
journalctl -u k3s-agent -n 50
systemctl status k3s-agent

# Causas comunes:
# - k3s-agent parado
# - Disco lleno (df -h) → DiskPressure=True
# - Certificado caducado (k3s certificate check en el server)
# - El worker no llega al API (https://192.168.252.2:6443)
```

**kubeadm.** La unidad del nodo es `kubelet`. El control plane son static pods en `kube-system` (`kube-apiserver`, `etcd`, `kube-scheduler`, `kube-controller-manager`), con manifiestos en `/etc/kubernetes/manifests/`.

```bash
journalctl -u kubelet -n 50
systemctl status kubelet
kubectl get pods -n kube-system -l tier=control-plane
crictl ps
```

**OpenShift.** `oc get nodes` y `oc describe node`. El kubelet se mira desde el host, con una sesión de debug. El control plane se diagnostica por operadores, no por un `systemctl status` del API:

```bash
oc get clusteroperators
oc get pods -n openshift-kube-apiserver
oc debug node/<nodo>
chroot /host
journalctl -u kubelet -n 50
```

---

## Laboratorios

- [Lab Básico](basico/README.md) — Diagnóstico de pods problemáticos (los 6 estados)
- [Lab Intermedio](intermedio/README.md) — Troubleshooting de servicios y red
- [Lab Avanzado](avanzado/README.md) — Troubleshooting de nodos y control plane
