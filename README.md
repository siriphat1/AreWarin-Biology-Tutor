# AreWarin Biology — Complete GitHub + Supabase System

ชุดนี้คือเวอร์ชันรวมระบบที่พัฒนามาทั้งหมดสำหรับเว็บสมัครเรียน AreWarin Biology โดยใช้ GitHub/Static Hosting + Supabase แทน Google Sheets / Google Drive / Apps Script และไม่มีระบบส่งอีเมลอัตโนมัติ

## ระบบที่รวมมาแล้ว

### เว็บสมัครเรียน `index.html`
- ข้อตกลงและนโยบาย
- เลือกประเภทนักเรียนใหม่ / นักเรียนเดิม
- เลือกรูปแบบเรียนเดี่ยว / กลุ่ม
- หมวดวิชาแบบเปิด/ปิดจาก Manager
- เลือกติวเตอร์ + Profile
- เลือกคอร์ส + Course Detail + Learning Outcomes + Syllabus
- เลือกหลายคอร์ส / แชร์แพ็กเกจ / แยกแพ็กเกจ
- ราคาแบบ Dynamic จาก Supabase
- Promotion code
- Dynamic Schedule แยกตามติวเตอร์
- เลือกเวลาเฉพาะช่วงที่ติวเตอร์ทุกคนในตะกร้าว่างตรงกัน
- Capacity และป้องกันจองชนที่ฐานข้อมูล
- แนบสลิปเข้า private Supabase Storage
- สมัครเรียน / ต่อคอร์ส
- เช็คสถานะการสมัคร + ประวัติล่าสุด
- ดาวน์โหลดใบเสร็จ PDF
- ระบบจ้างวิทยากร
- Banner / Logo / Branding จาก Manager

### Reviews subweb `/reviews/`
- รีวิวจากนักเรียน
- รูป ชื่อ โรงเรียน คอร์ส รีวิว คะแนนดาว
- Featured review
- Search + Filter

### Manager `/manager/`
- Supabase Auth + role `manager/admin`
- Dashboard
- Logo / Branding เว็บไซต์
- Banner Slider เพิ่ม/แก้ไข/ลบ/เปิด/ปิด/จัดลำดับ
- หมวดวิชา เพิ่ม/แก้ไข/เปิด/ปิด
- Tutor CRUD + รูป + ประวัติ + ระดับ + หมวด + วิดีโอ
- Course CRUD + รูป + รายละเอียด + outcomes + syllabus + badge
- รีวิว CRUD + Excel Import + Template
- Dynamic Schedule Templates
- ตารางสอนเฉพาะของติวเตอร์แต่ละคน
- ตั้งตารางรายสัปดาห์แบบ Bulk / Merge / Replace
- Copy ตารางระหว่างติวเตอร์
- Block ตารางทั้งสัปดาห์
- Capacity / Reservation status
- รายการสมัครเรียน + Search / Filter / Status
- คำขอจ้างวิทยากร + Status workflow
- ราคาคอร์ส
- Promotion codes
- ตรวจสลิป / Paid / Rejected
- Receipt settings: Logo, ลายเซ็น, Tax ID, ที่อยู่, Prefix
- System settings / Maintenance / Announcement

## โครงสร้าง

```text
arewarin-complete-system/
├─ index.html
├─ config.js
├─ config.example.js
├─ js/
│  ├─ supabase-bridge.js
│  └─ receipt.js
├─ manager/
│  ├─ index.html
│  └─ app.js
├─ reviews/
│  └─ index.html
├─ templates/
│  └─ arewarin-review-import-template.xlsx
└─ supabase/
   ├─ AREWARIN_FULL_SETUP.sql
   ├─ PROMOTE_ADMIN.sql
   ├─ config.toml
   ├─ legacy-upgrades/
   └─ functions/
      ├─ create-enrollment/index.ts
      └─ get-receipt/index.ts
```

# ติดตั้งจาก Supabase Project ใหม่

## 1. สร้าง Supabase Project

สร้าง Project ใหม่ที่ Supabase

## 2. สร้าง Manager Auth user

Dashboard → Authentication → Users → Add user

แนะนำให้สร้าง email ที่จะใช้เข้า Manager ก่อนรัน SQL เช่น:

```text
arewarin.biology@gmail.com
```

