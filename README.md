# AreWarin Ready Replace v9 — Strict Course Category

ตรงตาม rule ใหม่:

**เลือกหมวดไหน -> แสดงเฉพาะคอร์สที่ผูกกับหมวดนั้น**

ตัวอย่าง:
- Biochemistry -> `medical-biochemistry`
- A-Level Biology -> `biology`
- General Chemistry -> `chemistry`

เมื่อเลือก `medical-biochemistry`:
- Biochemistry ✅
- A-Level Biology ❌
- General Chemistry ❌

แม้เป็นติวเตอร์คนเดียวกัน คอร์สอื่นจะไม่ถูกดึงเข้ามา

## สาเหตุที่ v8 แสดงทั้งหมด

v8 มี recovery fallback:
ถ้า mapping ของคอร์สไม่ครบ แต่ติวเตอร์อยู่ในหมวดที่เลือก
ระบบจะแสดงคอร์สทั้งหมดของติวเตอร์ เพื่อป้องกันหน้า 0 คอร์ส

v9 ลบ fallback นี้ออกทั้งหมด

## Source of truth

ใช้ `course_categories` เท่านั้น

คอร์สไม่มี row ใน `course_categories`
= ไม่อยู่ในหมวดใด
= ไม่แสดงในหน้า category นั้น

## ติดตั้ง

วางทับ:
- `/index.html`
- `/manager/index.html`

ถ้า V5 Recovery SQL เคยรันสำเร็จแล้ว ไม่ต้อง run migration ใหม่

## Debug

เปิด Console:

AWV9DebugCategory()

ดู `matchedCourses` เทียบกับ `allTutorCourses`
