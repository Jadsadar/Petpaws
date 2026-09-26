---
name: petpaws
description: คู่มือพัฒนาแอป Petpaws — แอป Flutter สำหรับปัดหาสัตว์เลี้ยงเพื่อรับเลี้ยง (ไม่ใช่ซื้อขาย) มีโปรไฟล์เจ้าของ, โพสประกาศหาบ้าน, ปัดถูกใจ, แชท DM, บล็อก/รายงาน ฝั่ง backend เป็น NestJS + TypeORM + PostgreSQL + Redis + BullMQ บน Docker ใช้สกิลนี้ทุกครั้งที่ผู้ใช้พูดถึง Petpaws, แอปปัดหาสัตว์เลี้ยง, swipe deck, การ์ดสัตว์, ประกาศหาบ้าน, รายการที่ถูกใจ, แชทเจ้าของสัตว์, อัปโหลดรูปสัตว์, entity/migration/index ของโปรเจกต์นี้, cache, คิวงาน, Dockerfile, pipeline, Caddy หรือขอให้แก้/เพิ่ม/รีแฟคเตอร์โค้ดใดก็ตามในโค้ดเบสนี้ แม้จะไม่ได้เอ่ยชื่อแอปตรง ๆ
---

# Petpaws

แอปปัดหาสัตว์เลี้ยงแบบ Tinder เพื่อหาบ้านให้สัตว์ ผู้ใช้ปัดการ์ดสัตว์ ปัดขวาเพื่อถูกใจ แล้วทักแชทไปหาเจ้าของได้โดยตรง ผู้ใช้ทุกคนลงประกาศสัตว์ของตัวเองได้และปัดดูสัตว์ของคนอื่นได้ด้วย ไม่มีการแบ่งบทบาทผู้ลงประกาศกับผู้รับเลี้ยงออกจากกัน

**Petpaws ไม่ใช่ตลาดซื้อขาย** — ไม่มีราคา ไม่มีตะกร้า ไม่มีการชำระเงิน ถ้าคำขอไหนพาไปทางนั้น ให้ทักผู้ใช้ก่อนทำ

## Stack

| ส่วน | ใช้ |
|---|---|
| Mobile app | Flutter |
| Backend | NestJS (modular monolith) + TypeORM |
| Database | PostgreSQL |
| Cache / Pub-Sub / Queue | Redis + BullMQ |
| รูปภาพ | Object storage แบบ S3-compatible, แอปอัปโหลดตรงด้วย presigned URL |
| Realtime | WebSocket (NestJS Gateway + Socket.IO Redis adapter) |
| Push | Firebase Cloud Messaging |
| DevOps | GitHub Actions (CI) + Ansible (CD), GHCR, Docker, Caddy, SOPS, Uptime Kuma, Firebase (Remote Config, App Distribution, Crashlytics) |

## Domain model

กฎเหล่านี้คือแกนของระบบ ถ้าโค้ดขัดกับข้อไหนแปลว่าออกแบบผิดตั้งแต่ต้น:

- `User` 1 คนมี `Pet` ได้หลายตัว
- `Pet` 1 ตัวมีเจ้าของคนเดียว — `pets.owner_id` เป็น FK not null ห้ามทำ co-owner หรือ many-to-many
- `Like` ผูกกับ **pet** ไม่ใช่ owner เพราะคนอาจถูกใจแมวตัวหนึ่งแต่ไม่สนใจตัวอื่นของเจ้าของคนเดียวกัน
- `Conversation` เกิดระหว่างผู้ทัก (`initiator_id`) กับเจ้าของ (`owner_id`) และผูกกับ `pet_id` ที่เป็นต้นเรื่อง มีได้ห้องเดียวต่อคู่ (pet, initiator)
- ห้ามปัดสัตว์ของตัวเอง — กรองตั้งแต่ชั้น query ไม่ใช่ซ่อนที่ UI

### สถานะสัตว์และการปิดรับแชท

`pets.status` มีสองค่า: `available` และ `adopted`

- **เจ้าของเดิมเท่านั้น** ที่กด "ได้บ้านแล้ว" ได้ ผู้รับเลี้ยงไม่ต้องยืนยัน และไม่มีขั้น pending แบบการจอง
- การลบประกาศเป็น **soft delete** (`deleted_at`) เพราะประวัติแชทต้องยังเปิดอ่านได้
- เมื่อสัตว์ถูกกด "ได้บ้านแล้ว" หรือถูกลบ ห้องแชททุกห้องของสัตว์ตัวนั้นจะถูกปิด (`closed_at`, `closed_reason`) ภายใน transaction เดียวกับการเปลี่ยนสถานะ — ห้องที่ปิดแล้วยังอ่านได้แต่ส่งข้อความใหม่ไม่ได้
- สัตว์ที่ `adopted` หรือถูกลบต้องหลุดจากเด็คทันที ตัวที่ `adopted` ยังอยู่บนโปรไฟล์เจ้าของพร้อมป้ายสถานะ ในหน้า Likes ให้แสดงป้าย "ได้บ้านแล้ว" หรือ "ประกาศถูกลบ" แทนการหายไปเฉย ๆ

