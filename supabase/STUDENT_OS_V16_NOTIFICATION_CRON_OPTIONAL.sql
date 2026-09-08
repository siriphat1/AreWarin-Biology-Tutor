-- Optional: automatic V16 notifications every hour.
-- Run only if Supabase Cron / pg_cron is available in your project.
create extension if not exists pg_cron;
select cron.unschedule(jobid) from cron.job where jobname='arewarin-student-v16-notifications';
select cron.schedule('arewarin-student-v16-notifications','0 * * * *',$$select public.student_v16_notification_sweep_worker();$$);
