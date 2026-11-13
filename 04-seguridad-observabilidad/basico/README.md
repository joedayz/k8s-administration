# Lab 04 — Básico: RBAC — Usuarios, Roles y Permisos

## Objetivo
Crear roles con permisos mínimos, asignarlos a usuarios y ServiceAccounts, y verificar que los permisos funcionan correctamente.

## Duración estimada
50 minutos

---

## Paso 1 — Crear un ServiceAccount para una aplicación

Las aplicaciones dentro del cluster usan ServiceAccounts para autenticarse con la API.

```bash
kubectl apply -f serviceaccount.yaml

# Verificar
kubectl get serviceaccount -n produccion
kubectl describe serviceaccount app-reader -n produccion
```

---

## Paso 2 — Crear Roles con permisos mínimos

```bash
kubectl apply -f roles.yaml

# Ver los roles creados
kubectl get roles -n produccion
kubectl describe role lector-pods -n produccion
kubectl describe role gestor-deployments -n produccion
```

---

## Paso 3 — Asignar roles (RoleBinding)

```bash
kubectl apply -f rolebindings.yaml

# Ver las asignaciones
kubectl get rolebindings -n produccion
kubectl describe rolebinding app-reader-binding -n produccion
```

---

## Paso 4 — Verificar permisos con `auth can-i`

Esta es la herramienta más útil del admin para auditar permisos:

```bash
# ¿Puede el ServiceAccount app-reader listar pods?
kubectl auth can-i list pods \
  --namespace produccion \
  --as system:serviceaccount:produccion:app-reader

# ¿Puede eliminar pods?
kubectl auth can-i delete pods \
  --namespace produccion \
  --as system:serviceaccount:produccion:app-reader

# ¿Puede listar pods en otro namespace?
kubectl auth can-i list pods \
  --namespace desarrollo \
  --as system:serviceaccount:produccion:app-reader

# Ver todos los permisos de un ServiceAccount
kubectl auth can-i --list \
  --namespace produccion \
  --as system:serviceaccount:produccion:app-reader
```

---

## Paso 5 — Crear un usuario con certificado (simulación)

```bash
# Generar clave privada y CSR para el usuario "juan"
openssl genrsa -out juan.key 2048
openssl req -new -key juan.key -out juan.csr -subj "/CN=juan/O=equipo-dev"

# Codificar el CSR en base64
CSR_B64=$(cat juan.csr | base64 | tr -d '\n')

# Crear el CertificateSigningRequest en Kubernetes
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: juan
spec:
  request: $CSR_B64
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
    - client auth
EOF

# Aprobar el CSR como admin
kubectl certificate approve juan

# Obtener el certificado firmado
kubectl get csr juan -o jsonpath='{.status.certificate}' | base64 -d > juan.crt

# Crear kubeconfig para juan
kubectl config set-credentials juan --client-key=juan.key --client-certificate=juan.crt --embed-certs=true
kubectl config set-context juan-context --cluster=default --user=juan
```

### Paso 6 — Asignar rol al usuario juan y verificar

```bash
# El rol "lector-pods" se creó en el namespace "produccion" (Paso 2).
# Como un Role es un recurso namespaced, hay que crearlo también en "desarrollo"
# para poder asignarlo ahí con un RoleBinding.
kubectl create role lector-pods \
  --verb=get,list,watch \
  --resource=pods,pods/log,pods/status \
  --namespace=desarrollo

# Asignar rol de solo lectura en desarrollo
kubectl create rolebinding juan-reader \
  --role=lector-pods \
  --user=juan \
  --namespace=desarrollo

# Verificar qué puede hacer juan
kubectl auth can-i list pods --namespace desarrollo --as juan
kubectl auth can-i delete pods --namespace desarrollo --as juan
kubectl auth can-i list nodes --as juan

# Limpiar archivos temporales
rm juan.key juan.crt juan.csr
```

---

## Verificación

```bash
# Ver todos los RoleBindings del cluster
kubectl get rolebindings -A
kubectl get clusterrolebindings | grep -v system
```

---

## Limpieza

Estos recursos son exclusivos de este lab: ningún nivel intermedio o avanzado de este módulo los reutiliza.

```bash
# RoleBindings y ClusterRoleBinding
kubectl delete rolebinding app-reader-binding deployment-manager-binding -n produccion
kubectl delete rolebinding juan-reader -n desarrollo
kubectl delete clusterrolebinding admins-junior-reader

# Roles y ClusterRole
kubectl delete role lector-pods gestor-deployments -n produccion
kubectl delete role lector-pods -n desarrollo
kubectl delete clusterrole lector-cluster

# ServiceAccounts
kubectl delete serviceaccount app-reader deployment-manager -n produccion

# CertificateSigningRequest de juan
kubectl delete csr juan

# Contexto y credenciales locales de juan en el kubeconfig
kubectl config delete-context juan-context
kubectl config unset users.juan
```

---

## Preguntas de reflexión para el instructor

1. ¿Por qué usamos ServiceAccounts en lugar de usuarios para las aplicaciones?
2. ¿Cuál es el principio de mínimo privilegio y por qué importa en Kubernetes?
3. ¿Qué ClusterRoles vienen por defecto en Kubernetes y para qué sirven?
4. ¿Cómo auditarías qué permisos tiene un usuario que está dando problemas?
