# AreWarin Ready Replace v8 — Course List Hydration Fix

แก้ปัญหา:
- หมวดขึ้น
- เลือกติวเตอร์ได้
- แต่หน้า Course Catalog ขึ้น `0 คอร์ส`

## สาเหตุ
ระบบมีคอร์ส fallback อยู่ก่อน แล้ว `loadRemoteCatalog()` ค่อยแทนด้วยข้อมูลจริงจาก Supabase
รุ่นก่อนอาจผูก `categoryIds` ให้ object fallback ก่อน พอ catalog จริงมาแทน คอร์สจริงไม่มี mapping จึงถูกกรองเหลือ 0

## V8 แก้
- หลังโหลด catalog จริง จะ reload `course_categories`
- ตอนเลือกติวเตอร์ reload mapping อีกครั้ง
- ถ้า mapping ยังไม่ครบ แต่ติวเตอร์อยู่ในหมวดนั้น จะ fallback แสดงคอร์สของติวเตอร์ แทนการขึ้น 0
- เมื่อ mapping พร้อม ระบบจะกรองรายคอร์สตามหมวดตามปกติ
- ระบบราคาเฉพาะคอร์ส / ซ่อนแพ็กเกจยังอยู่ครบ

## ติดตั้ง
วางทับ:
- `/index.html`
- `/manager/index.html`

ถ้า V5 Recovery SQL เคยรันสำเร็จแล้ว ไม่ต้องรัน SQL ใหม่

## Debug
ถ้ายังมีปัญหา เปิด Console แล้วพิมพ์:

AWV8DebugCatalog()

จะเห็น selectedTutor, selectedCategory, จำนวนคอร์ส และ categoryIds
