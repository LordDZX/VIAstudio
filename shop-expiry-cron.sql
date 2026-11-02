-- Run after shop-layout-guard.sql and after adding the Vault secrets described in README.md.
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

do $$
begin
  if not exists (select 1 from vault.decrypted_secrets where name = 'project_url')
     or not exists (select 1 from vault.decrypted_secrets where name = 'publishable_key')
     or not exists (select 1 from vault.decrypted_secrets where name = 'expire_shops_cron_secret') then
    raise exception 'Add project_url, publishable_key, and expire_shops_cron_secret to Supabase Vault first.';
  end if;
end $$;

select cron.unschedule(jobid)
from cron.job
where jobname = 'market-shop-expiry-cleanup';

select cron.schedule(
  'market-shop-expiry-cleanup',
  '* * * * *',
  $job$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
             || '/functions/v1/expire-shops',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'publishable_key'),
        'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'expire_shops_cron_secret')
      ),
      body := '{}'::jsonb
    );
  $job$
);

select cron.unschedule(jobid)
from cron.job
where jobname = 'cleanup-old-cron-history';

select cron.schedule(
  'cleanup-old-cron-history',
  '17 3 * * *',
  $job$
    delete from cron.job_run_details
    where end_time < now() - interval '30 days';
  $job$
);
