-- Repair missing storefront coordinates and install a database-level no-overlap guard.
-- Existing shop content and ownership are preserved.
begin;
lock table public.market_shops in exclusive mode;
alter table public.market_shops add column if not exists cleanup_started_at timestamptz;

with missing as (
  select id,
         row_number() over (order by id) - 1 as extra_idx
  from public.market_shops
  where jsonb_typeof(payload->'position') is distinct from 'object'
     or coalesce(payload#>>'{position,x}', '') !~ '^-?[0-9]+([.][0-9]+)?$'
     or coalesce(payload#>>'{position,y}', '') !~ '^-?[0-9]+([.][0-9]+)?$'
), coords as (
  select id,
    case
      when id = 'thread' then 0 when id = 'plant' then 1 when id = 'film' then 2
      when id = 'bake' then 3 when id = 'ceramic' then 4 when id = 'paper' then 5
      when id ~ '^district-[0-9]+$' then substring(id from 'district-([0-9]+)')::integer
      else null
    end as slot_idx,
    extra_idx
  from missing
)
update public.market_shops m
set payload = jsonb_set(m.payload, '{position}', case
  when c.slot_idx is not null and c.slot_idx < 24 then jsonb_build_object(
    'x', 180 + (c.slot_idx % 6) * 700,
    'y', 230 + (c.slot_idx / 6) * 620
  )
  else jsonb_build_object(
    'x', 180 + (c.extra_idx % 20) * 300,
    'y', 2600 + (c.extra_idx / 20) * 300
  )
end, true)
from coords c where m.id = c.id;

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

create or replace function public.prevent_rerent_before_expiry_cleanup()
returns trigger language plpgsql set search_path = public as $$
begin
  if old.expire_at is not null and old.expire_at <= now()
     and jsonb_typeof(old.payload->'lease') = 'object'
     and auth.role() is not null
     and auth.role() <> 'service_role' then
    raise exception 'MARKET_SHOP_EXPIRY_CLEANUP_PENDING: wait for the expired lease cleanup';
  end if;
  return new;
end; $$;
drop trigger if exists market_shops_wait_for_expiry_cleanup on public.market_shops;
create trigger market_shops_wait_for_expiry_cleanup before update on public.market_shops
for each row execute function public.prevent_rerent_before_expiry_cleanup();

-- Authenticated shop owners can renew only their own active lease. Expiration is
-- extended from the existing server-side deadline, not from the browser clock.
create or replace function public.renew_market_shop(p_shop_id text, p_days integer)
returns jsonb language plpgsql security invoker set search_path = public as $$
declare current_payload jsonb; current_owner uuid; current_expiry timestamptz; cleanup_at timestamptz;
  next_expiry timestamptz; next_payload jsonb; renewal_list jsonb; renewed_at_ms bigint; next_expiry_ms bigint; next_duration integer;
begin
  if p_days is null or p_days not in (7,14,15) then raise exception 'Renewal must be 7, 14, or 15 days'; end if;
  if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean, true) then
    raise exception 'A verified account is required';
  end if;
  select payload, owner_id, expire_at, cleanup_started_at
    into current_payload, current_owner, current_expiry, cleanup_at
    from public.market_shops where id = p_shop_id for update;
  if not found or current_owner is distinct from auth.uid()
     or current_payload #>> '{lease,ownerId}' is distinct from auth.uid()::text then
    raise exception 'Only the current shop owner can renew this lease';
  end if;
  if cleanup_at is not null then raise exception 'Lease expiry cleanup is in progress'; end if;
  if current_expiry is null or current_expiry <= now() then raise exception 'This lease has expired'; end if;
  next_expiry := current_expiry + make_interval(days => p_days);
  renewed_at_ms := floor(extract(epoch from now()) * 1000)::bigint;
  next_expiry_ms := floor(extract(epoch from next_expiry) * 1000)::bigint;
  renewal_list := current_payload #> '{lease,renewals}';
  if jsonb_typeof(renewal_list) is distinct from 'array' then renewal_list := '[]'::jsonb; end if;
  renewal_list := renewal_list || jsonb_build_array(jsonb_build_object(
    'days', p_days, 'renewedAt', renewed_at_ms, 'expiresAt', next_expiry_ms
  ));
  next_duration := coalesce(nullif(current_payload #>> '{lease,duration}', '')::integer, 0) + p_days;
  next_payload := jsonb_set(current_payload, '{lease,expires}', to_jsonb(next_expiry_ms), true);
  next_payload := jsonb_set(next_payload, '{lease,duration}', to_jsonb(next_duration), true);
  next_payload := jsonb_set(next_payload, '{lease,renewals}', renewal_list, true);
  update public.market_shops set payload = next_payload, expire_at = next_expiry
    where id = p_shop_id;
  return jsonb_build_object('expires', next_expiry_ms, 'duration', next_duration, 'renewals', renewal_list);
end; $$;
revoke all on function public.renew_market_shop(text,integer) from public, anon;
grant execute on function public.renew_market_shop(text,integer) to authenticated;

create or replace function public.end_market_shop(p_shop_id text)
returns boolean language plpgsql security invoker set search_path = public as $$
declare current_payload jsonb; current_owner uuid; current_expiry timestamptz;
begin
  if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean, true) then
    raise exception 'A verified account is required';
  end if;
  select payload, owner_id, expire_at into current_payload, current_owner, current_expiry
    from public.market_shops where id = p_shop_id for update;
  if not found or current_owner is distinct from auth.uid()
     or current_payload #>> '{lease,ownerId}' is distinct from auth.uid()::text
     or current_expiry is null or current_expiry <= now() then
    raise exception 'Only the current shop owner can end this active lease';
  end if;
  update public.market_shops
  set owner_id = null, expire_at = null, cleanup_started_at = null,
      payload = jsonb_build_object(
        'id', p_shop_id, 'position', current_payload->'position', 'destroyed', false,
        'name', '空店面', 'emoji', '🏪', 'color', '#d6a68b',
        'tagline', '等待一位喜歡這裡的新店主。', 'owner', '', 'contact', '',
        'about', '', 'products', '[]'::jsonb, 'lease', 'null'::jsonb,
        'shopType', 'sale',
        'room', jsonb_build_object('wallColor','#eee7d6','wallType','plain','floorColor','#caa982','floorType','wood','decor','[]'::jsonb),
        'exterior', jsonb_build_object('awning','#d98b72','trim','#fff2da','style','awning'),
        'cloudOwnerId', 'null'::jsonb
      )
  where id = p_shop_id;
  return true;
end; $$;
revoke all on function public.end_market_shop(text) from public, anon;
grant execute on function public.end_market_shop(text) to authenticated;

-- The cron worker claims expired rows briefly so a lease cannot be renewed or
-- re-rented while its files are being removed through the Storage API.
create or replace function public.claim_expired_market_shops(p_limit integer default 100)
returns setof public.market_shops language plpgsql security definer set search_path = public as $$
begin
  return query
  with candidates as (
    select id from public.market_shops
    where expire_at <= now()
      and (cleanup_started_at is null or cleanup_started_at < now() - interval '10 minutes')
    order by expire_at
    limit greatest(1, least(coalesce(p_limit, 100), 100))
    for update skip locked
  )
  update public.market_shops s set cleanup_started_at = now()
  from candidates c where s.id = c.id
  returning s.*;
end; $$;

create or replace function public.release_expired_market_shop(p_shop_id text, p_expire_at timestamptz)
returns void language sql security definer set search_path = public as $$
  update public.market_shops set cleanup_started_at = null
  where id = p_shop_id and expire_at = p_expire_at and cleanup_started_at is not null;
$$;

create or replace function public.finalize_expired_market_shop(p_shop_id text, p_expire_at timestamptz)
returns boolean language plpgsql security definer set search_path = public as $$
declare finalized_id text;
begin
  update public.market_shops s
  set owner_id = null, expire_at = null, cleanup_started_at = null,
      payload = jsonb_build_object(
        'id', s.id, 'position', s.payload->'position', 'destroyed', false,
        'name', '空店面', 'emoji', '🏪', 'color', '#d6a68b',
        'tagline', '等待一位喜歡這裡的新店主。', 'owner', '', 'contact', '',
        'about', '', 'products', '[]'::jsonb, 'lease', 'null'::jsonb,
        'shopType', 'sale',
        'room', jsonb_build_object('wallColor','#eee7d6','wallType','plain','floorColor','#caa982','floorType','wood','decor','[]'::jsonb),
        'exterior', jsonb_build_object('awning','#d98b72','trim','#fff2da','style','awning'),
        'cloudOwnerId', 'null'::jsonb
      )
  where s.id = p_shop_id and s.expire_at = p_expire_at
    and s.expire_at <= now() and s.cleanup_started_at is not null
  returning s.id into finalized_id;
  if finalized_id is null then return false; end if;
  delete from public.account_messages where shop_id = p_shop_id;
  return true;
end; $$;
revoke all on function public.claim_expired_market_shops(integer) from public, anon, authenticated;
revoke all on function public.release_expired_market_shop(text,timestamptz) from public, anon, authenticated;
revoke all on function public.finalize_expired_market_shop(text,timestamptz) from public, anon, authenticated;
grant execute on function public.claim_expired_market_shops(integer) to service_role;
grant execute on function public.release_expired_market_shop(text,timestamptz) to service_role;
grant execute on function public.finalize_expired_market_shop(text,timestamptz) to service_role;

drop policy if exists "owners delete market media" on storage.objects;
create policy "owners delete market media" on storage.objects for delete to authenticated
  using (bucket_id='market-media' and (storage.foldername(name))[1]=(select auth.uid())::text and coalesce((select auth.jwt()->>'is_anonymous')::boolean,true)=false);

create or replace function public.clear_messages_when_shop_lease_ends()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if jsonb_typeof(old.payload->'lease') = 'object'
     and jsonb_typeof(new.payload->'lease') is distinct from 'object' then
    delete from public.account_messages where shop_id = new.id;
  end if;
  return new;
end; $$;
revoke all on function public.clear_messages_when_shop_lease_ends() from public, anon, authenticated;
drop trigger if exists market_shops_clear_messages_on_lease_end on public.market_shops;
create trigger market_shops_clear_messages_on_lease_end
after update of payload on public.market_shops
for each row execute function public.clear_messages_when_shop_lease_ends();

select count(*) as shops_without_position
from public.market_shops
where jsonb_typeof(payload->'position') is distinct from 'object'
   or coalesce(payload#>>'{position,x}', '') !~ '^-?[0-9]+([.][0-9]+)?$'
   or coalesce(payload#>>'{position,y}', '') !~ '^-?[0-9]+([.][0-9]+)?$';
commit;
