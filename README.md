# AreWarin Biology · Unified System V15.1

Release นี้รวม Enrollment, Manager, Tutor OS, Student Portal, Tutor Application, Reviews และ Library ให้ใช้ Supabase Project เดียวและอ้างอิงข้อมูลกลางชุดเดียวกัน

## แนวคิดหลัก

Single Source of Truth:
- Course UUID
- Course Offering
- Student UUID + Student Code
- Enrollment UUID + Enrollment Items
- Tutor UUID
- Hour Pool + Hour Ledger
- Attendance Session
- Payment / Portal Payment
- Module Registry + System Events

Subweb ใหม่ในอนาคตควรอ่าน/เขียนผ่านข้อมูลกลางเหล่านี้ ไม่สร้าง Student/Course/Tutor ซ้ำ

## V15.1 เพิ่ม Group Lockers

Tutor OS → **กลุ่มเรียน · Locker**

- สร้างกลุ่มเรียนผูกกับ Course + Tutor
- Group Code อัตโนมัติ เช่น `AWG-2026-0001`
- เพิ่ม/นำสมาชิกออกโดยไม่ลบประวัตินักเรียน
- สมาชิกต้องมี Enrollment ของคอร์สเดียวกับกลุ่ม
- กำหนดชั่วโมงเริ่มต้นต่อคาบ และ override รายคนได้
- เปิดคาบจาก Locker แล้วสร้าง roster `pending` อัตโนมัติ
- เช็กชื่อ มาเรียน / สาย / ขาด / ลา
- เริ่มจับเวลาจริง / จบและคำนวณเวลา
- ตัดชั่วโมง **รายคน** หรือบันทึกทั้งกลุ่มในครั้งเดียว
- ปรับชั่วโมงซ้ำได้โดยสร้าง Adjustment ใน Hour Ledger ไม่ double-charge
- Admin คืนชั่วโมงรายคนหรือทั้งคาบได้
- Student Portal อัปเดต Realtime จาก Hour Ledger

> Group Locker เป็นเครื่องมือจัดกลุ่มของผู้สอน นักเรียนแต่ละคนยังมี Student Code, Enrollment, Hour Pool และประวัติส่วนตัวแยกจากกัน

## Student Portal

`/student/`

- สมัคร Portal ด้วยเบอร์ที่ใช้สมัครเรียน
- Login ด้วย Email/Password
- Student Code แสดงบน Digital Student Card
- เช็กชั่วโมงแบบเร็วด้วย **Student Code + PIN 4 หลัก** โดยไม่ต้อง login
- หน้า quick check แสดงเฉพาะชื่อ, คอร์ส, ชั่วโมงคงเหลือ และ Group Locker — ไม่เปิดเบอร์/อีเมล/ที่อยู่
- Attendance แสดงชั่วโมงที่ตัดจริงต่อคาบ
- Realtime: Hour Ledger, Attendance, Course Offering, Groups, Notifications

## Course Opening / Enrollment Integration

`course_offerings` เป็นสวิตช์กลางสำหรับทุกระบบ

Tutor OS เปิด/ปิด Course Offering →
- เว็บสมัครเรียนเห็น/ซ่อนคอร์สตาม Offering
- Student Portal Catalog เห็นคอร์สเดียวกัน
- Enrollment ใหม่สร้าง Enrollment Item ด้วย Course UUID
- ระบบ Student Operations และ Hour Pool อ้างอิง Course UUID เดียวกัน

## ติดตั้งกับ Supabase Project ปัจจุบัน

Project: `ihmiqtwclnqrezsnswfz`

ถ้า Project ปัจจุบันยังอยู่ V13/V14 ให้รันไฟล์เดียว:

```text
supabase/V15_1_EXISTING_PROJECT_UPGRADE.sql
```

ไฟล์นี้รวม V14 Tutor OS + V15 Unified Core + V15.1 Group Lockers

จากนั้น deploy Edge Functions:

```bash
supabase link --project-ref ihmiqtwclnqrezsnswfz
supabase functions deploy create-enrollment --no-verify-jwt
supabase functions deploy get-receipt --no-verify-jwt
supabase functions deploy submit-tutor-application --no-verify-jwt
supabase functions deploy student-auth --no-verify-jwt
```

## Fresh Supabase Project

ใช้ไฟล์เดียว:

```text
supabase/AREWARIN_FULL_SETUP_V15_1.sql
```

## โครงสร้าง

```text
/
├── index.html                 # สมัครเรียน / ต่อคอร์ส
├── config.js                  # Shared Supabase config
├── manager/                   # Admin/Manager
├── tutor-os/                  # Teaching / Group Locker / Operations
├── student/                   # Student Portal
├── tutor-apply/               # Tutor Recruitment TH/EN
├── reviews/                   # Reviews
├── library/                   # Student/Team Library
├── js/
└── supabase/
    ├── V15_1_EXISTING_PROJECT_UPGRADE.sql
    ├── V15_1_GROUP_LOCKERS_UPGRADE.sql
    ├── AREWARIN_FULL_SETUP_V15_1.sql
    └── functions/
```

## Security

- Frontend ใช้ Publishable Key เท่านั้น
- ห้ามใส่ `service_role` ใน GitHub
- Group Lockers เข้าถึงได้เฉพาะ Tutor OS staff
- Student quick hour check ต้องใช้ Student Code + PIN และคืนข้อมูลขั้นต่ำ
- Finance / HR / Staff permission ยังถูกจำกัดด้วย RLS ฝั่งฐานข้อมูล

## ตรวจสอบหลัง deploy

1. Tutor OS → กลุ่มเรียน → สร้าง Locker
2. เพิ่มนักเรียนที่มีคอร์สตรงกัน
3. เปิดคาบจาก Locker
4. เช็กชื่อรายคน
5. กดเริ่ม/จบสอน
6. ตั้งชั่วโมงรายคน เช่น 1.50 / 1.25 / 0.75
7. บันทึกตัดชั่วโมง
8. เปิด Student Portal ของนักเรียน → ชั่วโมงคงเหลือต้องเปลี่ยน
9. ลอง Student Code + PIN → Quick Check ต้องแสดงยอดเดียวกัน

