# AreWarin Student Hub V15.2

V15.2 เป็น UI refresh ของ `/student/` โดยไม่เปลี่ยน data contract หรือ SQL

## เปลี่ยนอะไรบ้าง
- Theme หลัก: Prompt, Sky, Indigo, Slate, pastel glass
- Login / Signup / Quick Hours ใช้ visual language เดียวกับเว็บสมัครเรียน
- Sidebar / Mobile bottom navigation ใหม่
- Dashboard metrics และ Digital Student Card ใหม่
- Course, Learning, Attendance, Payment, Notification, Profile และ Installment modal ถูกปรับ theme ให้สอดคล้องกัน
- เพิ่มปุ่มกลับเว็บหลักใน Top bar

## Deploy
แทนที่โฟลเดอร์ `/student/` บน GitHub Pages ด้วยไฟล์ `student/index.html` และ `student/theme-v15.2.css` จากชุดนี้

ไม่ต้องรัน SQL และไม่ต้อง Redeploy Edge Function สำหรับการเปลี่ยน UI ครั้งนี้
