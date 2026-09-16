# AreWarin Ready Replace v3 — วางทับได้เลย

เวอร์ชันนี้แก้จาก v2 โดย **ฝังช่อง “หมวดที่เปิดสอน” ลงใน `manager/index.html` โดยตรง**
ดังนั้นเมื่อเปิดหน้า Manager > คอร์ส คุณต้องเห็นกรอบหมวดทันที แม้ Supabase ยังโหลดไม่สำเร็จ

## ใช้ไฟล์แค่ 3 ตัว

```text
YOUR-REPO/
├─ index.html                         ← วางทับด้วยไฟล์นี้
├─ manager/
│  ├─ index.html                     ← วางทับด้วยไฟล์นี้
│  ├─ app.js                         ← เก็บไฟล์เดิม
│  └─ v17-control.js                 ← เก็บไฟล์เดิม
└─ supabase/
   └─ COURSE_CATEGORY_UPGRADE.sql     ← Run ใน Supabase SQL Editor 1 ครั้ง
```

## ขั้นตอน

1. เอา `index.html` จาก ZIP ไปวางทับ **index.html ที่ root**
2. เอา `manager/index.html` จาก ZIP ไปวางทับ **manager/index.html**
3. Commit + Push GitHub
4. ไป Supabase > SQL Editor > New Query
5. Copy `COURSE_CATEGORY_UPGRADE.sql` ทั้งไฟล์ แล้ว Run
6. รอ GitHub Pages / Hosting deploy เสร็จ
7. เปิด Manager แล้วกด Ctrl+F5

## สิ่งที่ต้องเห็นใน Manager > คอร์ส

หลังช่อง “ติวเตอร์” จะมีกรอบ:

- หมวดที่เปิดสอน *
- ค้นหาหมวด
- รายการหมวดจาก `subject_categories`
- ปุ่ม `สร้างหมวดใหม่`

ถ้าเห็นกรอบ แต่ขึ้น “โหลดหมวดไม่สำเร็จ”:
แปลว่า HTML ใหม่ทำงานแล้ว แต่ต้องตรวจ Supabase/RLS/SQL ต่อ

ถ้า **ไม่เห็นกรอบหมวดเลย**:
แปลว่า Hosting ยังไม่ได้ใช้ `manager/index.html` ไฟล์ใหม่นี้
ให้ตรวจว่าอัปไฟล์ไว้ที่ `manager/index.html` จริง ไม่ใช่ `manager-index.html` ที่ root

## ตรวจฐานข้อมูล

Run:

```sql
select * from public.course_categories limit 20;
```

ต้องไม่ขึ้น `relation does not exist`

## หมายเหตุ

- ไม่ต้องอัปไฟล์ add-on JavaScript เพิ่ม
- โค้ดหมวดถูกฝังใน HTML แล้ว
- ไม่ต้องแก้ `manager/app.js`
- ระบบเดิมยังคงทำงานต่อ
