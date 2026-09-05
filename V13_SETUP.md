# AreWarin V13 — Policy CMS + International Tutor Application

## สิ่งที่เพิ่ม

### `/tutor-apply/`
- หน้า Welcome ก่อนเริ่มสมัคร
- หน้า Policies & Guidelines ก่อนเข้าสู่แบบฟอร์ม
- ปุ่ม TH / EN เปลี่ยนภาษาทั้งระบบสมัครติวเตอร์
- Policy ภาษาไทย/อังกฤษตามค่าที่ Manager กำหนด
- ฟอร์ม 4 ขั้นตอนเดิม
- รองรับผู้สมัครต่างชาติ: สัญชาติ ประเทศที่พำนัก และเบอร์โทร 8–15 หลัก
- เก็บ `preferred_language` เพื่อให้ Manager ทราบว่าผู้สมัครใช้ภาษาใด
- เก็บ Revision ของนโยบายที่ผู้สมัครยอมรับ

### `/manager/` → นโยบาย & กติกา
Manager แก้ได้ทั้ง:
- ระบบสมัครเรียนหลัก
- ระบบสมัครติวเตอร์
- Welcome text
- Policy title/subtitle
- Consent text
- ปุ่มดำเนินการ
- เพิ่ม/แก้ไข/ลบ/ซ่อน/เรียง Policy Section
- ภาษาไทยและ English
- ทุกครั้งที่แก้จะเพิ่ม Revision

### ระบบสมัครเรียนหลัก
หน้า Policy ของนักเรียนดึงจาก Supabase `policy_pages` และ `policy_sections`
ดังนั้นแก้กติกาจาก Manager แล้วหน้าเว็บจะเปลี่ยนตาม โดยไม่ต้องแก้ HTML

## Supabase Project ปัจจุบัน

ถ้า Project ของคุณมีระบบเดิมอยู่แล้ว ให้รัน:

`supabase/V13_EXISTING_PROJECT_UPGRADE.sql`

ไฟล์นี้เป็น cumulative upgrade รวม:
1. Existing Student Renewal
2. Tutor Application
3. Editable Policy CMS
4. International / bilingual Tutor Application

จากนั้น Redeploy Edge Function:

```bash
supabase link --project-ref ihmiqtwclnqrezsnswfz
supabase functions deploy submit-tutor-application --no-verify-jwt
supabase functions deploy create-enrollment --no-verify-jwt
```

`submit-tutor-application` ต้อง redeploy เพราะ V13 รองรับ international phone, language, nationality และ country.

## Supabase Project ใหม่

ใช้ไฟล์เดียว:

`supabase/AREWARIN_FULL_SETUP_V13.sql`

ไม่ต้องรันไฟล์ upgrade แยก

## หมายเหตุ

- Publishable key ใน `config.js` ใช้กับ browser ได้
- ห้ามนำ Service Role Key ไปใส่ frontend/GitHub
- ไฟล์ผู้สมัครติวเตอร์ยังเก็บใน private bucket `tutor-application-assets`
