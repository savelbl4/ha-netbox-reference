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
![bg 90%](netbox_default_architecture.svg)

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

Формулировка на простом уровне:

> NetBox не должен переставать работать, если падает один сервер.

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

PostgreSQL  
→ Patroni

Redis  
→ replication / sentinel

Балансировка  
→ HAProxy + Keepalived

NetBox  
→ несколько инстансов

Connection pooling
→ PgBouncer

---

# Что происходит при падении

NetBox node down
→ HAProxy переключает трафик

PostgreSQL leader down
→ Patroni выбирает нового

Server down
→ VIP переезжает

---

# Проверка отказоустойчивости

Пример сценария:

1. отключаем одну ноду PostgreSQL
2. Patroni выбирает нового лидера
3. NetBox продолжает работать

Пользователь почти не замечает переключение.

---

# Сбой PostgreSQL Leader

![bg 85%](netbox-postgres-failover2.svg)

<style scoped>
section h1 {
  position: absolute !important;
  top: 20px !important;
}
</style>

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
