-- Run in Supabase SQL Editor. Auth providers / Anonymous Sign-ins must also be enabled in Auth settings.
-- Social OAuth client secrets stay in Supabase Dashboard, never in index.html.

create table if not exists public.market_shops (
  id text primary key,
  owner_id uuid references auth.users(id),
  payload jsonb not null,
  expire_at timestamptz,
  cleanup_started_at timestamptz
);
alter table public.market_shops add column if not exists owner_id uuid references auth.users(id);
alter table public.market_shops add column if not exists expire_at timestamptz;
alter table public.market_shops add column if not exists cleanup_started_at timestamptz;

-- Query and storage safeguards (same definitions as traffic-protection.sql).
create index if not exists market_shops_expire_at_idx
  on public.market_shops (expire_at)
  where expire_at is not null;

create or replace function public.market_shop_uploaded_image_count(p_payload jsonb)
returns integer language sql immutable set search_path = public as $$
  select (
    select count(*)::integer
    from jsonb_array_elements(case when jsonb_typeof(p_payload->'products') = 'array' then p_payload->'products' else '[]'::jsonb end) as products(product)
    cross join lateral jsonb_array_elements(case when jsonb_typeof(product->'media') = 'array' then product->'media' else '[]'::jsonb end) as media_items(media)
    where media->>'mediaKey' is not null
      and coalesce(media->>'publicURL', '') like '%/storage/v1/object/public/market-media/%'
  ) + (
    select count(*)::integer
    from jsonb_array_elements(case when jsonb_typeof(p_payload->'products') = 'array' then p_payload->'products' else '[]'::jsonb end) as products(product)
    where case when jsonb_typeof(product->'media') = 'array' then jsonb_array_length(product->'media') = 0 else true end
      and product->>'mediaKey' is not null
      and coalesce(product->>'publicURL', '') like '%/storage/v1/object/public/market-media/%'
  );
$$;

create or replace function public.enforce_market_shop_image_limit()
returns trigger language plpgsql set search_path = public as $$
declare new_count integer; old_count integer := 0;
begin
  new_count := public.market_shop_uploaded_image_count(new.payload);
  if tg_op = 'UPDATE' then old_count := public.market_shop_uploaded_image_count(old.payload); end if;
  if new_count > 5 and new_count > old_count then
    raise exception 'MARKET_SHOP_IMAGE_LIMIT: a shop may store at most five uploaded images' using errcode = '23514';
  end if;
  return new;
end; $$;
drop trigger if exists market_shops_image_limit on public.market_shops;
create trigger market_shops_image_limit before insert or update of payload on public.market_shops
for each row execute function public.enforce_market_shop_image_limit();

