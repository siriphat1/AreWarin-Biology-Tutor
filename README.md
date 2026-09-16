# AreWarin Ready Replace v5 — Recovery

เวอร์ชันนี้แก้ปัญหาจาก Console ที่พบจริง:

1. `course_package_rules 404`
   - เกิดจากยังไม่มี table ใน Supabase
   - v5 จะไม่ query table นี้จนกว่า SQL migration จะติดตั้งสำเร็จ
   - จึงไม่ทำให้ Console ยิง 404 ซ้ำ

2. หน้าเลือกหมวดขึ้น `ยังไม่พบหมวดวิชา`
   - สาเหตุคือ `course_categories` มี table แล้ว แต่บาง/ทั้งหมดของคอร์สยังไม่มี mapping
   - v5 จะ fallback ไปใช้ `tutor.categories` สำหรับคอร์สที่ยังไม่ได้ map
   - จึงไม่ทำให้หน้าสมัครว่างทั้งหน้าอีก

3. `escapeHTML is not defined`
   - แก้ compatibility helper ให้ Policy CMS แล้ว

## วางไฟล์

```text
YOUR-REPO/
├─ index.html                 <- ใช้ index.html จากชุด v5
└─ manager/
   └─ index.html              <- ใช้ manager/index.html จากชุด v5
```

เก็บไฟล์เดิม:
- manager/app.js
- manager/v17-control.js
- config.js
- js/supabase-bridge.js

## Supabase

เปิด Supabase > SQL Editor > New Query
แล้ว Run ทั้งไฟล์:

```text
supabase/AREWARIN_V5_RECOVERY.sql
```

จากนั้นตรวจ:

```sql
select key,value
from public.app_settings
where key in ('COURSE_RULES_READY','COURSE_CATEGORY_RELATION_READY');

select count(*) from public.course_categories;
```

`COURSE_RULES_READY` ต้องเป็น `true`

## หลัง Deploy

1. Commit + Push
2. รอ GitHub Pages deploy
3. Ctrl + F5
4. หน้าเลือกหมวดต้องกลับมาแสดง
5. Manager > คอร์ส จะกรองตามติวเตอร์ และตั้งแพ็กเกจ/ราคาเฉพาะคอร์สได้

## Tailwind warning

ข้อความ:

`cdn.tailwindcss.com should not be used in production`

เป็น Warning ไม่ใช่สาเหตุที่หมวดหาย และไม่ทำให้ระบบหยุดทำงาน
