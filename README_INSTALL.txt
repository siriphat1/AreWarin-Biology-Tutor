AreWarin V25.1 — Legacy Multi-course + Tutor-managed Shared Hours

สิ่งที่เพิ่ม

MANAGER > นักเรียนเก่ารอตรวจ
- เลือกคอร์สปัจจุบันจาก “คอร์สที่น้องกรอกมา” ได้โดยตรง
- เลือกได้หลายคอร์สพร้อมกัน
- มีรายการ “คอร์สอื่น ๆ ในระบบ” ให้เลือกเพิ่ม
- กดครั้งเดียวสร้าง Active Course Wallet ทุกคอร์ส
- นักเรียนจึงขึ้นใน Tutor OS และจัดตารางได้ทุกคอร์ส
- ไม่สร้าง Enrollment / Payment ย้อนหลัง

TUTOR OS > นักเรียน & CRM
- นักเรียนที่มี 2+ Current Courses จะมีปุ่ม “แชร์เวลาเรียน”
- Tutor เป็นผู้เลือกคอร์สที่จะใช้ชั่วโมงร่วมกันเอง
- Tutor ระบุจำนวนชั่วโมงรวมเอง เช่น Biology + Chemistry = 20 ชม.
- รองรับ Unlimited
- ย้ายจำนวนชั่วโมงที่ใช้ไปแล้วจาก pool เดิมเข้า Shared Pool แบบไม่ซ้ำ pool
- Realtime และ Manual lesson ใช้ Shared Pool เดียวกัน
- หน้า CRM คำนวณชั่วโมงคงเหลือแบบไม่บวก Shared Pool ซ้ำ

ตัวอย่าง
นักเรียน A:
  Biology current
  Chemistry current
Tutor สร้าง Shared Hour Pool = 20 ชั่วโมง
สอน Biology 1.5 ชม. -> เหลือ 18.5
สอน Chemistry 2 ชม. -> เหลือ 16.5

ติดตั้ง
1) ต้องมี Manager V25 bridge + Tutor OS V19
2) Supabase SQL Editor -> Run:
   AREWARIN_V25_1_LEGACY_MULTICOURSE_SHARED_HOURS.sql
3) ทับ:
   /manager/index.html
   /tutor-os/index.html
   /tutor-os/app.js
4) Ctrl + Shift + R

ข้อสำคัญ
Manager มีหน้าที่เลือก “คอร์สที่กำลังเรียน”
Tutor มีหน้าที่กำหนด “Shared Hour Pool / จำนวนชั่วโมง”
เพื่อไม่ให้ Manager เดาจำนวนชั่วโมงของนักเรียนเก่า
