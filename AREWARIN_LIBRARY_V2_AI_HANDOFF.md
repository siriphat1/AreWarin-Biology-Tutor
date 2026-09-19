# AreWarin Library V2 COMPLETE NO-TS — AI / Developer Handoff

## Goal
Maintain a private digital library for AreWarin students, tutors/staff and managers/admins without adding a Library TypeScript Edge Function.

## Files to understand first
- `library/index.html` — all Library frontend, reader and Library Studio UI.
- `supabase/AREWARIN_LIBRARY_V2_COMPLETE_NO_TS.sql` — cumulative database schema, RPCs, RLS and Storage policies.
- `library/arewarin-library-import-template-v2.xlsx` — Excel bulk-import contract.
- `manager/index.html` — latest Manager with a link to `/library/?admin=1`.

## Existing external dependencies
- `/config.js` provides only `SUPABASE_URL` + `SUPABASE_ANON_KEY`.
- Existing Supabase Auth accounts are shared with AreWarin.
- Existing `student-auth` function from Student Hub is reused only when a student profile exists but needs an auth account. Do not create a new Library Edge Function just for this.

## Critical security rules
1. NEVER place `SUPABASE_SERVICE_ROLE_KEY` in browser code.
2. `library-books` MUST remain a private Storage bucket.
3. Keep `library_user_can_access_item(uid,item_id)` as the canonical access decision.
4. Keep Storage SELECT protected by `library_can_read_path(auth.uid(),name)`.
5. Course-restricted books must require at least one matching `os_student_course_enrollments.course_id` for students.
6. Staff/admin may bypass student course gating according to current SQL.
7. “No download” is a deterrent, not DRM: a short signed URL is still visible to a technically capable authenticated user in browser networking tools.

## Main tables
- `library_settings`
- `library_categories` (`parent_id` supports category tree)
- `library_items`
- `library_collections`
- `library_collection_items`
- `library_item_courses`
- `library_favorites`
- `library_pins`
- `library_reading_progress`
- `library_bookmarks`
- `library_notes`
- `library_book_requests`
- `library_new_seen`
- `library_sessions`
- `library_access_log`
- `library_audit_log`

## User-facing RPCs
- `library_whoami()`
- `library_session_touch(session_key, device_label)`
- `library_home()`
- `library_mark_new_seen()`
- `library_item_detail(item_id)`
- `library_toggle_favorite(item_id)`
- `library_toggle_pin(item_id)`
- `library_progress_save(item_id,last_page,total_pages)`
- `library_toggle_bookmark(item_id,page,label)`
- `library_reader_state(item_id)`
- `library_note_save(...)`
- `library_note_delete(note_id)`
- `library_request_book(...)`
- `library_open_item(item_id)`
- `library_can_read_path(uid,path)`

## Admin RPCs
- `library_admin_bootstrap_v2()`
- `library_admin_duplicate_check(...)`
- `library_admin_save_item(jsonb)`
- `library_admin_save_category(jsonb)`
- `library_admin_save_collection(jsonb)`
- `library_admin_bulk_action(item_ids,action,value)`
- `library_admin_bulk_upsert_v2(rows)`
- `library_admin_request_update(...)`
- `library_admin_settings_save(jsonb)`

## Frontend sections
Student/staff library home contains:
- Continue Reading
- Recently Viewed
- My Shelf (favorite + pin)
- Collections
- NEW
- My Course
- Recommended/Featured
- Popular
- Search + category + collection + author + year filters

Reader includes:
- PDF.js canvas renderer
- private short-lived signed URL
- outline/TOC
- bookmarks
- notes
- jump page
- zoom
- fit width/page
- light/dark/sepia
- fullscreen
- dynamic watermark
- saved progress

Library Studio contains:
- Dashboard KPIs
- Books + Live Preview
- category tree
- collections
- Excel preview/import
- book requests
- cover library
- audit log
- settings
- bulk actions + soft delete/restore

## Excel contract
Columns are defined in the V2 template. `collection_codes` and `course_names` are comma-separated. PDF and cover filenames must exactly match selected upload files.

## Safe future enhancements
If stronger anti-copy controls are required, do NOT expose service_role in browser. Move reading delivery to a server/Worker that renders PDF pages to images/tiles, while preserving this database access model.