## 3. รัน SQL ตัวเดียว

Dashboard → SQL Editor → New Query

Copy ทั้งไฟล์:

```text
supabase/AREWARIN_FULL_SETUP.sql
```

แล้วกด **Run**

SQL นี้ใช้สำหรับ Fresh Project และรวมทุกฟีเจอร์ไว้แล้ว ไม่ต้องรันไฟล์ upgrade แยก

ถ้า Auth user ถูกสร้างไว้ก่อน SQL จะ promote email `arewarin.biology@gmail.com` เป็น admin อัตโนมัติ หากใช้ email อื่น ให้แก้ `v_admin_email` ท้าย SQL หรือรัน `PROMOTE_ADMIN.sql` หลังแก้ email

## 4. ตั้งค่า `config.js`

นำ Project URL และ Publishable/Anon key จาก Project Settings → API มาใส่:

```js
window.AREWARIN_CONFIG = {
  SUPABASE_URL: 'https://ihmiqtwclnqrezsnswfz.supabase.co',
  SUPABASE_ANON_KEY: '<ใส่ Publishable Key ใน config.js>'
};
```

> Publishable/Anon key เป็น key สำหรับ frontend ได้ แต่ห้ามใส่ `service_role` key ใน GitHub หรือ browser

## 5. Deploy Edge Functions

ติดตั้ง Supabase CLI แล้วรันจาก root ของ project:

```bash
supabase login
supabase link --project-ref ihmiqtwclnqrezsnswfz
supabase functions deploy create-enrollment --no-verify-jwt
supabase functions deploy get-receipt --no-verify-jwt
```

ระบบใช้ public Edge Functions เพราะหน้า Student ไม่ได้ login แต่ภายใน function ใช้ service role จาก Supabase environment และข้อมูลสำคัญยังถูกป้องกันด้วย receipt token / server-side logic

## 6. ทดสอบ local

อย่าเปิด `index.html` ด้วย `file://` โดยตรง ให้ใช้ local server:

```bash
python -m http.server 8080
```

แล้วเปิด:

```text
http://localhost:8080/
http://localhost:8080/manager/
http://localhost:8080/reviews/
```

## 7. Deploy GitHub

นำ folder นี้ขึ้น GitHub และ deploy ด้วย GitHub Pages, Netlify หรือ Vercel ได้

# Storage ที่ SQL สร้าง

- `payment-slips` — PRIVATE
- `receipt-assets` — PRIVATE
- `tutor-assets` — PUBLIC
- `course-assets` — PUBLIC
- `review-assets` — PUBLIC
- `site-assets` — PUBLIC

# ตารางหลัก

- `profiles`
- `tutors`
- `courses`
- `course_prices`
- `promotions`
- `app_settings`
- `enrollments`
- `payments`
- `receipt_settings`
- `receipt_sequences`
- `schedule_templates`
- `tutor_schedules`
- `schedule_reservations`
- `speaker_requests`
- `reviews`
- `site_branding`
- `home_banners`
- `subject_categories`

# หมายเหตุด้านระบบ

- Email notification ถูกตัดออกตาม requirement
- สลิปไม่ถูกเปิด public
- Logo/Signature ของใบเสร็จเป็น private asset และใช้ signed URL ชั่วคราว
- ราคา Student ใหม่คำนวณซ้ำใน Edge Function ไม่เชื่อยอดจาก browser
- การ reserve ตารางใช้ database function + row lock เพื่อป้องกัน capacity ชน
- เบอร์โทรสำหรับเช็คสถานะส่งผ่าน RPC ที่คืนเฉพาะข้อมูลจำเป็น
- Student reviews Excel template อยู่ใน `/templates/`


---

## Tutor Application System
เพิ่ม subweb `/tutor-apply/` สำหรับสมัครร่วมทีมติวเตอร์ พร้อม Manager review, private document storage และ status tracking

- Existing Supabase project: run `supabase/TUTOR_APPLICATION_UPGRADE.sql`
- New project: `supabase/AREWARIN_FULL_SETUP.sql` รวมฟีเจอร์นี้แล้ว
- Deploy: `supabase functions deploy submit-tutor-application --no-verify-jwt`

ดูรายละเอียดใน `TUTOR_APPLICATION_SETUP.md`
