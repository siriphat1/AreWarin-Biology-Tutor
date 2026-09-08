# AreWarin Student Deploy Fix V15.6.1

สาเหตุของบัคในภาพ: `student/index.html` ถูกนำไปวางทับ root `/index.html` ทำให้ URL หลักแสดง Student Portal และ `../config.js` ชี้ออกนอกโฟลเดอร์โปรเจกต์ จึง 404.

โครงสร้างที่ถูกต้อง:

```
AreWarin-Biology-Tutor/
├─ index.html                 # ระบบสมัครเรียนหลัก
├─ config.js                  # Supabase public config
└─ student/
   ├─ index.html              # Student Portal V15.6.1
   └─ theme-v15.6.1.css
```

Deploy:
1. Root `/index.html` ใช้ไฟล์ index.html ในแพ็กนี้
2. Root `/config.js` ใช้ไฟล์ config.js ในแพ็กนี้
3. `/student/index.html` ใช้ student/index.html
4. `/student/theme-v15.6.1.css` ใช้ student/theme-v15.6.1.css
5. Hard refresh

Student V15.6.1 มี public Supabase fallback ในตัว จึงไม่ค้างหน้า Loading หาก config file โหลดไม่ได้.
