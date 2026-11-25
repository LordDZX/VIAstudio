-- Three purpose maps; preserve shop IDs, content, ownership, and positions.
-- Run once before deploying the matching index.html. Safe to rerun.
begin;
create or replace function public.market_shop_map(p jsonb)
returns text language plpgsql immutable set search_path = public as $$
declare slot integer;
begin
  if p->>'shopType' in ('sale','collaboration','hiring') then return p->>'shopType'; end if;
  if coalesce(p->>'shopType','') <> '' then return 'sale'; end if;
  if coalesce(p->'lease','null'::jsonb) = 'null'::jsonb and coalesce(p->>'owner','') = ''
     and coalesce(p->'products','[]'::jsonb) = '[]'::jsonb then
    slot := case p->>'id' when 'thread' then 0 when 'plant' then 1 when 'film' then 2
      when 'bake' then 3 when 'ceramic' then 4 when 'paper' then 5 else null end;
    if p->>'id' ~ '^district-([6-9]|1[0-9]|2[0-3])$' then slot := substring(p->>'id' from 'district-([0-9]+)')::integer; end if;
    if slot is not null then return (array['sale','collaboration','hiring'])[slot % 3 + 1]; end if;
  end if;
  return 'sale';
end; $$;
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
            where public.market_shop_map(m.payload) = public.market_shop_map(new.payload) and m.id <> new.id and not coalesce((m.payload->>'destroyed')::boolean, false)
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
    where public.market_shop_map(m.payload) = public.market_shop_map(new.payload) and m.id <> new.id and not coalesce((m.payload->>'destroyed')::boolean, false)
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
for each row when ((old.payload -> 'position') is distinct from (new.payload -> 'position') or public.market_shop_map(old.payload) is distinct from public.market_shop_map(new.payload))
execute function public.enforce_market_shop_non_overlap();



alter table public.market_shops add column if not exists cleanup_started_at timestamptz;
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
        'shopType', public.market_shop_map(current_payload),
        'room', jsonb_build_object('wallColor','#eee7d6','wallType','plain','floorColor','#caa982','floorType','wood','decor','[]'::jsonb),
        'exterior', jsonb_build_object('awning','#d98b72','trim','#fff2da','style','awning'),
        'cloudOwnerId', 'null'::jsonb
      )
  where id = p_shop_id;
  return true;
end; $$;
revoke all on function public.end_market_shop(text) from public, anon;
grant execute on function public.end_market_shop(text) to authenticated;


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
        'shopType', public.market_shop_map(s.payload),
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

revoke all on function public.finalize_expired_market_shop(text,timestamptz) from public, anon, authenticated;
grant execute on function public.finalize_expired_market_shop(text,timestamptz) to service_role;
commit;
