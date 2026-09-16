# AreWarin Ready Replace v7 — Tutor Navigation Fix

แก้ปัญหา:
- หน้าเลือกหมวดแสดงแล้ว
- แต่กดหมวดแล้วหน้าเลือกติวเตอร์ไม่เปิด หรือไม่เห็นติวเตอร์

สาเหตุหลักคือระบบใหม่ใช้หมวดระดับคอร์ส แต่หน้าติวเตอร์เดิมยังอ้าง
`tutorProfiles[].categories`

v7 แก้โดย:
- sync หมวดของคอร์สกลับเข้า tutor profile
- ใช้ renderer หน้าติวเตอร์เดิมเป็นหลัก
- บังคับ category click ให้เปิด `stepTutor` ก่อน render
- มี capture-click fallback กัน onclick เดิมค้าง
- เก็บระบบซ่อน package และราคาเฉพาะคอร์สจาก v6 ไว้ครบ

## ติดตั้ง
วางทับ:
- `/index.html`
- `/manager/index.html`

ไม่ต้องรัน SQL ใหม่ ถ้า V5 Recovery เคยรันสำเร็จแล้ว

หลัง Push:
1. รอ GitHub Pages deploy
2. Ctrl + Shift + R
3. กดหมวด เช่น ชีววิทยา
4. ต้องเปิดหน้าเลือกติวเตอร์ทันที
