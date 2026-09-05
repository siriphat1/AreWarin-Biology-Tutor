# V15.1 Setup — Current Project

## 1) Upload release to GitHub
แทนไฟล์เดิมด้วยโครงจาก ZIP นี้ โดยคง `config.js` ที่ให้มา

## 2) Supabase SQL
Supabase → SQL Editor → New query → วางทั้งไฟล์:

`supabase/V15_1_EXISTING_PROJECT_UPGRADE.sql`

กด Run และตรวจผลท้าย query ว่ามี `groups`, `active_members`, `group_sessions`

## 3) Edge Functions
```bash
supabase login
supabase link --project-ref ihmiqtwclnqrezsnswfz
supabase functions deploy create-enrollment --no-verify-jwt
supabase functions deploy get-receipt --no-verify-jwt
supabase functions deploy submit-tutor-application --no-verify-jwt
supabase functions deploy student-auth --no-verify-jwt
```

## 4) Test Group Locker
- Login `/tutor-os/`
- กลุ่มเรียน · Locker → สร้างกลุ่ม
- เลือก Course/Tutor
- เพิ่มสมาชิก
- เปิดคาบ
- เช็กชื่อ
- เริ่ม/จบสอน
- กำหนดชั่วโมงรายคน
- บันทึกตัดชั่วโมง

## 5) Test Student
- `/student/`
- Login แล้วดู Attendance + ชั่วโมงคงเหลือ
- หรือหน้า Login → เช็กชั่วโมง → Student Code + PIN

## หมายเหตุ
Student Quick Check จะใช้ได้หลังนักเรียนสมัคร Student Portal และตั้ง PIN แล้ว หากยังไม่เคยสมัคร Portal ให้สมัครด้วยเบอร์เดิมก่อน
