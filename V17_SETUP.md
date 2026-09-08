# AreWarin Unified System V17 — Control + Automation

V17 builds on V16 and integrates the former Student Services subweb into the main Manager/Tutor OS.

## Install
1. Run `supabase/V17_CONTROL_AUTOMATION_UPGRADE.sql` after the existing V16 upgrade.
2. Upload the changed `manager/`, `student/`, `tutor-os/`, and `parent/` folders.
3. Hard refresh.

## New Manager modules
- Operations Center / Action Center
- Student 360°
- Finance Aging
- Universal Search (`Ctrl/Cmd + K`)
- System Health
- Audit Log
- Role Permission Matrix
- Integrated Student Services
- Group Broadcast
- Tutor Applicant Pipeline

## Student V17
- Course Wallet
- Request Center
- Group broadcasts through V17 bootstrap
- Existing V16 schedule/homework/payment/parent/support/security/PWA preserved

## Tutor OS V17
- Today Teaching
- Student Services integrated into main Tutor OS
- Old `/student-services/` URLs redirect to the integrated sections.
