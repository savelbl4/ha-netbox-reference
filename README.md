# HA NetBox (without Kubernetes)

🇷🇺 **Русская версия:** [README.ru.md](README.ru.md)

> Reference architecture for deploying NetBox in a highly available setup using classic infrastructure components.

---

## What is this project

This repository demonstrates a **production-like HA deployment of NetBox** built without Kubernetes.

The goal of the project is **not** to provide a one-click solution, but to show:
- how NetBox can be made highly available,
- which components are required,
- what operational pitfalls exist in real life.

The project was built and tested as a **real working system**, not a lab-only setup.

---

## Target audience

This project is intended for:
- network engineers using NetBox as a Source of Truth
- infrastructure / DevOps engineers
- SREs working in on‑prem or VM-based environments

You should be comfortable with:
- Linux
- basic PostgreSQL concepts
- networking and HA fundamentals

---

## What this project does

- Deploys NetBox in an HA setup
- Provides PostgreSQL HA using Patroni + etcd
- Uses Redis in HA mode
- Implements load balancing with VIP failover
- Documents real operational issues and recovery scenarios

---

## What this project does NOT do

- ❌ Not a managed service
- ❌ Not “one button deploy”
- ❌ Not Kubernetes-based
- ❌ Not universally applicable to every environment

This repository assumes **operator knowledge and responsibility**.

---

## Architecture overview

High-level components:

- Multiple NetBox instances (web + workers)
- PostgreSQL cluster with automatic failover (Patroni)
- Redis HA
- HAProxy with Virtual IP (Keepalived)
- Ansible for deployment and lifecycle management

> Think of this setup as a **control-plane for NetBox**, similar to HA network services.

```text
<ASCII-scheme>
                    Users / Automation
                  (Engineers, CI/CD, API)
                            |
                            v
                +--------------------------------+
                |        Virtual IP (VIP)        |
                |   HAProxy + Keepalived (HA)    |
                +--------------------------------+
                            |
          -------------------------------------------------
          |                       |                       |
          v                       v                       v
+----------------+     +----------------+     +----------------+
|    NetBox #1   |     |    NetBox #2   |     |    NetBox #3   |
|  Web + Workers |     |  Web + Workers |     |  Web + Workers |
|   (stateless)  |     |   (stateless)  |     |   (stateless)  |
+----------------+     +----------------+     +----------------+
          |                       |                       |
          +-----------+-----------+-----------+-----------+
                      |                       |
                      v                       v
        ======================        ======================
        =  PostgreSQL Cluster =        =     Redis HA     =
        ======================        ======================
        +------------+               +------------+
        | Postgres 1 |<---- Leader   |  Redis 1   |  Master
        +------------+               +------------+
        | Postgres 2 |  Replica      |  Redis 2   |  Replica
        +------------+               +------------+
        | Postgres 3 |  Replica      |  Redis 3   |  Replica
        +------------+               +------------+
               |
            Patroni
               |
              etcd
          (quorum / leader election)

```

---

## Why no Kubernetes?

This is a deliberate design choice.

Reasons:
- full control over components
- predictable failure scenarios
- easier troubleshooting
- better fit for on‑prem / small teams

---

## Automation approach

- Configuration management: **Ansible**
- Clear lifecycle separation:
  - pre-start
  - bootstrap
  - main deployment
- Critical recovery steps are **documented, not hidden**

> Not everything should be automated blindly.

---

## Operational notes

This repository includes:
- known pitfalls (“gotchas”)
- backup vs recovery considerations
- manual recovery procedures
- lessons learned from real failures

These parts are **intentional** and valuable.

---

## Status

- Project state: **reference / showcase**
- Actively used concepts
- No guarantees of backward compatibility

---

## License

MIT
