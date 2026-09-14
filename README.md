# AreWarin V17.1 — Realtime Teaching & Payment Fix

## สิ่งที่แก้
- หน้า Student > การชำระเงิน:
  - QR หมดอายุไม่แสดงกล่อง QR ว่างขนาดใหญ่
  - แสดงสถานะหมดอายุแบบ compact และปุ่มสร้าง QR ใหม่
  - เมื่อคอร์ส Active/Paused/Completed แล้ว payment เดิมถูก reconcile เป็น paid และซ่อนจากรายการที่ต้องชำระ
- Tutor OS > การสอน > ลงเวลา & ตัดชม.:
  - Quick Private Lesson Clock
  - เลือก Tutor / Student / Course Wallet
  - เห็นชั่วโมงคงเหลือก่อนสอน
  - ลงวันที่ เวลาเริ่ม เวลาเลิก และคำนวณชั่วโมงอัตโนมัติ
  - เริ่มจับเวลา “ตอนนี้” และกดจบคาบภายหลัง
  - ป้องกันตัดเกินชั่วโมงคงเหลือ
  - เขียน Attendance + Hour Ledger + Teaching Log ใน flow เดียว
- Student:
  - ชั่วโมงคงเหลือและคาบล่าสุดอัปเดตจาก Tutor OS แบบ Realtime
  - หน้าเวลาเรียนแสดงเวลาเริ่ม/จบ ผู้สอน สถานะ และชั่วโมงที่ตัด

## ติดตั้ง
1. Run `supabase/V17_1_REALTIME_TEACHING_UPGRADE.sql`
2. Replace `/student/index.html`
3. Replace `/tutor-os/app.js`
4. `/tutor-os/index.html` แนบมาเพื่อความครบชุด แต่ถ้าไฟล์เดิมเป็น V17 อยู่แล้วไม่จำเป็นต้องเปลี่ยน
5. Hard refresh

No Edge Function redeploy is required.