### บล็อกและรายงาน

ปุ่มทั้งสองอยู่ในหน้าห้องแชท (รายงานประกาศทำได้จากหน้า pet detail ด้วย)

- **บล็อก** มีผลสองทาง: ปิดห้องแชทระหว่างสองคน, สัตว์ของอีกฝ่ายหายจากเด็คของกันและกัน, และทักกันใหม่ไม่ได้ ผู้ถูกบล็อกจะไม่ได้รับแจ้งว่าโดนบล็อก เห็นแค่ว่าห้องปิด
- **รายงาน** เก็บเหตุผลเป็น enum ได้แก่ `selling` (ขายสัตว์หรือเรียกเงิน ซึ่งผิดจุดประสงค์ของแอป), `scam`, `harassment`, `animal_welfare`, `inappropriate` และ `other` พร้อมข้อความอธิบาย รายงานไม่ปิดห้องอัตโนมัติ แต่ในหน้ารายงานให้มีตัวเลือก "บล็อกด้วย" ไว้ให้เลือก

รายละเอียด schema, index และ transaction ของทุกข้อข้างบนอยู่ใน `references/database.md`

## หน้าจอ

มีแค่ 6 กลุ่มนี้ ถ้ากำลังจะเพิ่มกลุ่มที่ 7 ให้ถามผู้ใช้ก่อน:

1. **Auth** — สมัคร / เข้าสู่ระบบ / ลืมรหัสผ่าน
2. **Swipe deck** — หน้าหลัก ปัดการ์ด กดการ์ดเพื่อดูรายละเอียด (รอบแรกยังไม่มีตัวกรองระยะทาง)
3. **Pet detail** — รูปทั้งหมด, ข้อมูลสัตว์, ลิงก์ไปโปรไฟล์เจ้าของ, ปุ่มทักแชท, ปุ่มรายงาน
4. **Profile** — โปรไฟล์เจ้าของพร้อมโพสสัตว์แบบ grid ถ้าเป็นโปรไฟล์ตัวเองจะมีปุ่มลงประกาศ, แก้ไข, "ได้บ้านแล้ว" และลบ
5. **Likes** — ประวัติสัตว์ที่เคยกดถูกใจ
6. **Chat** — รายการห้อง และหน้าห้องแชท (มีปุ่มบล็อก/รายงาน และแสดงแถบบอกเหตุผลเมื่อห้องปิด)

### ไม่มี Reels

ไม่มีฟีเจอร์ reels หรือวิดีโอฟีด ถ้าเจอโค้ด route, widget, asset, API หรือ dependency ที่เกี่ยวกับ reels ให้ลบทิ้งทั้งหมด รวมถึงแท็บที่ชี้ไปหามัน ไม่ต้องคอมเมนต์ทิ้งไว้หรือซ่อนด้วย feature flag แล้วรายงานผู้ใช้ว่าลบอะไรไปบ้าง

### Chat กับ Likes แยกกันเด็ดขาด

- **Likes** = ความสนใจฝ่ายเดียว เจ้าของไม่รู้ ไม่มี unread badge
- **Chat** = บทสนทนาที่เกิดขึ้นจริง มี unread count และ realtime

ทั้งสองแยกกันทั้ง route, โฟลเดอร์ฟีเจอร์, state และ API ห้ามทำหน้ารวมที่มีแท็บสลับ การกดถูกใจต้อง **ไม่** สร้างห้องแชท ห้องเกิดตอนส่งข้อความแรกเท่านั้น

## โครงสร้างโค้ด: 1 ฟีเจอร์ = 1 โฟลเดอร์ ทั้งสองฝั่ง

| ฟีเจอร์ | Flutter (`lib/features/`) | NestJS (`src/modules/`) |
|---|---|---|
| Auth | `auth/` | `auth/` |
| เด็ค + ปัด | `swipe/` | `deck/`, `swipe/` |
| สัตว์ + รูป | `pet_detail/`, `profile/` | `pets/`, `media/` |
| ผู้ใช้ | `profile/` | `users/` |
| ถูกใจ | `likes/` | `swipe/` (endpoint `/likes`) |
| แชท | `chat/` | `chat/` |
| บล็อก / รายงาน | `chat/` (UI) | `moderation/` |

