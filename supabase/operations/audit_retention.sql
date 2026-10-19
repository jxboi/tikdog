-- Run once per hosted project as its database owner. Safe to reapply.
create extension if not exists pg_cron;

select cron.schedule(
  'tikdog-audit-retention',
  '0 3 * * *',
  $$delete from public.moderation_actions where created_at < now() - interval '90 days'$$
);

select jobid, jobname, schedule, active, command
from cron.job
where jobname = 'tikdog-audit-retention';
