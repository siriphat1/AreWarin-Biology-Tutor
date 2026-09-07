# AreWarin Student Course Sync V15.4.1

แก้กรณี Student Portal มี Student ID และยอดชำระแล้ว แต่หน้า “คอร์สของฉัน” ว่าง

## สาเหตุ
Edge Function รุ่น rescue บันทึก `enrollments` และ `payments` ได้ แต่ไม่ได้สร้าง `enrollment_items` ทำให้ trigger กลางไม่มีข้อมูลสำหรับสร้าง `os_student_course_enrollments` ซึ่งเป็นแหล่งข้อมูลคอร์สของ Student Portal/Tutor OS

## ทำตอนนี้
1. Supabase > SQL Editor > New query
2. วาง `supabase/V15_4_1_COURSE_SYNC_FIX.sql` ทั้งไฟล์ แล้ว Run 1 ครั้ง
3. Supabase > Edge Functions > create-enrollment > Code > `index.ts`
4. วาง `supabase/functions/create-enrollment/index.ts` แล้ว Deploy
5. เปิด endpoint ต้องเห็น version `v15.4.1-course-sync`
6. อัป `student/index.html` และ `student/theme-v15.4.css` ไป GitHub
7. Student Portal กด Refresh หรือ Ctrl+Shift+R

## พฤติกรรมใหม่
- ใบสมัครใหม่สร้าง course line item ทันที
- คอร์สที่ยังรอตรวจการชำระจะเห็นใน Student Portal เป็น “รอเปิดใช้งาน”
- เมื่อ Manager ยืนยันและ enrollment เป็น `confirmed` คอร์สจะเปลี่ยนเป็น active และเปิดชั่วโมง/บทเรียน
- SQL จะ backfill ใบสมัครเดิมที่มี `raw_payload.courseItems` โดยอัตโนมัติ
