# Módulo 12 — Seguridad de Imágenes, Networking Avanzado y Cifrado

## Rol del administrador

Este módulo cierra tres frentes distintos que todo admin de Kubernetes termina tocando tarde o temprano:
- **Seguridad de la cadena de suministro**: de dónde vienen las imágenes y quién puede jalarlas
- **Networking de nueva generación**: Gateway API, el sucesor declarado de Ingress
- **Protección de datos en reposo**: qué hay realmente dentro de etcd, y cómo se ve "por dentro" el plano de red (CNI, kube-proxy)

---

## Teoría

### Gateway API vs Ingress

Gateway API separa responsabilidades que Ingress mezclaba en un solo objeto:

```
Ingress (todo en un objeto)              Gateway API (roles separados)
┌─────────────────────────┐              ┌──────────────┐      ┌───────────────┐
│ Ingress                 │              │ GatewayClass │──▶   │ Gateway       │
│  - infraestructura       │              │ (el admin de  │      │ (una instancia │
│  - reglas de routing     │   ──────▶    │  la plataforma│      │  de balanceador│
│  - TLS                  │              │  la define)   │      │  concreta)     │
└─────────────────────────┘              └──────────────┘      └───────┬───────┘
                                                                        │
                                                                 ┌──────▼───────┐
                                                                 │  HTTPRoute    │
                                                                 │ (el equipo de │
                                                                 │  la app define│
                                                                 │  sus reglas)  │
                                                                 └──────────────┘
```

Esto permite que la plataforma controle el `Gateway` (TLS, puertos, clase de infraestructura) mientras cada equipo gestiona sus propios `HTTPRoute` sin tocar la infraestructura compartida — algo que Ingress no permitía de forma segura con un solo objeto monolítico.

### Cifrado de Secrets en reposo

Por defecto, los `Secret` de Kubernetes se guardan en etcd **en texto plano**, codificados solo en base64 (que no es cifrado). Cualquiera con acceso al disco de etcd puede leerlos. `EncryptionConfiguration` le dice al API server que cifre ciertos recursos antes de escribirlos a etcd:

```
kubectl create secret ──▶ API server ──▶ [cifrado con la clave de EncryptionConfiguration] ──▶ etcd
```

### CNI y modos de kube-proxy

- **CNI (Container Network Interface)**: el plugin que le da IP a cada pod y conecta esa IP a la red del cluster (Flannel, Calico, Cilium...). k3s usa Flannel por defecto con VXLAN.
- **kube-proxy**: programa las reglas que convierten `ClusterIP` de un Service en conexiones reales a los pods detrás. Dos modos:

| Modo | Cómo funciona | Cuándo se usa |
|------|---------------|---------------|
| `iptables` | Reglas de netfilter, recorridas secuencialmente | Default histórico, se degrada con miles de Services |
| `ipvs` | Tablas hash en el kernel, balanceo O(1) | Clusters grandes, mejor rendimiento |

---

## Laboratorios

- [Lab Básico](basico/README.md) — Image Security: `imagePullSecrets` con un registro privado real
- [Lab Intermedio](intermedio/README.md) — Gateway API: GatewayClass, Gateway y HTTPRoute con Traefik
- [Lab Avanzado](avanzado/README.md) — Cifrado de Secrets en reposo (EncryptionConfiguration) y diagnóstico de CNI/kube-proxy
