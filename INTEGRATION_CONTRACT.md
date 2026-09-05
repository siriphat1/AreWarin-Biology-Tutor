# AreWarin Integration Contract

ใช้เอกสารนี้เป็นกติกาสำหรับ Subweb ใหม่ทุกตัวในอนาคต

## 1. ห้ามสร้างข้อมูลหลักซ้ำ
ระบบใหม่ต้อง reuse:
- `courses`
- `course_offerings`
- `tutors`
- `os_students`
- `enrollments` / `enrollment_items`
- `os_student_course_enrollments`
- `os_hour_pools` / `os_hour_ledger`

## 2. ทุกโมดูลต้อง Register
เพิ่ม record ใน `os_module_registry` เพื่อให้ Unified Core รู้ path, role และ area

## 3. ใช้ Event Bus เมื่อข้อมูลสำคัญเปลี่ยน
ส่ง event ผ่าน `aw_emit_event()` หรือ trigger ไป `os_system_events`

## 4. Realtime เฉพาะข้อมูลที่ผู้ใช้ต้องเห็นทันที
ตัวอย่าง:
- ชั่วโมงเรียน
- Attendance
- Course Offering
- Notification
- Group Locker membership

## 5. สิทธิ์ต้องบังคับที่ Database
ห้ามพึ่งการซ่อนปุ่มใน UI อย่างเดียว ต้องมี RLS/RPC authorization

## 6. Business action สำคัญควรเป็น RPC/Edge Function
เช่น payment approval, hour deduction, enrollment creation เพื่อให้ transaction เป็น atomic และ audit ได้

## 7. Theme
Subweb ใหม่ใช้ Prompt + Navy / Slate / Sky / Indigo + card radius / spacing เดียวกับ AreWarin

## 8. URL Convention
- `/manager/` Admin content/config
- `/tutor-os/` Staff operations
- `/student/` Student account
- `/tutor-apply/` Public tutor application
- Subweb ใหม่ใช้ folder ของตัวเองและเชื่อมกลับ Unified Core