-- Serialize storefront placement writes and reject overlapping active buildings.
create or replace function public.enforce_market_shop_non_overlap()
returns trigger language plpgsql security definer set search_path = public as $$
declare px numeric; py numeric; idx integer; candidate_x numeric; candidate_y numeric; found_slot boolean := false; grid_x integer; grid_y integer;
begin
  if coalesce((new.payload->>'destroyed')::boolean, false) then return new; end if;
  perform pg_advisory_xact_lock(73191, 1);
  if jsonb_typeof(new.payload->'position') is distinct from 'object'
     or coalesce(new.payload#>>'{position,x}', '') !~ '^-?[0-9]+([.][0-9]+)?$'
     or coalesce(new.payload#>>'{position,y}', '') !~ '^-?[0-9]+([.][0-9]+)?$' then
    if new.id = 'thread' then idx := 0;
    elsif new.id = 'plant' then idx := 1;
    elsif new.id = 'film' then idx := 2;
    elsif new.id = 'bake' then idx := 3;
    elsif new.id = 'ceramic' then idx := 4;
    elsif new.id = 'paper' then idx := 5;
    elsif new.id ~ '^district-[0-9]+$' then idx := substring(new.id from 'district-([0-9]+)')::integer;
    else idx := null;
    end if;
    if idx is not null and idx < 24 then
      candidate_x := 180 + (idx % 6) * 700;
      candidate_y := 230 + (idx / 6) * 620;
    else
      for grid_y in 0..9 loop
        candidate_y := 170 + grid_y * 300;
        for grid_x in 0..32 loop
          candidate_x := -2400 + grid_x * 300;
          if not exists (
            select 1 from public.market_shops m
            where m.id <> new.id and not coalesce((m.payload->>'destroyed')::boolean, false)
              and coalesce(m.payload#>>'{position,x}', '') ~ '^-?[0-9]+([.][0-9]+)?$'
              and coalesce(m.payload#>>'{position,y}', '') ~ '^-?[0-9]+([.][0-9]+)?$'
              and (m.payload#>>'{position,x}')::numeric - 20 < candidate_x + 240
              and (m.payload#>>'{position,x}')::numeric + 240 > candidate_x - 20
              and (m.payload#>>'{position,y}')::numeric - 20 < candidate_y + 240
              and (m.payload#>>'{position,y}')::numeric + 240 > candidate_y - 20
          ) then found_slot := true; exit; end if;
        end loop;
        if found_slot then exit; end if;
      end loop;
      if not found_slot then raise exception 'No free storefront position' using errcode = '23514'; end if;
    end if;
    new.payload := jsonb_set(new.payload, '{position}', jsonb_build_object('x', candidate_x, 'y', candidate_y), true);
  end if;
  px := (new.payload#>>'{position,x}')::numeric;
  py := (new.payload#>>'{position,y}')::numeric;
  if px < -2420 or px > 7533.333333 or py < 170 or py > 3060 then
    raise exception 'Storefront position outside map bounds' using errcode = '23514';
  end if;
  if exists (
    select 1 from public.market_shops m
    where m.id <> new.id and not coalesce((m.payload->>'destroyed')::boolean, false)
      and coalesce(m.payload#>>'{position,x}', '') ~ '^-?[0-9]+([.][0-9]+)?$'
      and coalesce(m.payload#>>'{position,y}', '') ~ '^-?[0-9]+([.][0-9]+)?$'
      and (m.payload#>>'{position,x}')::numeric - 20 < px + 240
      and (m.payload#>>'{position,x}')::numeric + 240 > px - 20
      and (m.payload#>>'{position,y}')::numeric - 20 < py + 240
      and (m.payload#>>'{position,y}')::numeric + 240 > py - 20
  ) then raise exception 'MARKET_SHOP_OVERLAP: buildings and shops cannot overlap' using errcode = '23514'; end if;
  return new;
end; $$;
drop trigger if exists market_shops_no_overlap on public.market_shops;
drop trigger if exists market_shops_no_overlap_insert on public.market_shops;
drop trigger if exists market_shops_no_overlap_position_update on public.market_shops;
create trigger market_shops_no_overlap_insert before insert on public.market_shops
for each row execute function public.enforce_market_shop_non_overlap();
create trigger market_shops_no_overlap_position_update before update of payload on public.market_shops
for each row when ((old.payload -> 'position') is distinct from (new.payload -> 'position'))
execute function public.enforce_market_shop_non_overlap();
alter table public.market_shops enable row level security;
drop policy if exists "prototype public shop read" on public.market_shops;
drop policy if exists "prototype public shop write" on public.market_shops;
drop policy if exists "shops are public" on public.market_shops;
drop policy if exists "owners insert shops" on public.market_shops;
drop policy if exists "owners update shops" on public.market_shops;
create policy "shops are public" on public.market_shops for select to anon, authenticated using (true);
create policy "owners insert shops" on public.market_shops for insert to authenticated
  with check (owner_id = (select auth.uid()) and payload #>> '{lease,ownerId}' = (select auth.uid())::text and coalesce((select auth.jwt()->>'is_anonymous')::boolean, true) = false);
create policy "owners update shops" on public.market_shops for update to authenticated
  using ((owner_id is null or owner_id = (select auth.uid()) or expire_at <= now()) and coalesce((select auth.jwt()->>'is_anonymous')::boolean, true) = false)
  with check (coalesce((select auth.jwt()->>'is_anonymous')::boolean, true) = false and ((owner_id = (select auth.uid()) and payload #>> '{lease,ownerId}' = (select auth.uid())::text) or (owner_id is null and payload->'lease' = 'null'::jsonb)));

-- Private one-to-one messages. Old prototype messages are intentionally not imported.
create table if not exists public.account_messages (
  id bigint generated always as identity primary key,
  conversation_id text not null,
  shop_id text not null references public.market_shops(id),
  sender_id uuid not null references auth.users(id),
  recipient_id uuid not null references auth.users(id),
  sender_name text not null,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now(),
  check (sender_id <> recipient_id)
);
create index if not exists account_messages_conversation_created_idx on public.account_messages (conversation_id, created_at);
alter table public.account_messages enable row level security;
drop policy if exists "prototype public dm read" on public.account_messages;
drop policy if exists "prototype public dm insert" on public.account_messages;
drop policy if exists "participants read their messages" on public.account_messages;
drop policy if exists "sender inserts own messages" on public.account_messages;
create policy "participants read their messages" on public.account_messages for select to authenticated
  using ((select auth.uid()) = sender_id or (select auth.uid()) = recipient_id);
create policy "sender inserts own messages" on public.account_messages for insert to authenticated
  with check ((select auth.uid()) = sender_id and sender_id <> recipient_id and exists (select 1 from public.market_shops where id = shop_id and owner_id in (sender_id, recipient_id)) and conversation_id = (shop_id || ':' || least(sender_id::text, recipient_id::text) || ':' || greatest(sender_id::text, recipient_id::text)));

-- Atomic shared equipment locks. A lock is renewed while the rider stays and expires after disconnect.
create table if not exists public.park_sessions (
  facility_id text primary key,
  user_id uuid not null references auth.users(id),
  session_id text not null,
  expires_at timestamptz not null
);
alter table public.park_sessions enable row level security;
drop policy if exists "park occupancy is public" on public.park_sessions;
create policy "park occupancy is public" on public.park_sessions for select to anon, authenticated using (true);
create or replace function public.claim_park_facility(p_facility_id text, p_session_id text)
returns boolean language plpgsql security definer set search_path = public as $$
declare claimed_count integer;
begin
  if auth.uid() is null or p_session_id not like auth.uid()::text || ':%' then return false; end if;
  insert into public.park_sessions(facility_id,user_id,session_id,expires_at)
  values(p_facility_id,auth.uid(),p_session_id,now()+interval '15 seconds')
  on conflict(facility_id) do update set user_id=excluded.user_id, session_id=excluded.session_id, expires_at=excluded.expires_at
  where public.park_sessions.expires_at < now() or public.park_sessions.session_id = p_session_id;
  get diagnostics claimed_count = row_count;
  return claimed_count = 1;
end; $$;
create or replace function public.renew_park_facility(p_facility_id text, p_session_id text)
returns boolean language plpgsql security definer set search_path = public as $$
declare renewed_count integer;
begin
  if auth.uid() is null or p_session_id not like auth.uid()::text || ':%' then return false; end if;
  update public.park_sessions set expires_at=now()+interval '15 seconds'
    where facility_id=p_facility_id and user_id=auth.uid() and session_id=p_session_id;
  get diagnostics renewed_count = row_count;
  return renewed_count = 1;
end; $$;
create or replace function public.release_park_facility(p_facility_id text, p_session_id text)
returns void language sql security definer set search_path = public as $$
  delete from public.park_sessions where facility_id=p_facility_id and user_id=auth.uid() and session_id=p_session_id;
$$;
revoke all on function public.claim_park_facility(text,text) from public;
revoke all on function public.renew_park_facility(text,text) from public;
revoke all on function public.release_park_facility(text,text) from public;
grant execute on function public.claim_park_facility(text,text) to authenticated;
grant execute on function public.renew_park_facility(text,text) to authenticated;
grant execute on function public.release_park_facility(text,text) to authenticated;

-- Public read for display; only a signed-in user's own Storage folder may be written.
insert into storage.buckets (id,name,public) values ('market-media','market-media',true)
on conflict (id) do update set public=true;
drop policy if exists "prototype market media upload" on storage.objects;
drop policy if exists "prototype market media public read" on storage.objects;
drop policy if exists "market media public read" on storage.objects;
drop policy if exists "owners upload market media" on storage.objects;
drop policy if exists "owners update market media" on storage.objects;
drop policy if exists "owners delete market media" on storage.objects;
create policy "market media public read" on storage.objects for select to anon,authenticated using (bucket_id='market-media');
create policy "owners upload market media" on storage.objects for insert to authenticated
  with check (bucket_id='market-media' and (storage.foldername(name))[1]=(select auth.uid())::text and coalesce((select auth.jwt()->>'is_anonymous')::boolean,true)=false);
create policy "owners update market media" on storage.objects for update to authenticated
  using (bucket_id='market-media' and (storage.foldername(name))[1]=(select auth.uid())::text and coalesce((select auth.jwt()->>'is_anonymous')::boolean,true)=false)
  with check (bucket_id='market-media' and (storage.foldername(name))[1]=(select auth.uid())::text and coalesce((select auth.jwt()->>'is_anonymous')::boolean,true)=false);
create policy "owners delete market media" on storage.objects for delete to authenticated
  using (bucket_id='market-media' and (storage.foldername(name))[1]=(select auth.uid())::text and coalesce((select auth.jwt()->>'is_anonymous')::boolean,true)=false);

-- Add required tables to Realtime publication idempotently.
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='account_messages') then
    alter publication supabase_realtime add table public.account_messages;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='park_sessions') then
    alter publication supabase_realtime add table public.park_sessions;
  end if;
end $$;


-- Retire the prototype chat table's anonymous read/write exposure; the game now uses account_messages.
DO $$ BEGIN
  if to_regclass('public.private_messages') is not null then
    execute 'alter table public.private_messages enable row level security';
    execute 'drop policy if exists "prototype public dm read" on public.private_messages';
    execute 'drop policy if exists "prototype public dm insert" on public.private_messages';
    execute 'revoke all on table public.private_messages from anon, authenticated';
  end if;
END $$;

-- Reset only the old built-in showcase NPC leases. Other user-created store data is left untouched.
update public.market_shops
set owner_id = null,
    expire_at = null,
    payload = payload || jsonb_build_object(
      'owner', '', 'tagline', '等待一位喜歡這裡的新店主。', 'contact', '', 'about', '',
      'products', '[]'::jsonb, 'lease', null, 'cloudOwnerId', null
    )
where payload #>> '{lease,ownerId}' like 'showcase-%'
   or payload #>> '{lease,provider}' = '示範店主';

grant select on public.market_shops to anon, authenticated;
grant insert, update on public.market_shops to authenticated;
grant select, insert on public.account_messages to authenticated;
grant select on public.park_sessions to anon, authenticated;
grant usage, select on sequence public.account_messages_id_seq to authenticated;







