AreWarin Library V2 COMPLETE — NO-TS
====================================

รุ่นนี้รวมระบบ Library V1.1 + V2 upgrade ใน SQL ไฟล์เดียว และไม่ต้อง Deploy Library Edge Function / ไม่มี .ts ใหม่

ไฟล์หลักจริง ๆ
1) /library/index.html
2) /supabase/AREWARIN_LIBRARY_V2_COMPLETE_NO_TS.sql
3) /library/arewarin-library-import-template-v2.xlsx
4) /manager/index.html (optional — เพิ่มลิงก์ Library OS ให้ Manager ล่าสุด)

ติดตั้งแบบ Fresh Install
1. Supabase > SQL Editor
2. รัน AREWARIN_LIBRARY_V2_COMPLETE_NO_TS.sql ทั้งไฟล์
3. ตรวจท้าย SQL ให้ arewarin_library_v2_status -> ok = true
4. อัป /library/index.html
5. อัป /library/arewarin-library-import-template-v2.xlsx
6. ต้องมี /config.js เดิม
7. Student signup ใน Library ใช้ student-auth เดิมของ Student Hub — ไม่ต้องเพิ่ม Library .ts
8. ถ้าต้องการเมนู Library OS ใน Manager ให้อัป manager/index.html
9. Ctrl + Shift + R

ถ้าติดตั้ง V1/V1.1 ไปแล้ว
- SQL V2 เป็น cumulative จึงรันได้เช่นกัน
- จากนั้นทับ library/index.html และ template V2

Storage
- library-covers = Public เฉพาะภาพปก
- library-books = PRIVATE สำหรับ PDF
- ห้ามเปลี่ยน library-books เป็น public

ฟีเจอร์ V2
- Favorite + Pin / My Shelf
- Continue Reading / Recently Viewed / Completed
- NEW + unread new badge
- Featured / Recommended / Popular
- Collections / Category Tree
- My Course recommendations + per-course access
- Book Detail + Related Books
- Request a Book
- Bookmark ต่อหน้า / Personal Notes
- Reading progress
- PDF.js Private Reader
- Jump page / TOC / Zoom / Fit Width / Fit Page / Fullscreen
- Light / Dark / Sepia reader
- Dynamic user/time watermark
- Ctrl+S / Ctrl+P / right-click deterrence
- Active device/session limit
- Admin Dashboard
- Library Studio + Live Preview
- Drag & Drop PDF/Cover
- Existing Cover Library
- ISBN validation
- SHA-256 PDF duplicate warning
- Tags chips
- Draft / Published / Hidden / Archived
- Soft Delete / Restore
- Bulk Actions
- Excel Preview + Validation + Import Result
- Collections / Course restriction management
- Book requests workflow
- Audit Log
- Settings

ข้อจำกัด No-TS
Browser จะสร้าง Signed URL ชั่วคราวหลัง RPC + Storage RLS ตรวจสิทธิ์แล้ว
จึงไม่มีปุ่ม Download และไม่มี public PDF URL แต่ผู้ใช้ที่เชี่ยวชาญ DevTools อาจเห็น temporary signed URL ขณะที่ยังไม่หมดอายุได้
ระบบเว็บไม่สามารถป้องกัน screenshot หรือการบันทึกข้อมูล 100% ได้

ไม่ควรทำ
- ห้ามใส่ SUPABASE_SERVICE_ROLE_KEY ใน HTML
- ห้ามทำ library-books เป็น Public
- ห้ามลบ library_user_can_access_item / library_can_read_path
