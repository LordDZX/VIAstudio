-- One-time full gameplay-data reset for the connected Supabase project.
-- Keeps shop IDs and positions so users can rent the empty spaces again.
-- Auth users/accounts and the game schema are intentionally retained.

begin;

do $$ begin
  if to_regclass('public.account_messages') is not null then
    execute 'delete from public.account_messages';
  end if;
  if to_regclass('public.park_sessions') is not null then
    execute 'delete from public.park_sessions';
  end if;
  if to_regclass('public.private_messages') is not null then
    execute 'delete from public.private_messages';
  end if;
end $$;

update public.market_shops
set owner_id = null,
    expire_at = null,
    payload = jsonb_build_object(
      'id', id,
      'position', coalesce(nullif(payload->'position', 'null'::jsonb), case
        when id = 'thread' then jsonb_build_object('x',180,'y',230)
        when id = 'plant' then jsonb_build_object('x',880,'y',230)
        when id = 'film' then jsonb_build_object('x',1580,'y',230)
        when id = 'bake' then jsonb_build_object('x',2280,'y',230)
        when id = 'ceramic' then jsonb_build_object('x',2980,'y',230)
        when id = 'paper' then jsonb_build_object('x',3680,'y',230)
        when id ~ '^district-[0-9]+$' then jsonb_build_object(
          'x',180 + (substring(id from 'district-([0-9]+)')::integer % 6) * 700,
          'y',230 + (substring(id from 'district-([0-9]+)')::integer / 6) * 620
        )
        else jsonb_build_object('x',180,'y',2600)
      end),
      'destroyed', false,
      'name', '空店面',
      'emoji', '🏪',
      'color', '#d6a68b',
      'tagline', '等待一位喜歡這裡的新店主。',
      'owner', '',
      'contact', '',
      'about', '',
      'products', '[]'::jsonb,
      'lease', 'null'::jsonb,
      'gameDataResetVersion', 2,
      'room', jsonb_build_object(
        'wallColor', '#eee7d6',
        'wallType', 'plain',
        'floorColor', '#caa982',
        'floorType', 'wood',
        'decor', '[]'::jsonb
      ),
      'exterior', jsonb_build_object(
        'awning', '#d98b72',
        'trim', '#fff2da',
        'style', 'awning'
      ),
      'cloudOwnerId', 'null'::jsonb
    );

select count(*) as shop_slots,
       count(*) filter (where owner_id is not null or expire_at > now()) as occupied_shops
from public.market_shops;

commit;
