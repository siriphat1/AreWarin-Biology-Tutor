# Tutor OS migration map

The uploaded legacy Tutor OS was not embedded verbatim because it contained multiple overlapping launchers/modules and referenced a different data model. The new V14 subweb keeps the workflow categories but maps them to the current AreWarin system.

| Legacy functional area | V14 destination |
|---|---|
| Overview / Unified Command Center | `/tutor-os/?section=overview` |
| Student records / Enrollment | Tutor OS Students + core `enrollments` sync |
| CRM / Parent | `os_crm_contacts` |
| Student Portal / Attendance | Portal Preview + `os_attendance_*` |
| Course core | existing `courses` table + Manager deep link |
| Registration / Admissions | existing Manager Enrollment |
| Schedule / Capacity | existing Dynamic Tutor Schedule in Manager |
| Package / Discount | existing `course_prices` + `promotions` |
| Teaching logs | `os_teaching_logs` |
| Learning playback/content | `os_learning_topics/assets/assignments` |
| Tasks | `os_tasks` |
| Announcements | `os_announcements` |
| Finance / payments | core `payments` + `os_finance_entries` |
| Tutors | core `tutors` |
| Team library | `os_library_items` |
| HR | `os_hr_entries` (Admin only) |
| Tutor recruitment | existing `tutor_applications` + Manager |
| Speaker requests | existing `speaker_requests` + Manager |
| Reports | Tutor OS analytics + CSV export |
| Import / quick replies | `os_crm_contacts`, `os_quick_replies` |
| User permissions | `os_staff_profiles` + Supabase Auth/RLS |

The design goal is one shared lifecycle, not separate copies of the same core records.
