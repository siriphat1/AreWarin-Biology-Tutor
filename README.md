# AreWarin Student Experience V15.5

Release นี้แก้ 4 เรื่องพร้อมกัน:

1. Student UI เปลี่ยนทิศทางใหม่ให้ใช้ visual language เดียวกับ `index.html` ระบบสมัครเรียน: Prompt, sky/indigo pastel, glass card, เส้นบาง, มุมโค้ง และปุ่มแบบเดียวกัน รวมถึง sidebar, dashboard, course, payment, profile และ installment modal
2. Manager ยืนยันการชำระ/เปลี่ยน Enrollment เป็น confirmed แล้วสถานะ Student Portal จะตามเป็น `ชำระแล้ว` และคอร์สเปิด Active อัตโนมัติ
3. Student Portal แสดงชื่อจริง-นามสกุลและข้อมูลจากใบสมัครล่าสุด พร้อมแก้ไขข้อมูลติดต่อที่อนุญาต
4. แก้ `column "l.lesson_date" must appear in the GROUP BY clause...` ใน `student_v9_payment_bootstrap()`

## Existing Supabase project

รัน `supabase/V15_5_CUMULATIVE_UPGRADE.sql` ใน SQL Editor หนึ่งครั้ง จากนั้นอัปไฟล์:

- `/student/index.html`
- `/student/theme-v15.5.css`

ไม่ต้อง redeploy Edge Function สำหรับ patch นี้

หลังอัป GitHub Pages ให้ Hard Refresh (`Ctrl + Shift + R`) แล้วทดสอบ:

- Manager -> ยืนยัน payment / Active
- Student -> Dashboard ต้องขึ้น `ชำระแล้ว`
- Student -> คอร์สของฉัน ต้องเป็น Active
- Student -> บัญชีของฉัน ต้องเห็นข้อมูลใบสมัคร
- Student -> การชำระเงิน -> ดูแผนผ่อน ต้องไม่เกิด GROUP BY error
