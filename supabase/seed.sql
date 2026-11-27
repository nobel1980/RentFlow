-- RentFlow Production Storage Policy & pg_cron Reference Script
-- Run after applying migrations 0001..0012 on a Supabase PostgreSQL instance.
-- Storage policies use public.can_access_agreement_document(name) from migration 0012
-- to enforce '{owner_account_id}/{agreement_id}/{filename}' isolation.

do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'storage' and table_name = 'buckets') then
    insert into storage.buckets (id, name, public)
    values ('agreements', 'agreements', false),
           ('receipts', 'receipts', false)
    on conflict (id) do update set public = false;
  end if;
end;
$$;
