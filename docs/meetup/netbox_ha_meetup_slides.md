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

Обычно всё выглядит так:

NetBox
PostgreSQL
Redis

Часто это **одна VM или сервер**.
Это означает один SPOF.

![bg fit](1)
![bg 90%](netbox_ha_default_architecture.svg)

---

# Что происходит при проблемах

Типичные события:

- перезагрузка сервера
- обновление системы
- обслуживание гипервизора
- отказ диска
- падение VM

В этот момент **NetBox полностью недоступен**.

> Если NetBox падает — часть инфраструктуры перестаёт работать.

---

# Требование бизнеса

NetBox — control plane инфраструктуры

Если он недоступен:
- ломается автоматизация
- CI/CD теряет доступ к данным

> Основная цель:
> Переживать типовые отказы без остановки сервиса

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

![bg 97%](netbox-ha-main-architecture.svg)

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

**NetBox node down**
_→ HAProxy переключает трафик_

**PostgreSQL leader down**
_→ Patroni выбирает нового_

**Server down**
_→ VIP переезжает_

---

# Какие отказы мы тестировали

PostgreSQL
Redis
NetBox
Инфраструктура

---

# PostgreSQL

<div class="wrap">

<div class="text">

Проверяли поведение системы в реальных сценариях:

1. отключаем одну ноду PostgreSQL  
2. Patroni выбирает нового лидера  
3. NetBox продолжает работать  

> Пользователь почти не замечает переключение.

</div>

<div class="image">

![width:100%](netbox-postgres-failover2.svg)

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
  top: 35%;
  transform: translateY(-50%);
  width: 50%;
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

# NetBox

- остановка одного инстанса
- перезапуск сервиса
- отключение VM

→ HAProxy переключает трафик
→ пользователи не замечают

---

# Redis

- падение master
- перезапуск ноды

→ Sentinel выбирает нового master
→ очередь и кэш продолжают работать

---

# Инфраструктура

- перезагрузка сервера
- недоступность одной VM

→ сервис остаётся доступным через VIP

---

## Итог

> В типовых сценариях отказа сервис остаётся доступным
---

# Что важно в эксплуатации

Нужно мониторить:

- доступность NetBox
- статус лидера PostgreSQL
- состояние Redis
- мониторинг
- backup
- процедуры восстановления

Также важно иметь:

- схему архитектуры
- инструкции восстановления

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
