# Existing Student Renewal V11

## ฟีเจอร์
- นักเรียนเดิมค้นหาด้วยเบอร์โทรที่ใช้สมัครเดิม
- ดึงข้อมูลส่วนตัวและคอร์สล่าสุด
- แสดงประวัติสมัครล่าสุด
- ต่อคอร์สเดิม หรือแก้ไข/เพิ่มคอร์ส
- แก้ชื่อ ชื่อเล่น เบอร์ใหม่ LINE Email สถานศึกษา ระดับชั้น คณะ จังหวัด
- เปลี่ยนเรียนเดี่ยว/กลุ่ม
- ใช้ package picker + dynamic tutor schedule แบบเดียวกับนักเรียนใหม่
- server คำนวณราคาซ้ำ
- server ตรวจว่า `previousEnrollmentId` ตรงกับเบอร์ lookup เดิมก่อนรับ renewal

## ติดตั้งกับ Supabase เดิม
1. เปิด Supabase SQL Editor
2. รัน `supabase/EXISTING_STUDENT_RENEWAL_UPGRADE.sql`
3. Redeploy Edge Function:
   `supabase functions deploy create-enrollment --no-verify-jwt`
4. Deploy frontend ชุดล่าสุดทั้งหมด เพราะมีการแก้:
   - `index.html`
   - `js/supabase-bridge.js`
   - `manager/app.js`
   - `manager/index.html`

## หมายเหตุ
RPC `lookup_existing_student()` รับเฉพาะเบอร์โทรที่ตรงกับรายการเดิม และคืนข้อมูลที่จำเป็นต่อการต่อคอร์ส ไม่คืนข้อมูลผู้ปกครองหรือ raw payload
