-- Upgrade for the no-code Website Manager
-- Run once in Supabase > SQL Editor if the project was installed from an older package.
-- Expands the existing public site-media bucket so managers can upload common document files, not only images.

update storage.buckets
set file_size_limit = 20971520,
    allowed_mime_types = array[
      'image/jpeg','image/png','image/webp','image/gif',
      'application/pdf',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.ms-excel',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.ms-powerpoint',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'text/plain'
    ]
where id = 'site-media';
