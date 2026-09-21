create extension if not exists pgcrypto;

create type public.game_round as enum ('lobby', 'round_1', 'round_2', 'finished');
create type public.player_status as enum ('unlocked', 'locked');

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  round public.game_round not null default 'lobby',
  current_player_id uuid,
  winner_id uuid,
  last_roll int check (last_roll between 1 and 6),
  created_at timestamptz not null default now()
);

create table public.players (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 24),
  points int not null default 0 check (points between 0 and 20),
  status public.player_status not null default 'unlocked',
  lock_value int not null default 0 check (lock_value >= 0),
  round_1_done boolean not null default false,
  joined_at timestamptz not null default now()
);

alter table public.rooms add constraint rooms_current_player_fk foreign key (current_player_id) references public.players(id);
alter table public.rooms add constraint rooms_winner_fk foreign key (winner_id) references public.players(id);
alter table public.rooms add column host_player_id uuid references public.players(id);
alter table public.players add constraint players_room_name_unique unique (room_id, display_name);

create table public.game_events (
  id bigint generated always as identity primary key,
  room_id uuid not null references public.rooms(id) on delete cascade,
  player_id uuid references public.players(id),
  message text not null,
  created_at timestamptz not null default now()
);

alter table public.rooms enable row level security;
alter table public.players enable row level security;
alter table public.game_events enable row level security;
-- The browser only receives room data through controlled server actions.
-- Add authenticated policies after the chosen auth flow is connected.
create policy "rooms readable" on public.rooms for select using (true);
create policy "rooms insertable" on public.rooms for insert with check (true);
create policy "rooms updatable" on public.rooms for update using (true) with check (true);
create policy "players readable" on public.players for select using (true);
create policy "players insertable" on public.players for insert with check (true);
create policy "players deletable" on public.players for delete using (true);
alter publication supabase_realtime add table public.players;

create or replace function public.dice_power(roll int) returns int language sql immutable as $$
  select case when roll = 5 then 5 when roll = 6 then 10 else 0 end;
$$;

create or replace function public.cap_points(value int) returns int language sql immutable as $$
  select greatest(0, least(20, value));
$$;

create or replace function public.set_room_host(p_room_id uuid, p_player_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.rooms set host_player_id = p_player_id
  where id = p_room_id and round = 'lobby' and host_player_id is null
    and exists (select 1 from public.players where id = p_player_id and room_id = p_room_id);
  if not found then raise exception 'Could not assign room host'; end if;
end;
$$;

create or replace function public.start_game(p_room_id uuid, p_player_id uuid)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room public.rooms;
  v_first uuid;
  v_count int;
begin
  select * into v_room from public.rooms where id = p_room_id for update;
  if not found then raise exception 'Room not found'; end if;
  if v_room.host_player_id is distinct from p_player_id then raise exception 'Only the host can start the game'; end if;
  if v_room.round <> 'lobby' then raise exception 'This game has already started'; end if;
  select count(*) into v_count from public.players where room_id = p_room_id;
  if v_count < 2 then raise exception 'At least 2 players are required'; end if;
  select id into v_first from public.players where room_id = p_room_id order by joined_at, id limit 1;
  update public.players set points = 0, status = 'unlocked', lock_value = 0, round_1_done = false where room_id = p_room_id;
  update public.rooms set round = 'round_1', current_player_id = v_first, last_roll = null, winner_id = null where id = p_room_id returning * into v_room;
  insert into public.game_events(room_id, player_id, message) values (p_room_id, p_player_id, 'Round 1 has started.');
  return v_room;
end;
$$;

create or replace function public.roll_round_1(p_room_id uuid, p_player_id uuid)
returns public.rooms
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room public.rooms;
  v_roll int;
  v_power int;
  v_next uuid;
  v_all_done boolean;
  v_name text;
begin
  select * into v_room from public.rooms where id = p_room_id for update;
  if not found then raise exception 'Room not found'; end if;
  if v_room.round <> 'round_1' then raise exception 'Round 1 is not active'; end if;
  if v_room.current_player_id is distinct from p_player_id then raise exception 'It is not your turn'; end if;
  select display_name into v_name from public.players where id = p_player_id and room_id = p_room_id;
  if v_name is null then raise exception 'Player is not in this room'; end if;
  v_roll := floor(random() * 6 + 1)::int;
  v_power := public.dice_power(v_roll);
  update public.players set points = public.cap_points(points + v_power), round_1_done = true where id = p_player_id;
  insert into public.game_events(room_id, player_id, message) values (p_room_id, p_player_id, v_name || ' rolled ' || v_roll || ' and gained ' || v_power || ' power.');
  select not exists (select 1 from public.players where room_id = p_room_id and round_1_done = false) into v_all_done;
  if v_all_done then
    select id into v_next from public.players where room_id = p_room_id order by joined_at, id limit 1;
    update public.rooms set round = 'round_2', current_player_id = v_next, last_roll = v_roll where id = p_room_id returning * into v_room;
    insert into public.game_events(room_id, player_id, message) values (p_room_id, p_player_id, 'Round 1 complete. Round 2 is ready.');
  else
    select id into v_next from public.players where room_id = p_room_id and round_1_done = false order by joined_at, id limit 1;
    update public.rooms set current_player_id = v_next, last_roll = v_roll where id = p_room_id returning * into v_room;
  end if;
  return v_room;
end;
$$;
