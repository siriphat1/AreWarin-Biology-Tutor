# AreWarin — Course Category Ready System

ชุดนี้เป็น **drop-in upgrade** สำหรับระบบ AreWarin เดิม เพื่อแก้ปัญหา:

- เพิ่มคอร์สใหม่แล้วไม่มีหมวด
- คอร์สถูกแสดงตามหมวดของติวเตอร์ ทำให้คอร์สทั้งหมดของติวเตอร์ถูกเหมารวมอยู่หมวดเดียวกัน
- ต้องการเลือกหมวดเดิมหลายหมวดต่อ 1 คอร์ส
- ต้องการสร้างหมวดใหม่จากหน้า **Manager > เพิ่ม/แก้ไขคอร์ส** ได้ทันที

## สิ่งที่ได้

### Manager
- เลือกหมวดเดิมได้หลายหมวด
- Search หมวด
- สร้างหมวดใหม่โดยไม่ออกจากหน้าเพิ่มคอร์ส
- หมวดใหม่ถูกเลือกให้คอร์สอัตโนมัติ
- Edit คอร์สเดิมแล้วโหลดหมวดเดิมกลับมา
- ถ้าคอร์ส `เปิดใช้งาน` แต่ไม่มีหมวด ระบบจะไม่ให้ submit
- ไม่ต้องแก้ `manager/app.js` เดิม

### หน้าเว็บสมัคร
- หมวดวิชาอิงจาก **course_categories** จริง
- แสดงเฉพาะหมวดที่มีคอร์ส
- จำนวนคอร์สต่อหมวดคำนวณจากคอร์สจริง
- หน้าเลือกติวเตอร์แสดงเฉพาะติวเตอร์ที่มีคอร์สในหมวดนั้น
- หลังเลือกติวเตอร์ แสดงเฉพาะคอร์สของหมวดที่ผู้ใช้เลือก
- ถ้า migration ยังไม่ถูกติดตั้ง จะ fallback กลับระบบเดิมแทนที่จะทำเว็บพัง

## ไฟล์

```text
arewarin-course-category-ready/
├─ install.py
├─ manager/
│  └─ course-category-addon.js
├─ js/
│  └─ course-category-public-addon.js
└─ supabase/
   └─ COURSE_CATEGORY_UPGRADE.sql
```

## ติดตั้ง

### 1) แตก ZIP

สมมติ project เดิม:

```text
arewarin-complete-system/
├─ index.html
├─ manager/
│  ├─ index.html
│  └─ app.js
├─ js/
└─ supabase/
```

### 2) รัน installer

Windows:

```bash
python install.py C:\path\to\arewarin-complete-system
```

macOS / Linux:

```bash
python3 install.py /path/to/arewarin-complete-system
```

Installer จะ:
- copy add-on เข้า project
- patch `manager/index.html`
- patch `index.html`
- backup HTML เดิมเป็น `.bak-course-category`
- ไม่แก้ `manager/app.js` เดิม

### 3) Supabase

เปิด:

**Supabase Dashboard → SQL Editor → New query**

แล้วรันไฟล์:

```text
supabase/COURSE_CATEGORY_UPGRADE.sql
```

SQL จะสร้าง:

```text
course_categories
course_id -> courses.id
category_id -> subject_categories.id
```

และ backfill คอร์สเดิมจาก `tutor.categories` เพื่อไม่ให้รายการเก่าหายทันที

### 4) Refresh

Deploy ขึ้น GitHub/Vercel/Netlify ตามเดิม แล้ว:

```text
Ctrl + F5
```

## Flow ใหม่

```text
Manager > คอร์ส
   ↓
เลือกติวเตอร์
   ↓
เลือกหมวดเดิม 1..N หมวด
   หรือ + สร้างหมวดใหม่
   ↓
กรอกข้อมูลคอร์ส
   ↓
บันทึก
   ↓
courses + course_categories
   ↓
หน้าเว็บสมัคร
   ↓
หมวด → ติวเตอร์ที่มีคอร์สในหมวด → คอร์สในหมวดนั้นเท่านั้น
```

## ข้อควรทราบ

ระบบนี้ออกแบบให้ทำงานกับโครงสร้างเดิมที่มี:

- `courses`
- `tutors`
- `subject_categories`
- `public.is_manager()`
- Supabase Auth/RLS

ถ้าโปรเจกต์ของคุณใช้ชื่อตาราง/คอลัมน์ต่างจากนี้ ให้ปรับ SQL ก่อน Run
