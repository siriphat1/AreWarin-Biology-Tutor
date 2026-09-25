-- ============================================================
-- Wat Nongwang Wittaya School Website CMS
-- Run this file in Supabase > SQL Editor
-- ============================================================

create extension if not exists pgcrypto;

create table if not exists public.site_settings (
  id integer primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.site_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.achievements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  year text,
  image_url text,
  description text not null default '',
  published boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.is_site_admin()
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  -- Authentication-first manager mode. Supabase anonymous users also use the
  -- authenticated Postgres role, so explicitly reject the is_anonymous claim.
  select auth.uid() is not null
     and coalesce((auth.jwt()->>'is_anonymous')::boolean, false) = false;
$$;

revoke all on function public.is_site_admin() from public;
grant execute on function public.is_site_admin() to authenticated;

alter table public.site_settings enable row level security;
alter table public.site_admins enable row level security;
alter table public.achievements enable row level security;

-- Public website can read settings.
drop policy if exists "public read site settings" on public.site_settings;
create policy "public read site settings" on public.site_settings
for select using (true);

-- Only admins can create/update/delete site settings.
drop policy if exists "admin insert site settings" on public.site_settings;
create policy "admin insert site settings" on public.site_settings
for insert to authenticated with check (public.is_site_admin());

drop policy if exists "admin update site settings" on public.site_settings;
create policy "admin update site settings" on public.site_settings
for update to authenticated using (public.is_site_admin()) with check (public.is_site_admin());

drop policy if exists "admin delete site settings" on public.site_settings;
create policy "admin delete site settings" on public.site_settings
for delete to authenticated using (public.is_site_admin());

-- Admin can read their own admin record. The security-definer function handles role checks.
drop policy if exists "admin read own record" on public.site_admins;
create policy "admin read own record" on public.site_admins
for select to authenticated using (user_id = auth.uid());

-- Public only sees published achievements; admins can also read drafts.
drop policy if exists "public read published achievements" on public.achievements;
create policy "public read published achievements" on public.achievements
for select using (published = true);

drop policy if exists "admin read all achievements" on public.achievements;
create policy "admin read all achievements" on public.achievements
for select to authenticated using (public.is_site_admin());

drop policy if exists "admin insert achievements" on public.achievements;
create policy "admin insert achievements" on public.achievements
for insert to authenticated with check (public.is_site_admin());

drop policy if exists "admin update achievements" on public.achievements;
create policy "admin update achievements" on public.achievements
for update to authenticated using (public.is_site_admin()) with check (public.is_site_admin());

drop policy if exists "admin delete achievements" on public.achievements;
create policy "admin delete achievements" on public.achievements
for delete to authenticated using (public.is_site_admin());

-- Keep updated_at fresh.
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists site_settings_updated_at on public.site_settings;
create trigger site_settings_updated_at before update on public.site_settings
for each row execute function public.set_updated_at();

drop trigger if exists achievements_updated_at on public.achievements;
create trigger achievements_updated_at before update on public.achievements
for each row execute function public.set_updated_at();

-- Public image bucket for website media.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('site-media', 'site-media', true, 20971520, array['image/jpeg','image/png','image/webp','image/gif','application/pdf','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/vnd.ms-powerpoint','application/vnd.openxmlformats-officedocument.presentationml.presentation','text/plain'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "public read site media" on storage.objects;
create policy "public read site media" on storage.objects
for select using (bucket_id = 'site-media');

drop policy if exists "admin upload site media" on storage.objects;
create policy "admin upload site media" on storage.objects
for insert to authenticated with check (bucket_id = 'site-media' and public.is_site_admin());

drop policy if exists "admin update site media" on storage.objects;
create policy "admin update site media" on storage.objects
for update to authenticated using (bucket_id = 'site-media' and public.is_site_admin()) with check (bucket_id = 'site-media' and public.is_site_admin());

drop policy if exists "admin delete site media" on storage.objects;
create policy "admin delete site media" on storage.objects
for delete to authenticated using (bucket_id = 'site-media' and public.is_site_admin());

-- Initial site data copied from the original HTML.
insert into public.site_settings (id, data)
values (1, $sitejson$
{
  "branding": {
    "logoUrl": ""
  },
  "introPage": {
    "show": true,
    "type": "mourning",
    "image": "https://spacebar.th/_next/image?url=%2Fapi%2Fmedia%2Ffile%2FHer%2520Majesty-the-Queen%2520Mother-has-preserved-works-of-art-as-the-artistic-treasures-of-Thailand-SPACEBAR-Hero.jpg&w=3840&q=75",
    "title": "น้อมรำลึกในพระมหากรุณาธิคุณอันหาที่สุดมิได้",
    "subtitle": "ข้าพระพุทธเจ้า คณะผู้บริหาร คณะครู บุคลากร และสามเณรนักเรียน<br>โรงเรียนวัดหนองแวงวิทยา"
  },
  "announcement": {
    "show": false,
    "text": "แจ้งเตือน: เปิดรับสมัครสามเณรนักเรียนใหม่ ประจำปีการศึกษา 2569 ตั้งแต่วันนี้ - 30 เมษายน 2569 ณ ห้องวิชาการ โรงเรียนวัดหนองแวงวิทยา"
  },
  "info": {
    "nameTh": "โรงเรียนวัดหนองแวงวิทยา",
    "nameEn": "Wat Nongwang Wittaya School",
    "directorName": "พระครูสุธีกิตติวรญาณ",
    "directorImage": "",
    "directorMsg": "เรามุ่งมั่นที่จะสร้างสภาพแวดล้อมแห่งการเรียนรู้ที่ผสมผสานหลักธรรมทางพระพุทธศาสนาเข้ากับวิชาการสมัยใหม่ เปิดโอกาสให้นักเรียนทุกคนได้ค้นพบศักยภาพของตนเองอย่างเต็มที่",
    "phone": "043-123-4567",
    "email": "info@nongwang.ac.th",
    "address": "123 ถนนประชาสโมสร ตำบลในเมือง อำเภอเมือง จังหวัดขอนแก่น 40000",
    "stats": [
      {
        "label": "สามเณรนักเรียน",
        "value": "1,845",
        "icon": "users"
      },
      {
        "label": "บุคลากร",
        "value": "112",
        "icon": "award"
      }
    ]
  },
  "history": {
    "paragraph1": "โรงเรียนวัดหนองแวงวิทยา เป็นโรงเรียนพระปริยัติธรรม แผนกสามัญศึกษา สังกัดสำนักงานพระพุทธศาสนาแห่งชาติ ตั้งอยู่ ณ วัดหนองแวง พระอารามหลวง จังหวัดขอนแก่น ก่อตั้งขึ้นโดยมีวัตถุประสงค์หลักเพื่อให้การศึกษาแก่พระภิกษุสามเณร ทั้งในด้านหลักธรรมคำสอนทางพระพุทธศาสนา ควบคู่ไปกับวิชาการทางโลกตามหลักสูตรแกนกลางการศึกษาขั้นพื้นฐาน",
    "paragraph2": "จากอดีตที่เริ่มต้นจากศาลาการเปรียญเล็กๆ สู่การเป็นสถานศึกษาที่มีอาคารเรียนอันทันสมัย โรงเรียนวัดหนองแวงวิทยาได้ผลิตศาสนทายาทและบุคลากรที่มีคุณภาพออกสู่สังคมอย่างต่อเนื่อง ถือเป็นเสาหลักสำคัญในการสืบทอดพระพุทธศาสนาในภาคตะวันออกเฉียงเหนือ",
    "vision": "\"มุ่งพัฒนาศาสนทายาท ให้เพียบพร้อมด้วยศีลาจารวัตร และเป็นเลิศทางวิชาการ สู่มาตรฐานสากล\"",
    "oldImage": "https://images.unsplash.com/photo-1574345511867-0c7f212f4ba1?q=80&w=1200&auto=format&fit=crop&grayscale=1",
    "newImage": "https://pukmudmuangthai.com/wp-content/uploads/2021/02/%E0%B8%82%E0%B8%AD%E0%B8%99%E0%B9%81%E0%B8%81%E0%B9%88%E0%B8%99-%E0%B8%A7%E0%B8%B1%E0%B8%94%E0%B8%AB%E0%B8%99%E0%B8%AD%E0%B8%87%E0%B9%81%E0%B8%A7%E0%B8%87%E0%B8%9E%E0%B8%A3%E0%B8%B0%E0%B8%AD%E0%B8%B2%E0%B8%A3%E0%B8%B2%E0%B8%A1%E0%B8%AB%E0%B8%A5%E0%B8%A7%E0%B8%87-Medium.jpg"
  },
  "examStats": {
    "naktham": [
      {
        "name": "นักธรรมชั้นตรี",
        "passRate": 95
      },
      {
        "name": "นักธรรมชั้นโท",
        "passRate": 88
      },
      {
        "name": "นักธรรมชั้นเอก",
        "passRate": 82
      }
    ],
    "pali": [
      {
        "name": "ประโยค ๑-๒",
        "passRate": 75
      },
      {
        "name": "เปรียญธรรม ๓ ประโยค",
        "passRate": 60
      },
      {
        "name": "เปรียญธรรม ๔ ประโยค",
        "passRate": 45
      }
    ]
  },
  "donation": {
    "bankName": "ธนาคารกรุงไทย",
    "accNumber": "123-4-56789-0",
    "accName": "ชื่อบัญชี: กองทุนการศึกษา โรงเรียนวัดหนองแวงวิทยา",
    "qrImage": "https://upload.wikimedia.org/wikipedia/commons/d/d0/QR_code_for_mobile_English_Wikipedia.svg"
  },
  "social": {
    "facebook": "https://www.facebook.com/profile.php?id=100063745052570",
    "line": "#",
    "youtube": "#"
  },
  "map": {
    "linkUrl": "https://maps.app.goo.gl/C1YfMnZP2YkvTuoa7",
    "embedIframe": "https://maps.google.com/maps?q=โรงเรียนวัดหนองแวงวิทยา%20ขอนแก่น&t=&z=16&ie=UTF8&iwloc=&output=embed"
  },
  "media": {
    "videoPromo": "https://www.youtube.com/watch?v=YOUR_VIDEO_ID",
    "vrTour": "https://my.matterport.com/show/?m=YOUR_VR_ID"
  },
  "examDate": "2026-02-15T09:00:00",
  "paliWord": {
    "word": "วิริยะ",
    "reading": "วิ-ริ-ยะ",
    "meaning": "ความเพียร, ความพยายาม"
  },
  "promoBanners": [
    "https://img5.pic.in.th/file/secure-sv1/641434808_1513538270780994_4742841130745667713_n.jpg",
    "https://images.unsplash.com/photo-1523050854058-8df90110c9f1?q=80&w=2070&auto=format&fit=crop"
  ],
  "welcomeImage": "https://pukmudmuangthai.com/wp-content/uploads/2021/02/%E0%B8%82%E0%B8%AD%E0%B8%99%E0%B9%81%E0%B8%81%E0%B9%88%E0%B8%99-%E0%B8%A7%E0%B8%B1%E0%B8%94%E0%B8%AB%E0%B8%99%E0%B8%AD%E0%B8%87%E0%B9%81%E0%B8%A7%E0%B8%87%E0%B8%9E%E0%B8%A3%E0%B8%B0%E0%B8%AD%E0%B8%B2%E0%B8%A3%E0%B8%B2%E0%B8%A1%E0%B8%AB%E0%B8%A5%E0%B8%A7%E0%B8%87-Medium.jpg",
  "news": [
    {
      "date": "5",
      "monthYear": "มี.ค. 69",
      "type": "รับสมัคร",
      "typeColor": "bg-red-100 text-red-600",
      "title": "ประกาศรับสมัครนักเรียนใหม่ ประจำปีการศึกษา 2570"
    },
    {
      "date": "1",
      "monthYear": "มี.ค. 69",
      "type": "กิจกรรม",
      "typeColor": "bg-green-100 text-green-600",
      "title": "ขอเชิญร่วมงานนิทรรศการวิชาการ นวัตกรรมล้ำหน้า หนองแวงวิทยาพัฒน์"
    },
    {
      "date": "28",
      "monthYear": "ก.พ. 69",
      "type": "วิชาการ",
      "typeColor": "bg-blue-100 text-blue-600",
      "title": "ประกาศผลการสอบคัดเลือกนักเรียน โครงการห้องเรียนพิเศษ (SMTE)"
    }
  ],
  "events": [
    {
      "date": "15 มีนาคม",
      "title": "วันสถาปนาโรงเรียน",
      "time": "08:00 - 12:00"
    },
    {
      "date": "20-24 กรกฎาคม",
      "title": "สอบกลางภาคเรียนที่ 1",
      "time": "ตลอดวัน"
    }
  ],
  "executives": [
    {
      "name": "พระครูสุธีกิตติวรญาณ",
      "position": "ผู้อำนวยการโรงเรียน",
      "img": "https://ui-avatars.com/api/?name=ผอ&background=fed7aa&color=c2410c&size=200"
    },
    {
      "name": "นายสมเกียรติ รักวิชา",
      "position": "รองผู้อำนวยการ ฝ่ายวิชาการ",
      "img": "https://images.unsplash.com/photo-1560250097-0b93528c311a?q=80&w=200&auto=format&fit=crop"
    },
    {
      "name": "นางสาวศิริพร พูนสุข",
      "position": "รองผู้อำนวยการ ฝ่ายงบประมาณ",
      "img": "https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?q=80&w=200&auto=format&fit=crop"
    },
    {
      "name": "นายธนวัฒน์ พัฒนกิจ",
      "position": "รองผู้อำนวยการ ฝ่ายบริหารทั่วไป",
      "img": "https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?q=80&w=200&auto=format&fit=crop"
    }
  ],
  "teachers": [
    {
      "name": "นางวิภาวี สอนดี",
      "department": "กลุ่มสาระฯ วิทยาศาสตร์",
      "img": "https://images.unsplash.com/photo-1580894732444-8ecded790047?q=80&w=200&auto=format&fit=crop"
    },
    {
      "name": "นายอดิศักดิ์ คิดเร็ว",
      "department": "กลุ่มสาระฯ คณิตศาสตร์",
      "img": "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?q=80&w=200&auto=format&fit=crop"
    },
    {
      "name": "นางพรรณนภา รักไทย",
      "department": "กลุ่มสาระฯ ภาษาไทย",
      "img": "https://images.unsplash.com/photo-1544005313-94ddf0286df2?q=80&w=200&auto=format&fit=crop"
    },
    {
      "name": "นายสุรพล พาทำ",
      "department": "กลุ่มสาระฯ ศิลปะ",
      "img": "https://images.unsplash.com/photo-1519085360753-af0119f7cbe7?q=80&w=200&auto=format&fit=crop"
    }
  ],
  "specialTeachers": [
    {
      "name": "พระมหาสมชาย จิตฺตทนฺโต",
      "department": "ครูสอนภาษาบาลีพิเศษ",
      "img": "https://ui-avatars.com/api/?name=พระ&background=fef08a&color=ca8a04&size=200"
    },
    {
      "name": "Mr. John Smith",
      "department": "ครูพิเศษภาษาอังกฤษ (NES)",
      "img": "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?q=80&w=200&auto=format&fit=crop"
    }
  ],
  "curriculums": [
    {
      "title": "แผนกปริยัติธรรม",
      "subtitle": "นักธรรม / บาลี",
      "desc": "หลักสูตรมุ่งเน้นการศึกษาหลักธรรมคำสอนทางพระพุทธศาสนา เพื่อปลูกฝังคุณธรรมและจริยธรรม ขัดเกลาจิตใจตามวิถีพุทธ",
      "icon": "book",
      "color": "bg-amber-100 text-amber-600"
    },
    {
      "title": "แผนกสามัญ",
      "subtitle": "มัธยมศึกษาตอนต้น และ ตอนปลาย",
      "desc": "หลักสูตรแกนกลางการศึกษาขั้นพื้นฐาน มุ่งเน้นวิชาการควบคู่เทคโนโลยี สู่ความเป็นเลิศในศตวรรษที่ 21 เพื่อการศึกษาต่อระดับอุดมศึกษา",
      "icon": "monitor-play",
      "color": "bg-blue-100 text-blue-600"
    }
  ],
  "achievements": [
    {
      "title": "รางวัลชนะเลิศ การประกวดสวดมนต์หมู่ทำนองสรภัญญะ ระดับภาค",
      "year": "2568",
      "img": "https://images.unsplash.com/photo-1589321599763-888463db8342?q=80&w=400&auto=format&fit=crop"
    },
    {
      "title": "เหรียญทอง การแข่งขันโครงงานวิทยาศาสตร์ งานศิลปหัตถกรรมนักเรียน",
      "year": "2568",
      "img": "https://images.unsplash.com/photo-1564473379204-7431e11440cc?q=80&w=400&auto=format&fit=crop"
    },
    {
      "title": "โรงเรียนส่งเสริมคุณธรรมจริยธรรมดีเด่น ระดับจังหวัด",
      "year": "2567",
      "img": "https://images.unsplash.com/photo-1528605248644-14dd04022da1?q=80&w=400&auto=format&fit=crop"
    },
    {
      "title": "รางวัลเหรียญทองแดง โอลิมปิกวิชาการ สาขาคณิตศาสตร์ระดับชาติ",
      "year": "2567",
      "img": "https://images.unsplash.com/photo-1632516643720-e7f5d7d6eca8?q=80&w=400&auto=format&fit=crop"
    }
  ],
  "documents": [
    {
      "title": "ใบสมัครเข้าศึกษาต่อ ปีการศึกษา 2569",
      "size": "1.2 MB",
      "type": "PDF"
    },
    {
      "title": "คู่มือนักเรียนและผู้ปกครอง",
      "size": "3.5 MB",
      "type": "PDF"
    },
    {
      "title": "ปฏิทินวิชาการ ประจำภาคเรียนที่ 1/2569",
      "size": "0.8 MB",
      "type": "PDF"
    }
  ],
  "environment": {
    "aqi": 24,
    "status": "อากาศดีมาก",
    "temp": 32
  },
  "routines": [
    {
      "time": "04:30 น.",
      "task": "ตื่นนอน ทำวัตรเช้า",
      "icon": "bell"
    },
    {
      "time": "06:00 น.",
      "task": "ออกบิณฑบาต",
      "icon": "sun"
    },
    {
      "time": "08:30 น.",
      "task": "เรียนปริยัติธรรม/สามัญ",
      "icon": "book-open"
    },
    {
      "time": "16:00 น.",
      "task": "ทำความสะอาดบริเวณวัด",
      "icon": "leaf"
    },
    {
      "time": "18:00 น.",
      "task": "ทำวัตรเย็น นั่งสมาธิ",
      "icon": "moon"
    }
  ],
  "dhammaQuote": {
    "pali": "นตฺถิ ปญฺญาสมา อาภา",
    "thai": "แสงสว่างเสมอด้วยปัญญา ไม่มี"
  },
  "quickLinks": [
    {
      "icon": "users",
      "label": "ระบบสารสนเทศ",
      "bg": "bg-orange-100",
      "text": "text-orange-600",
      "url": "#"
    },
    {
      "icon": "book-open",
      "label": "E-Learning",
      "bg": "bg-orange-100",
      "text": "text-orange-600",
      "url": "#"
    },
    {
      "icon": "graduation-cap",
      "label": "รับสมัครนักเรียน",
      "bg": "bg-orange-500",
      "text": "text-white",
      "url": "https://sites.google.com/view/wnwvit/home"
    }
  ]
}
$sitejson$::jsonb)
on conflict (id) do nothing;

-- Initial achievements. Safe to run once on a fresh project.
insert into public.achievements (title, year, image_url, description, published, created_at)
select * from (values
  ('รางวัลชนะเลิศ การประกวดสวดมนต์หมู่ทำนองสรภัญญะ ระดับภาค', '2568', 'https://images.unsplash.com/photo-1589321599763-888463db8342?q=80&w=400&auto=format&fit=crop', '', true, now() - interval '0 seconds'),
  ('เหรียญทอง การแข่งขันโครงงานวิทยาศาสตร์ งานศิลปหัตถกรรมนักเรียน', '2568', 'https://images.unsplash.com/photo-1564473379204-7431e11440cc?q=80&w=400&auto=format&fit=crop', '', true, now() - interval '1 seconds'),
  ('โรงเรียนส่งเสริมคุณธรรมจริยธรรมดีเด่น ระดับจังหวัด', '2567', 'https://images.unsplash.com/photo-1528605248644-14dd04022da1?q=80&w=400&auto=format&fit=crop', '', true, now() - interval '2 seconds'),
  ('รางวัลเหรียญทองแดง โอลิมปิกวิชาการ สาขาคณิตศาสตร์ระดับชาติ', '2567', 'https://images.unsplash.com/photo-1632516643720-e7f5d7d6eca8?q=80&w=400&auto=format&fit=crop', '', true, now() - interval '3 seconds')
) as v(title, year, image_url, description, published, created_at)
where not exists (select 1 from public.achievements);

-- ============================================================
-- AUTHENTICATION-FIRST ADMIN MODE
-- ============================================================
-- No manual insert into site_admins is required.
-- Every non-anonymous account created in:
--   Supabase Dashboard > Authentication > Users
-- can sign in to /manager/ and receives Website Manager permissions.
--
-- IMPORTANT SECURITY SETTINGS in Authentication > General Configuration:
--   1) Disable "Allow new users to sign up"
--   2) Disable anonymous sign-ins
-- This keeps manager account creation under the Supabase project owner's control.
--
-- The site_admins table is retained only for backward compatibility and can be
-- ignored by this version.
-- ============================================================


-- ============================================================
-- DEDICATED PERSONNEL TABLE (included for fresh installations)
-- ============================================================
-- ============================================================
-- Supabase Upgrade: Dedicated Personnel / บุคลากร
-- Wat Nongwang Wittaya School
-- Run in Supabase > SQL Editor. Safe to run again.
-- ============================================================

create or replace function public.is_site_admin()
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select auth.uid() is not null
     and coalesce((auth.jwt()->>'is_anonymous')::boolean, false) = false;
$$;

revoke all on function public.is_site_admin() from public;
grant execute on function public.is_site_admin() to authenticated;

create table if not exists public.personnel (
  id uuid primary key default gen_random_uuid(),
  staff_type text not null check (staff_type in ('executives','teachers','specialTeachers')),
  full_name text not null,
  position text not null default '',
  department text not null default '',
  image_url text not null default '',
  education text not null default '',
  phone text not null default '',
  email text not null default '',
  is_alumni boolean not null default false,
  alumni_batch text not null default '',
  published boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default auth.uid()
);

create index if not exists personnel_public_order_idx
  on public.personnel (published, staff_type, sort_order, created_at);
create index if not exists personnel_alumni_idx
  on public.personnel (is_alumni, alumni_batch);

alter table public.personnel enable row level security;

drop policy if exists "public read published personnel" on public.personnel;
create policy "public read published personnel" on public.personnel
for select using (published = true);

drop policy if exists "admin read all personnel" on public.personnel;
create policy "admin read all personnel" on public.personnel
for select to authenticated using (public.is_site_admin());

drop policy if exists "admin insert personnel" on public.personnel;
create policy "admin insert personnel" on public.personnel
for insert to authenticated with check (public.is_site_admin());

drop policy if exists "admin update personnel" on public.personnel;
create policy "admin update personnel" on public.personnel
for update to authenticated using (public.is_site_admin()) with check (public.is_site_admin());

drop policy if exists "admin delete personnel" on public.personnel;
create policy "admin delete personnel" on public.personnel
for delete to authenticated using (public.is_site_admin());

grant select on public.personnel to anon, authenticated;
grant insert, update, delete on public.personnel to authenticated;

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists personnel_updated_at on public.personnel;
create trigger personnel_updated_at before update on public.personnel
for each row execute function public.set_updated_at();

-- Migrate legacy personnel arrays from site_settings only when the new table is empty.
-- The old JSON is intentionally left untouched as a rollback copy; the upgraded app
-- reads/writes personnel from public.personnel and no longer saves duplicate staff JSON.
do $$
begin
  if not exists (select 1 from public.personnel limit 1) then
    insert into public.personnel (
      staff_type, full_name, position, department, image_url,
      education, phone, email, is_alumni, alumni_batch,
      published, sort_order
    )
    select
      src.staff_type,
      coalesce(nullif(src.item->>'name',''), 'ไม่ระบุชื่อ'),
      coalesce(src.item->>'position',''),
      coalesce(src.item->>'department',''),
      coalesce(src.item->>'img',''),
      coalesce(src.item->>'education',''),
      coalesce(src.item->>'phone',''),
      coalesce(src.item->>'email',''),
      case when lower(coalesce(src.item->>'isAlumni','false')) in ('true','1','yes','on') then true else false end,
      coalesce(src.item->>'alumniBatch',''),
      case when lower(coalesce(src.item->>'published','true')) in ('false','0','no','off') then false else true end,
      ((src.ord - 1)::integer) * 10
    from public.site_settings s
    cross join lateral (
      select 'executives'::text as staff_type, e.item, e.ord
      from jsonb_array_elements(coalesce(s.data->'executives','[]'::jsonb)) with ordinality as e(item,ord)
      union all
      select 'teachers'::text as staff_type, t.item, t.ord
      from jsonb_array_elements(coalesce(s.data->'teachers','[]'::jsonb)) with ordinality as t(item,ord)
      union all
      select 'specialTeachers'::text as staff_type, sp.item, sp.ord
      from jsonb_array_elements(coalesce(s.data->'specialTeachers','[]'::jsonb)) with ordinality as sp(item,ord)
    ) src
    where s.id = 1;
  end if;
end $$;

comment on table public.personnel is
'Dedicated personnel directory. Website and Manager read/write this table directly; public can read published rows only.';
