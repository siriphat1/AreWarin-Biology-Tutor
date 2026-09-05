# AreWarin Tutor Application System

ระบบสมัครร่วมทีมติวเตอร์สำหรับ AreWarin Biology ใช้ธีมเดียวกับเว็บหลักและเชื่อม Supabase Project เดียวกัน

## URL
- หน้าใบสมัคร: `/tutor-apply/`
- หลังบ้าน: `/manager/` > `สมัครติวเตอร์`

## ฟีเจอร์ผู้สมัคร
- ชื่อ / นามสกุล / ชื่อเล่น / เบอร์ / อีเมล / LINE / จังหวัด / อาชีพปัจจุบัน
- แนะนำตัว
- ประวัติการศึกษาหลายรายการ
- ประวัติการทำงาน/การสอนหลายรายการ
- รางวัล / ใบประกาศ / ผลงาน
- เลือกวิชาที่สอนจาก `subject_categories`
- ระดับผู้เรียนและรูปแบบ Online / Onsite
- ประสบการณ์สอน / เรทที่คาดหวัง / พื้นที่ Onsite
- เลือกวันและช่วงเวลาที่สะดวกประจำ
- สไตล์การสอน / เหตุผลที่อยากร่วมทีม
- แนบรูป, Resume/CV, Portfolio, Transcript
- บันทึกร่างอัตโนมัติใน Local Storage
- ออกเลขใบสมัครรูปแบบ `AWT-YYYY-000001`
- เช็คสถานะด้วยเลขใบสมัคร + เบอร์โทร

## ความเป็นส่วนตัว
ไฟล์ผู้สมัครเก็บใน bucket `tutor-application-assets` แบบ Private และเปิดดูผ่าน Signed URL เฉพาะ Manager/Admin เท่านั้น

## ติดตั้งใน Project เดิม
1. เปิด Supabase > SQL Editor
2. Run `supabase/TUTOR_APPLICATION_UPGRADE.sql`
3. Deploy Edge Function

```bash
supabase functions deploy submit-tutor-application --no-verify-jwt
```

## Project ใหม่
ใช้ `supabase/AREWARIN_FULL_SETUP.sql` รุ่นที่อยู่ในชุดนี้ ซึ่งรวม Tutor Application แล้ว จากนั้น deploy Edge Function ด้านบน

## Manager
เมนู `สมัครติวเตอร์` รองรับ:
- ค้นหาและกรองสถานะ
- ดูข้อมูลการศึกษาและประสบการณ์ทั้งหมด
- เปิดไฟล์แนบแบบ Signed URL
- สถานะ: New / Reviewing / Interview / Accepted / Rejected / Withdrawn
- ข้อความสถานะที่ผู้สมัครมองเห็น
- Manager note ภายใน
- นำข้อมูลผู้สมัครไป Prefill ฟอร์ม `ติวเตอร์` และคัดลอกรูปโปรไฟล์ไป `tutor-assets`
