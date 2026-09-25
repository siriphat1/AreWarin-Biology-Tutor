# Student Portal — โรงเรียนวัดหนองแวงวิทยา

## URL structure
- `/student-portal/` — Student Portal
- `/student-portal/manager/` — Student Manager
- `/student-portal/templates/student-import-template.xlsx`
- `/student-portal/templates/timetable-import-template.xlsx`
- `/student-portal/templates/exam-import-template.xlsx`

## ก่อนใช้งาน
1. เข้า Supabase > SQL Editor
2. Run `supabase/student-portal.sql`
3. ตรวจสอบ Table Editor ว่ามีตาราง:
   - `students`
   - `student_timetables`
   - `student_exams`
   - `student_grade_uploads`
   - `student_portal_sessions`
4. ตรวจสอบ Storage ว่ามี private bucket `student-portal-files`
5. อัปเว็บไซต์ขึ้น GitHub Pages
6. เข้า `/student-portal/manager/` ด้วยบัญชี Supabase Authentication ของผู้ดูแล

## การเข้าสู่ระบบของนักเรียน
ระบบใช้ **รหัสนักเรียน + PIN** เพื่อไม่ให้บุคคลที่รู้เพียงรหัสนักเรียนสามารถเปิดข้อมูลส่วนบุคคลและไฟล์ผลการเรียนได้

ผู้ดูแลกำหนด PIN ตอนเพิ่มนักเรียน หรือใส่ใน Excel template ได้ หากเว้น PIN สำหรับนักเรียนใหม่ ระบบจะสร้าง PIN 6 หลักและดาวน์โหลด CSV ให้ผู้ดูแลเก็บไว้

## Excel / AI workflow
Template ทุกไฟล์มีชีต `AI_INSTRUCTIONS` ซึ่งสามารถส่งให้ AI พร้อมภาพ/PDF ต้นฉบับ เพื่อให้ AI จัดข้อมูลกลับมาในโครงสร้างที่ Manager นำเข้าได้

### นักเรียน
Template: `student-import-template.xlsx`

### ตารางเรียน
Template: `timetable-import-template.xlsx`
หนึ่งแถว = หนึ่งคาบ มี วัน เวลาเริ่ม/สิ้นสุด รหัสวิชา วิชา ครูผู้สอน ห้อง ภาคเรียน และปีการศึกษา

### วันสอบ
Template: `exam-import-template.xlsx`
หนึ่งแถว = หนึ่งวิชาที่สอบ มีวันที่ เวลา รหัสวิชา วิชา ประเภทสอบ ห้องสอบ ภาคเรียน และปีการศึกษา

## การเก็บไฟล์
- รูปนักเรียนและไฟล์ผลการเรียนอยู่ใน bucket `student-portal-files`
- Bucket เป็น private
- นักเรียนเข้าถึงไฟล์ผ่าน `storage_key` แบบ UUID ที่ระบบคืนให้หลังยืนยันรหัสนักเรียน + PIN สำเร็จ
- ผู้ดูแลที่ล็อกอินผ่าน Supabase Authentication สามารถเปิดไฟล์ได้