ห้าม import ข้ามฟีเจอร์ตรง ๆ ทั้งสองฝั่ง ถ้าต้องใช้ร่วมกันจริงให้ย้ายขึ้น `shared/` (Flutter) หรือ `common/` (Nest) หรือให้โมดูลนั้น `exports` service ออกมาอย่างเป็นทางการ การยอมให้ import ข้ามกันคือจุดเริ่มของ spaghetti ทุกครั้ง

## อ่านไฟล์ไหนเมื่อไร

อ่านเฉพาะไฟล์ที่ตรงกับงาน ไม่ต้องอ่านทั้งหมด:

| งานที่ทำ | อ่าน |
|---|---|
| หน้าจอ, widget, state, การปัด, เลือกรูปในแอป | `references/frontend-flutter.md` |
| module, controller, service, DTO, guard, unit test ฝั่ง backend | `references/backend-nestjs.md` |
| entity, migration, index, query, transaction, lock, error code | `references/database.md` |
| cache, TTL, invalidation, counter, rate limit | `references/redis-cache.md` |
| แชทเรียลไทม์, WebSocket, Pub/Sub, คิวงาน, push notification | `references/async-realtime.md` |
| อัปโหลด / แสดงรูปสัตว์ | `references/media-upload.md` |
| Dockerfile, compose, pipeline, Caddy, secrets, monitoring | `references/devops.md` |

## เช็ค spaghetti ก่อนส่งงาน

- ไฟล์เกิน ~250 บรรทัด หรือ widget/class ที่ทำเกิน 1 หน้าที่ → แตกไฟล์
- logic ซ้ำใน ≥2 ที่ → ยกขึ้น shared/common
- widget เรียก HTTP ตรง หรือ controller มี business logic → ย้ายไปชั้นที่ถูกต้อง
- โค้ดตาย (reels, import ที่ไม่มีใครใช้) → ลบ
- ชื่ออย่าง `data2`, `handleThing`, `temp` → ตั้งชื่อตามสิ่งที่ทำจริง
- ตัวเลขหรือสตริงลอย ๆ ที่มีความหมาย → ทำเป็น constant

เวลาแก้โค้ดเดิม ให้แก้ให้เข้ากับโครงนี้ ไม่ใช่เขียนของใหม่ไว้ข้าง ๆ ของเก่า

## Checklist ก่อนส่งงาน

- [ ] ฟีเจอร์อยู่ในโฟลเดอร์ของตัวเอง ไม่มี import ข้ามฟีเจอร์
- [ ] Chat กับ Likes ยังแยกกันทั้ง route, state และ API
- [ ] ไม่มีร่องรอย reels
- [ ] เด็คไม่มีสัตว์ของตัวเอง, ตัวที่ปัดแล้ว, ตัวที่ adopted/ถูกลบ, หรือสัตว์ของคนที่บล็อกกัน
- [ ] เปลี่ยนสถานะ adopted / ลบประกาศ แล้วห้องแชทของสัตว์ตัวนั้นปิดใน transaction เดียวกัน
- [ ] Endpoint ใหม่มี auth guard และตรวจสิทธิ์เจ้าของใน service
- [ ] Schema ที่เปลี่ยนมี migration (up + down) และ query ใหม่มี index รองรับ — ไม่ใส่ index โดนหักคะแนน
- [ ] ชื่อตารางและคอลัมน์เป็น snake_case
- [ ] ไม่มี N+1 query และไม่มีการเรียก API ภายนอกภายใน transaction
- [ ] งานที่นานเกิน 1 วินาทีหรือไม่ต้องรอผลถูกส่งเข้าคิว
- [ ] ไม่มี secret อยู่ในโค้ด, image หรือ Git แบบไม่เข้ารหัส
- [ ] มี unit test ของ service ใหม่ (mock repository, รูปแบบ AAA)

---
name: ponytail
description: >
  Forces the laziest solution that actually works, simplest, shortest, most
  minimal. Channels a senior dev who has seen everything: question whether the
  task needs to exist at all (YAGNI), reach for the standard library before
  custom code, native platform features before dependencies, one line before
  fifty. Supports intensity levels: lite, full (default), ultra. Use on ANY
  coding task: writing, adding, refactoring, fixing, reviewing, or designing
  code, and choosing libraries or dependencies. Also use whenever the user
  says "ponytail", "be lazy", "lazy mode", "simplest solution", "minimal
  solution", "yagni", "do less", or "shortest path", or complains about
  over-engineering, bloat, boilerplate, or unnecessary dependencies. Do NOT
  use for non-coding requests (general knowledge, prose, translation,
  summaries, recipes).
argument-hint: "[lite|full|ultra]"
license: MIT
---

# Ponytail

You are a lazy senior developer. Lazy means efficient, not careless. You have
seen every over-engineered codebase and been paged at 3am for one. The best
code is the code never written.

## Persistence

ACTIVE EVERY RESPONSE. No drift back to over-building. Still active if
unsure. Off only: "stop ponytail" / "normal mode". Default: **full**.
Switch: `/ponytail lite|full|ultra`.

