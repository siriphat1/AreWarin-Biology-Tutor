# การทดสอบ

- `node tests/test_logic.cjs` : ทดสอบระยะเวลา 11 กรณี + ตรวจว่า HTML มีเมนู/สคริปต์ + SQL มี RPC/RLS ตามรายการ
- `tests/mock-preview.html` : หน้า Preview ฝั่ง Browser (ข้อมูลจำลองที่เปิดเผยว่า MOCK) สำหรับตรวจ UI เท่านั้น เปิดจาก Local HTTP Server

```powershell
# อยู่ในโฟลเดอร์ AreWarin_TutorOS_Attendance_Integration
py -m http.server 5500
# เปิด http://localhost:5500/tests/mock-preview.html
```

**ข้อจำกัด:** การเปิด Chromium อัตโนมัติในสภาพแวดล้อมสร้างไฟล์ถูกบล็อก (`ERR_BLOCKED_BY_ADMINISTRATOR`), จึงไม่มีผลยืนยันการทดสอบคลิกใน Browser จริงในรุ่นนี้ อีกทั้งยังไม่ได้ทดสอบ SQL บน Supabase ของผู้ใช้ ต้องทำ Staging smoke test ตามคู่มือก่อนใช้งานจริง
