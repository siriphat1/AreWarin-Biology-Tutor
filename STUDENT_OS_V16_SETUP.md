# AreWarin Student OS V16

## เพิ่มในรอบนี้
- Personal Schedule + ขอเลื่อน/ชดเชย
- Homework & Submission + คะแนน/Feedback
- Parent View แบบ token จำกัดข้อมูล
- Receipt Center + Certificate
- Support Ticket
- Course Recommendation / Course Catalog เชื่อมระบบสมัครเรียน
- Security Center + device registry + sign out other sessions
- PWA / Add to Home Screen
- Notification Rules + sweep
- Learning Journey + Recent Activity

## ติดตั้ง
1. รัน `supabase/STUDENT_OS_V16_UPGRADE.sql` หลัง SQL V15.7 ที่มีอยู่แล้ว
2. อัปโฟลเดอร์ `student/`, `parent/`, `manager/student-services/`, `tutor-os/student-services/`
3. อัป `manager/index.html` และ `tutor-os/index.html` ที่ patch link แล้ว
4. Hard refresh

## Notification automation
ฟังก์ชัน `student_v16_run_notification_sweep()` พร้อมใช้งานจาก Manager > Student Services > Notification Rules. หากต้องการอัตโนมัติรายชั่วโมง ให้รัน `supabase/STUDENT_OS_V16_NOTIFICATION_CRON_OPTIONAL.sql` เพิ่ม (เฉพาะโปรเจกต์ที่เปิด Supabase Cron/pg_cron).