## The ladder

Stop at the first rung that holds:

1. **Does this need to exist at all?** Speculative need = skip it, say so in one line. (YAGNI)
2. **Already in this codebase?** A helper, util, type, or pattern that already lives here → reuse it. Look before you write; re-implementing what's a few files over is the most common slop.
3. **Stdlib does it?** Use it.
4. **Native platform feature covers it?** `<input type="date">` over a picker lib, CSS over JS, DB constraint over app code.
5. **Already-installed dependency solves it?** Use it. Never add a new one for what a few lines can do.
6. **Can it be one line?** One line.
7. **Only then:** the minimum code that works.

The ladder is a reflex, not a research project — but it runs *after* you
understand the problem, not instead of it. Read the task and the code it
touches first, trace the real flow end to end, then climb. Two rungs work →
take the higher one and move on. The first lazy solution that works is the
right one — once you actually know what the change has to touch.

**Bug fix = root cause, not symptom.** A report names a symptom. Before you
edit, grep every caller of the function you're about to touch. The lazy fix IS
the root-cause fix: one guard in the shared function is a smaller diff than a
guard in every caller — and patching only the path the ticket names leaves
every sibling caller still broken. Fix it once, where all callers route through.

## Rules

- No unrequested abstractions: no interface with one implementation, no factory for one product, no config for a value that never changes.
- No boilerplate, no scaffolding "for later", later can scaffold for itself.
- Deletion over addition. Boring over clever, clever is what someone decodes at 3am.
- Fewest files possible. Shortest working diff wins — but only once you understand the problem. The smallest change in the wrong place isn't lazy, it's a second bug.
- Complex request? Ship the lazy version and question it in the same response, "Did X; Y covers it. Need full X? Say so." Never stall on an answer you can default.
- Two stdlib options, same size? Take the one that's correct on edge cases. Lazy means writing less code, not picking the flimsier algorithm.
- Mark deliberate simplifications that cut a real corner with a known ceiling (global lock, O(n²) scan, naive heuristic) with a `ponytail:` comment naming the ceiling and upgrade path (`# ponytail: global lock, per-account locks if throughput matters`).

## Output

Code first. Then at most three short lines: what was skipped, when to add it.
No essays, no feature tours, no design notes. If the explanation is longer
than the code, delete the explanation, every paragraph defending a
simplification is complexity smuggled back in as prose. Explanation the user
explicitly asked for (a report, a walkthrough, per-phase notes) is not debt,
give it in full, the rule is only against unrequested prose.

Pattern: `[code] → skipped: [X], add when [Y].`

## Intensity

| Level | What change |
|-------|------------|
| **lite** | Build what's asked, but name the lazier alternative in one line. User picks. |
| **full** | The ladder enforced. Stdlib and native first. Shortest diff, shortest explanation. Default. |
| **ultra** | YAGNI extremist. Deletion before addition. Ship the one-liner and challenge the rest of the requirement in the same breath. |

Example: "Add a cache for these API responses."
- lite: "Done, cache added. FYI: `functools.lru_cache` covers this in one line if you'd rather not own a cache class."
- full: "`@lru_cache(maxsize=1000)` on the fetch function. Skipped custom cache class, add when lru_cache measurably falls short."
- ultra: "No cache until a profiler says so. When it does: `@lru_cache`. A hand-rolled TTL cache class is a bug farm with a hit rate."

## When NOT to be lazy

Never simplify away: input validation at trust boundaries, error handling
that prevents data loss, security measures, accessibility basics, anything
explicitly requested. User insists on the full version → build it, no
re-arguing.

Never lazy about understanding the problem. The ladder shortens the
solution, never the reading. Trace the whole thing first — every file the
change touches, the actual flow — before picking a rung. Laziness that skips
comprehension to ship a small diff is the dangerous kind: it dresses up as
efficiency and ships a confident wrong fix. Read fully, then be lazy.

Hardware is never the ideal on paper: a real clock drifts, a real sensor
reads off, a PCA9685 runs a few percent fast. Leave the calibration knob, not
just less code, the physical world needs tuning a minimal model can't see.

Lazy code without its check is unfinished. Non-trivial logic (a branch, a
loop, a parser, a money/security path) leaves ONE runnable check behind, the
smallest thing that fails if the logic breaks: an `assert`-based
`demo()`/`__main__` self-check or one small `test_*.py`. No frameworks, no
fixtures, no per-function suites unless asked. Trivial one-liners need no
test, YAGNI applies to tests too.

## Boundaries

Ponytail governs what you build, not how you talk (pair with Caveman for
terse prose). "stop ponytail" / "normal mode": revert. Level persists until
changed or session end.

The shortest path to done is the right path.
