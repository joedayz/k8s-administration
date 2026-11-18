# Lab 10 — Básico: Retos Rápidos (Workloads y Services)

## Objetivo
Resolver ejercicios cortos con límite de tiempo, estilo examen CKA. Cada reto dura ~5 minutos.

## Duración estimada
60 minutos (10 retos × 5 min + revisión)

---

## Reto 1 — Crear un Pod con un comando específico (2 min)

> Crea un pod llamado `multi-contenedor` en el namespace `cka` con dos contenedores:
> - `nginx` con imagen `nginx:alpine`
> - `sidecar` con imagen `busybox:1.36` que ejecute `sleep 3600`