# Lab 01 — Avanzado: Diagnóstico del control plane y auditoría

## Objetivo
Diagnosticar el estado del control plane, inspeccionar eventos del cluster y configurar un alias profesional de kubectl para operación diaria eficiente.

## Duración estimada
60 minutos

---

## Paso 1 — Diagnóstico profundo del cluster

```bash
# Ver la versión completa del cluster y del cliente
kubectl version

# Ver información del cluster (API server, CoreDNS, etc.)
kubectl cluster-info

# Dump completo del estado del cluster (útil para soporte)
kubectl cluster-info dump --output-directory=/tmp/cluster-dump
ls /tmp/cluster-dump/
```

---

## Paso 2 — Inspeccionar componentes del control plane en k3s

En k3s, el control plane corre como proceso del sistema, no como pods.

```bash
# Ver el estado del servicio k3s
sudo systemctl status k3s

# Ver logs del control plane en tiempo real
sudo journalctl -u k3s -f

# Ver últimas 100 líneas de logs
sudo journalctl -u k3s --no-pager -n 100

# Buscar errores específicos en los logs
sudo journalctl -u k3s --no-pager | grep -i error
sudo journalctl -u k3s --no-pager | grep -i "failed"
```

---

## Paso 3 — Trabajar con eventos del cluster

Los eventos son la primera fuente de diagnóstico cuando algo falla.

```bash
# Ver todos los eventos del cluster ordenados por tiempo
kubectl get events -A --sort-by='.lastTimestamp'

# Ver solo eventos de tipo Warning
kubectl get events -A --field-selector type=Warning

# Ver eventos de un namespace específico
kubectl get events -n kube-system --sort-by='.lastTimestamp'

# Aplicar un pod con error deliberado para ver el evento
kubectl apply -f pod-con-error.yaml

# Observar los eventos del pod fallido
kubectl get events --field-selector involvedObject.name=pod-con-error
kubectl describe pod pod-con-error

# Limpiar
kubectl delete pod pod-con-error
```

---

## Paso 4 — Configurar kubectl para operación eficiente

Un admin pasa muchas horas con kubectl. Configurarlo bien ahorra tiempo y evita errores.

```bash
# Configurar autocompletado (agregar a ~/.bashrc o ~/.zshrc)
echo 'source <(kubectl completion bash)' >> ~/.bashrc
# o para zsh:
echo 'source <(kubectl completion zsh)' >> ~/.zshrc

# Alias esenciales para admins
cat >> ~/.bashrc << 'EOF'
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods -A'
alias kgn='kubectl get nodes'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias kaf='kubectl apply -f'
alias kdf='kubectl delete -f'
alias kns='kubectl config set-context --current --namespace'
EOF

source ~/.bashrc

# Ver el contexto actual
kubectl config current-context

# Ver todos los contextos disponibles
kubectl config get-contexts

# Cambiar de namespace sin escribirlo en cada comando
kubectl config set-context --current --namespace=produccion
kubectl get pods  # ahora muestra pods de produccion por defecto

# Volver al namespace default
kubectl config set-context --current --namespace=default
```

---

## Paso 5 — Inspeccionar etcd (base de datos del cluster)

En k3s, etcd es reemplazado por SQLite por defecto (en single-node) o etcd embebido en HA.

```bash
# Ver dónde están los datos de k3s
sudo ls -la /var/lib/rancher/k3s/server/

# El archivo db/state.db es la base de datos SQLite
sudo ls -la /var/lib/rancher/k3s/server/db/

# Ver cuántos objetos hay en el cluster
kubectl get all -A | wc -l

# Ver el número de objetos por tipo
kubectl api-resources --verbs=list --namespaced -o name | \
  xargs -I{} kubectl get {} -A --ignore-not-found 2>/dev/null | \
  grep -v "^NAME" | wc -l
```

---

## Verificación

```bash
# Estado general del cluster — el "health check" del admin
kubectl get nodes
kubectl get pods -A | grep -v Running | grep -v Completed
kubectl get events -A --field-selector type=Warning | tail -20
```

Si el segundo comando no devuelve nada, todos los pods están saludables.

---

## Preguntas de reflexión para el instructor

1. ¿Por qué en k3s el control plane está en `journalctl` y no en pods como en vanilla k8s?
2. ¿Cuál es la diferencia entre un evento `Warning` y uno `Normal`?
3. ¿Qué información crítica te da `kubectl describe node` que `kubectl get node` no muestra?
4. ¿Por qué es importante tener aliases y autocompletado configurados en producción?
