# AreWarin Biology · V14 Tutor OS Integration

V14 integrates the uploaded Tutor OS concept into the current AreWarin Biology GitHub + Supabase system as a real staff-only subweb at `/tutor-os/` while keeping the existing enrollment site, Manager, Reviews, Tutor Application, Policy CMS, receipt/payment flows, and tutor-specific schedules intact.

## What changed in V14

### New `/tutor-os/` subweb
- Unified dashboard / operations overview
- Students + operational student records synced from the main `enrollments`
- CRM + guardian contacts + follow-up date
- Student Portal preview
- Courses using the same Course UUIDs as Manager
- Course requests workflow
- Attendance sessions and per-student status: present / late / absent / leave
- Teaching logs and lesson hours
- Learning topics + video/file/link/sheet resources
- Tasks and team announcements
- Shared tutor schedule viewer linked to Manager schedule editing
- Finance dashboard for Admin using main payments + Tutor OS ledger
- Tutors overview
- Staff permissions (`teacher` / `admin`)
- Team Library
- HR records for Admin
- Tutor recruitment and speaker-request summaries linked to Manager
- Reports + CSV export
- Quick Replies
- CRM CSV import + template
- System health / connected-app shortcuts

### Connected data model
Main transactional/catalog data remains the single source of truth:
- `tutors`
- `courses`
- `enrollments`
- `payments`
- `tutor_schedules`
- `schedule_templates`
- `tutor_applications`
- `speaker_requests`

Tutor OS adds only operational extension tables prefixed `os_`. Database triggers sync main Enrollment and Payment changes into Tutor OS student/course/finance records.

### Manager integration
`/manager/` now has Tutor OS links in:
- top bar
- sidebar
- dashboard hero

Manager supports `?section=...` deep links, so Tutor OS can jump directly to Course, Tutor, Enrollment, Schedule, Payment, Policy, and Tutor Application screens.

### Security
- Uses the same Supabase Auth session as the main system.
- Existing Manager/Admin profiles are automatically bridged to `os_staff_profiles` as Tutor OS `admin`.
- Tutor accounts can be granted `teacher` access by UID from Tutor OS → Team → Staff & สิทธิ์.
- Finance, HR, Staff permission changes, permanent student deletion, and sensitive core workflow records are protected by database RLS for Tutor OS Admin.
- Teachers can work with Student operations, CRM, Attendance, Teaching, Learning, Tasks, Announcements, Library, and Course Requests.

## Supabase project already in use

This package is configured for the current AreWarin Supabase project through the shared root `config.js`.

For an **existing V13 project**, run **one SQL file** in Supabase → SQL Editor:

```text
supabase/V14_EXISTING_PROJECT_UPGRADE.sql
```

The SQL is designed to be re-runnable and will:
- create the Tutor OS operational schema
- sync current Manager/Admin accounts
- backfill existing enrollments and payments
- create sync triggers for future records
- install RLS
- create private `tutor-os-assets` storage bucket

Then logout/login once and open:

```text
https://YOUR_GITHUB_PAGES/tutor-os/
```

## Brand-new Supabase project

Use this cumulative SQL instead:

```text
supabase/AREWARIN_FULL_SETUP_V14.sql
```

Do **not** run both Full Setup and V14 Upgrade on a fresh database unless you specifically want to rerun the idempotent upgrade.

## Edge Functions

Tutor OS itself does not require a new Edge Function. Existing public forms still use:

```bash
supabase link --project-ref ihmiqtwclnqrezsnswfz
supabase functions deploy create-enrollment --no-verify-jwt
supabase functions deploy get-receipt --no-verify-jwt
supabase functions deploy submit-tutor-application --no-verify-jwt
```

The Tutor Application CORS fix is included in this package. `supabase/config.toml` has `verify_jwt = false` for all three public functions.

## Structure

```text
arewarin-tutor-os-v14/
├── index.html                  # Main enrollment / renewal site
├── config.js                   # Shared Supabase config
├── js/
├── manager/                    # Main Manager + Tutor OS entry points
├── reviews/
├── tutor-apply/                # TH/EN tutor recruitment + CORS-safe submit
├── tutor-os/                   # NEW unified staff subweb
│   ├── index.html
│   ├── styles.css
│   ├── app.js
│   └── staff/index.html
├── templates/
└── supabase/
    ├── V14_EXISTING_PROJECT_UPGRADE.sql
    ├── TUTOR_OS_V14_UPGRADE.sql
    ├── AREWARIN_FULL_SETUP_V14.sql
    ├── config.toml
    └── functions/
```

## Staff access

For the current Manager/Admin user, simply run the V14 SQL and sign in with the same Manager credentials.

For a new Tutor/Teacher account:
1. Supabase → Authentication → Add user.
2. Copy that Auth user UID.
3. Sign in as Tutor OS Admin.
4. Team & เนื้อหา → Staff & สิทธิ์ → ให้สิทธิ์.
5. Paste UID and choose `teacher`.

Do not put a Supabase service-role/secret key into any frontend file.

## Source-code adaptation note

The supplied Tutor OS source combined multiple generations/modules in one large HTML application. V14 keeps its functional areas, but remaps them to the current AreWarin schema instead of connecting the old source directly to its former database. This avoids maintaining duplicate student/course/tutor records and makes Manager + Enrollment + Tutor OS operate against one Supabase project.
