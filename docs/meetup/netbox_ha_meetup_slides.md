---
marp: true
theme: default
paginate: true
title: HA NetBox для сетевой инфраструктуры
author: Сергей Савелов
---

# HA NetBox для сетевой инфраструктуры

**NetBox без SPOF (Single Point Of Failure)
классическая HA архитектура**

Сергей Савелов
LiveOps / Infrastructure

---

# Почему вообще об этом говорить

NetBox часто становится:

- Source of Truth
- IPAM
- база для автоматизации
- зависимость для CI/CD

Если NetBox падает:

- нельзя выделять IP
- автоматизация ломается
- часть процессов возвращается в Excel

---

# Типичная установка NetBox

<div class="wrap">

<div class="text">

Обычно всё выглядит так:

NetBox
PostgreSQL
Redis

Часто это **одна VM или сервер**.
Это означает один SPOF.

</div>

<div class="image">

![width:100%](01_netbox_default_architecture.svg)

</div>

</div>

<style scoped>
.wrap {
  position: relative;
  height: 100%;
}

/* текст поверх */
.text {
  position: absolute;
  left: 0;
  top: 25%;
  transform: translateY(-50%);
  width: 45%;
  padding: 20px;
  border-radius: 10px;
  z-index: 10;
}

/* картинка */
.image {
  position: absolute;
  right: -10%;
  top: 5%;
  width: 60%;
  height: 150%;
}
</style>

---

# Что происходит при проблемах

Типичные события:

- перезагрузка сервера
- обновление системы
- обслуживание гипервизора
- отказ диска
- падение VM

В этот момент **NetBox полностью недоступен**.

> часть инфраструктуры перестаёт работать.

---

# Требование бизнеса

NetBox — control plane инфраструктуры

Если он недоступен:
- ломается автоматизация
- CI/CD теряет доступ к данным

> NetBox должен переживать типовые отказы без остановки сервиса

---

# Разбираем NetBox

NetBox состоит из:

- Web UI
- background workers
- PostgreSQL
- Redis

Поэтому отказоустойчивость нужно обеспечить на нескольких уровнях.

---

# Возможные подходы

1. Kubernetes — сложность
2. Managed сервисы — не всегда доступны
3. Классический HA — простой и понятный

Мы выбрали **классический HA**.

---

# Основная идея

Что нужно обеспечить:

- несколько NetBox
- HA для базы
- HA для Redis
- единая точка доступа

---

# Архитектура решения

![bg 97%](02_netbox-ha-main-architecture.svg)

<style scoped>
section h1 {
  position: absolute !important;
  top: 20px !important;
}
</style>

---

# Основные компоненты

**PostgreSQL**
_→ Patroni_

**Redis**
_→ replication / sentinel_

**Балансировка**
_→ HAProxy + Keepalived_

**NetBox**
_→ несколько инстансов_

**Connection pooling**
_→ PgBouncer_

---

# Что происходит при падении

**NetBox**
_Если падает активная нода NetBox — VIP просто переезжает._

**PostgreSQL**
_Если падает leader — Patroni выбирает нового, HAProxy начинает слать трафик туда._

**Redis**
_Redis переключается на master через health checks._

**Нода целиком**
_Если падает вся VM — VIP переезжает, сервис продолжает работать._

---

# NetBox

<div class="wrap">

<div class="text">

1. На активной ноде падает Angie или NetBox
1. Keepalived снижает приоритет
1. VIP переезжает


</div>

<div class="image">

![width:100%](03_netbox-netbox-failover.svg)

</div>

</div>

<style scoped>
.wrap {
  position: relative;
  height: 100%;
}

/* текст поверх */
.text {
  position: absolute;
  left: 0;
  top: 25%;
  transform: translateY(-50%);
  width: 50%;
  padding: 20px;
  border-radius: 10px;
  z-index: 10;
}

/* картинка */
.image {
  position: absolute;
  right: -10%;
  top: -10%;
  width: 65%;
  height: 100%;
}
</style>

---

# PostgreSQL

<div class="wrap">

<div class="text">

1. отключаем одну ноду PostgreSQL
1. Patroni выбирает нового лидера
1. HAProxy начинает слать трафик туда

</div>

<div class="image">

![width:100%](04_netbox-postgres-failover.svg)

</div>

</div>

<style scoped>
.wrap {
  position: relative;
  height: 100%;
}

/* текст поверх */
.text {
  position: absolute;
  left: 0;
  top: 25%;
  transform: translateY(-50%);
  width: 45%;
  padding: 20px;
  border-radius: 10px;
  z-index: 10;
}

/* картинка */
.image {
  position: absolute;
  right: -5%;
  top: -10%;
  width: 60%;
  height: 100%;
}
</style>

---

# Redis

<div class="wrap">

<div class="text">

1. Падает Redis master  
1. Sentinel обнаруживает сбой  
1. Выбирается новый master  
1. HAProxy начинает слать трафик на него  

</div>

<div class="image">

![width:100%](05_netbox-redis-failover.svg)

</div>

</div>

<style scoped>
.wrap {
  position: relative;
  height: 100%;
}

/* текст поверх */
.text {
  position: absolute;
  left: 0;
  top: 25%;
  transform: translateY(-50%);
  width: 45%;
  padding: 20px;
  border-radius: 10px;
  z-index: 10;
}

/* картинка */
.image {
  position: absolute;
  right: -5%;
  top: -10%;
  width: 60%;
  height: 100%;
}
</style>

---

# Инфраструктура

<div class="wrap">

<div class="text">

1. Падает целая VM / сервер  
2. Keepalived теряет heartbeat  
3. VIP переносится на другую ноду  
4. Сервисы продолжают работать   

</div>

<div class="image">

![width:100%](06_netbox-node-failover.svg)

</div>

</div>

<style scoped>
.wrap {
  position: relative;
  height: 100%;
}

/* текст поверх */
.text {
  position: absolute;
  left: 0;
  top: 25%;
  transform: translateY(-50%);
  width: 45%;
  padding: 20px;
  border-radius: 10px;
  z-index: 10;
}

/* картинка */
.image {
  position: absolute;
  right: -5%;
  top: -10%;
  width: 60%;
  height: 100%;
}
</style>

---

# Что важно в эксплуатации

<div class="wrap">

<div class="text">

Нужно мониторить:

- доступность NetBox
- статус лидера PostgreSQL
- состояние Redis
- backup
- процедуры восстановления

Также важно иметь:

- схему архитектуры
- инструкции восстановления 

</div>

<div class="image">

![width:100%](grafana.png)

</div>

</div>

<style scoped>
.wrap {
  position: relative;
  height: 100%;
}

/* текст поверх */
.text {
  position: absolute;
  left: 0;
  top: 40%;
  transform: translateY(-50%);
  width: 45%;
  padding: 20px;
  border-radius: 10px;
  z-index: 10;
}

/* картинка */
.image {
  position: absolute;
  right: -5%;
  top: -5%;
  width: 70%;
  height: 100%;
}
</style>

---

# Итоги

NetBox — критическая система инфраструктуры.

HA:

- уменьшает риск недоступности
- делает систему сложнее
- требует понимания архитектуры

Но для production это оправдано.

---

# Спасибо

Вопросы?
