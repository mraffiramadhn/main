-- Enable Supabase Cron scheduler (used for weekly Treasury automations)
create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;
