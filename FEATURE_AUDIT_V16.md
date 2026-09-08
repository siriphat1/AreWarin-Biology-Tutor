# AreWarin Student OS V16 — Feature Audit

## ฟีเจอร์เดิมที่คงไว้
- Login / สมัคร Student / PIN recovery
- Quick check ชั่วโมงด้วย Student Code + PIN
- Dashboard / Digital Student Pass
- คอร์สของฉัน / Progress / ชั่วโมงคงเหลือ
- Learning content: YouTube, video, file, external link, mark complete
- Attendance / Group Locker / Hour Ledger
- QR Payment / Slip / Installment / Partial payment
- Notifications / Profile / Course code
- สมัครคอร์สเพิ่ม / ต่อคอร์สผ่านระบบสมัครเรียนหลัก

## เพิ่ม V16 ครบชุด
1. ตารางเรียนส่วนตัว + ขอเลื่อน/ชดเชย
2. Learning Journey
3. Homework & Assignment Center + upload + score/feedback
4. Parent View แบบ token จำกัดข้อมูล
5. Receipt Center
6. Smart Course Recommendation
7. Recent Activity / Next Action
8. Support Ticket Center
9. Certificate / Achievement
10. Security Center + Device Registry + sign out other sessions
11. PWA / Add to Home Screen
12. Notification Rules + sweep function

## การเชื่อมระบบ
- Manager: `/manager/student-services/`
- Tutor OS: `/tutor-os/student-services/`
- Student OS: `/student/`
- Parent View: `/parent/`
- Shared Supabase: students, groups, courses, hour pools, payments, notifications + V16 tables
