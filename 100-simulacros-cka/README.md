# Módulo 100 — Simulacros CKA II

## Rol del administrador

Segunda ronda de simulacros. El módulo 99 ya cubrió los retos "clásicos" (pod multi-contenedor, NodePort, Job simple, PVC dinámico, deny-all, drain sin PDB, backup de SQLite…). Aquí **ningún reto repite ejercicio**: se ejercitan temas de los módulos 01–13 que el 99 no tocó (rollbacks a revisión concreta, StatefulSets, sidecars nativos, PDB bloqueando un drain, CSR de usuarios, snapshots de etcd, Gateway API, Kustomize, DNS roto…). Cada reto tiene:
- Un enunciado breve (como en el examen)
- Un tiempo límite
- La solución paso a paso
- Comandos de verificación

Los retos usan sus propios namespaces (`cka2`, `cka2-mid`, `cka2-trouble`…) para no chocar con los del módulo 99.

---

## Formato del examen CKA

- **Duración:** 2 horas
- **Tareas:** 15-20 ejercicios prácticos
- **Entorno:** terminal Linux con kubectl preconfigurado (varios clusters/contextos, acceso `ssh` a los nodos)
- **Nota de aprobado:** 66%
- **Herramientas permitidas:** kubectl, documentación oficial de Kubernetes (kubernetes.io, helm.sh, gateway-api.sigs.k8s.io)

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

### Estrategias nuevas para el examen CKA

1. **El contexto primero, siempre** — cada pregunta indica un contexto; copia y ejecuta el `kubectl config use-context ...` antes de leer el resto
2. **Edita en vivo solo lo mutable** — `kubectl set image/env/resources` y `kubectl patch` son más rápidos que `kubectl edit`; para campos inmutables de un pod usa `kubectl replace --force -f`
3. **Lee los eventos antes que los logs** — `kubectl events` / `kubectl get events --field-selector` te dicen *por qué* algo no arranca; los logs solo sirven si el contenedor llegó a ejecutarse
4. **`kubectl explain --recursive`** te da el árbol completo de campos cuando no recuerdas dónde va algo (`topologySpreadConstraints`, `volumeClaimTemplates`…)
5. **Verifica cada respuesta** con el comando que usaría el corrector (`get -o jsonpath`, `auth can-i`, `rollout history`), no solo con `kubectl apply` sin errores
6. **Marca y sigue** — anota el número de las preguntas dudosas y vuelve al final; las de troubleshooting suelen valer más puntos

### Atajos de kubectl para el examen (nuevos)

```bash
# ~/.vimrc mínimo para editar YAML sin romper la indentación
cat <<'EOF' >> ~/.vimrc
set expandtab tabstop=2 shiftwidth=2 autoindent
EOF

# Contextos
kubectl config get-contexts
kubectl config use-context <contexto>
kubectl config set-context --current --namespace=cka2   # namespace por defecto

# Generar YAML de recursos menos obvios
kubectl create cronjob limpieza --image=busybox:1.36 --schedule="*/5 * * * *" \
  --dry-run=client -o yaml -- sh -c 'date' > cronjob.yaml
kubectl create ingress web --class=traefik --rule="web.local/*=web-svc:80" \
  --dry-run=client -o yaml > ingress.yaml
kubectl create role lector --verb=get,list --resource=pods,pods/log \
  --dry-run=client -o yaml > role.yaml
kubectl create pdb web-pdb --selector=app=web --min-available=2 \
  --dry-run=client -o yaml > pdb.yaml

# Modificar workloads sin abrir el editor
kubectl set image deployment/web nginx=nginx:1.28-alpine
kubectl set env deployment/web MODO=produccion
kubectl set resources deployment/web --requests=cpu=50m,memory=64Mi --limits=memory=128Mi

# Árbol completo de campos
kubectl explain pod.spec.topologySpreadConstraints --recursive
kubectl explain statefulset.spec.volumeClaimTemplates --recursive | head -30

# Eventos filtrados
kubectl get events -n cka2 --field-selector type=Warning --sort-by=.lastTimestamp
kubectl get events -n cka2 --field-selector involvedObject.name=mi-pod
kubectl events -n cka2 --for pod/mi-pod --types=Warning
```

---

## Laboratorios

- [Lab Básico](basico/README.md) — Retos rápidos (5 min cada uno) — Configuración, rollouts, probes, scheduling y cuotas
- [Lab Intermedio](intermedio/README.md) — Retos de dificultad media (10 min) — StatefulSets, Jobs, sidecars, NetworkPolicy, Ingress, Gateway API, PV estáticos y Kustomize
- [Lab Avanzado](avanzado/README.md) — Retos completos estilo examen (15 min) — Troubleshooting, DNS, mantenimiento con PDB, usuarios con CSR y etcd snapshots
