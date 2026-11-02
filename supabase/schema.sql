-- =====================================================================
-- Mario Party Jamboree Tracker: Supabase (Postgres) schema
--
-- Run once: Supabase dashboard > SQL Editor > New query > paste > Run.
-- Safe to re-run: tables use IF NOT EXISTS, views and functions use
-- CREATE OR REPLACE, and seed rows use ON CONFLICT DO NOTHING.
--
-- Access model (the site is public, "anyone with the link"):
--   * anyone can READ every table and view
--   * anyone can DELETE a game (players and photo cascade)
--   * nobody can INSERT or UPDATE tables directly; new games go through
--     add_game(), which validates the whole game in one transaction
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Lookup tables. Dropdowns on the page are loaded from these, so to
--    add a DLC character or board, insert a row here.
-- ---------------------------------------------------------------------
create table if not exists public.characters (
  name text primary key check (char_length(name) between 1 and 30)
);

create table if not exists public.boards (
  name       text primary key check (char_length(name) between 1 and 60),
  sort_order int  not null default 100
);

insert into public.characters (name) values
  ('Mario'), ('Luigi'), ('Peach'), ('Daisy'), ('Wario'), ('Waluigi'),
  ('Yoshi'), ('Birdo'), ('Rosalina'), ('Donkey Kong'), ('Toad'), ('Toadette'),
  ('Boo'), ('Shy Guy'), ('Bowser'), ('Bowser Jr.'), ('Goomba'), ('Koopa Troopa'),
  ('Monty Mole'), ('Pauline'), ('Ninji'), ('Spike')
on conflict do nothing;

insert into public.boards (name, sort_order) values
  ('Mega Wiggler''s Tree Party', 1), ('Rainbow Galleria', 2), ('Goomba Lagoon', 3),
  ('Roll ''em Raceway', 4), ('King Bowser''s Keep', 5),
  ('Mario''s Rainbow Castle', 6), ('Western Land', 7)
on conflict do nothing;


-- ---------------------------------------------------------------------
-- 2. Core tables
-- ---------------------------------------------------------------------
create table if not exists public.games (
  id         bigint generated always as identity primary key,
  played_on  date        not null default current_date,
  board      text        not null references public.boards (name) on update cascade,
  mode       text        not null default 'Party'
                         check (mode in ('Party', 'Partner Party', 'Other')),
  turns      smallint    not null check (turns between 1 and 99),
  created_at timestamptz not null default now()
);

-- One row per seat in a game. CPUs take a place but have no name.
create table if not exists public.game_players (
  game_id     bigint   not null references public.games (id) on delete cascade,
  seat        smallint not null check (seat between 1 and 8),
  player_name text     check (char_length(player_name) between 1 and 30),
  -- Grouping key so "Matt", "matt " and "MATT" count as one person.
  player_key  text     generated always as
                       (regexp_replace(lower(btrim(player_name)), '\s+', ' ', 'g')) stored,
  is_cpu      boolean  not null default false,
  character   text     not null references public.characters (name) on update cascade,
  place       smallint not null check (place between 1 and 8),
  stars       smallint not null default 0 check (stars between 0 and 99),
  coins       smallint not null default 0 check (coins between 0 and 999),
  primary key (game_id, seat),
  constraint cpu_has_no_name check (is_cpu = (player_name is null))
);

-- The same person cannot sit in one game twice.
create unique index if not exists game_players_one_seat_per_person
  on public.game_players (game_id, player_key) where not is_cpu;

create index if not exists game_players_player_key on public.game_players (player_key);

-- Photos live in their own table so history queries stay small.
create table if not exists public.game_photos (
  game_id bigint primary key references public.games (id) on delete cascade,
  data    text   not null
          check (data like 'data:image/jpeg;base64,%' and length(data) < 900000)
);


-- ---------------------------------------------------------------------
-- 3. The only way to add a game. SECURITY DEFINER lets it insert even
--    though the public role has no INSERT grant, so every game is
--    validated here before it lands.
-- ---------------------------------------------------------------------
create or replace function public.add_game(p_game jsonb, p_photo text default null)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id bigint;
  v_n  int := coalesce(jsonb_array_length(p_game -> 'players'), 0);
begin
  if v_n not between 2 and 8 then
    raise exception 'A game needs 2 to 8 players (got %).', v_n;
  end if;

  insert into games (played_on, board, mode, turns)
  values ((p_game ->> 'played_on')::date,
          p_game ->> 'board',
          coalesce(p_game ->> 'mode', 'Party'),
          (p_game ->> 'turns')::smallint)
  returning id into v_id;

  insert into game_players (game_id, seat, player_name, is_cpu, character, place, stars, coins)
  select v_id,
         t.ord,
         case when coalesce((t.p ->> 'cpu')::boolean, false) then null
              else nullif(btrim(t.p ->> 'name'), '') end,
         coalesce((t.p ->> 'cpu')::boolean, false),
         t.p ->> 'character',
         (t.p ->> 'place')::smallint,
         coalesce((t.p ->> 'stars')::smallint, 0),
         coalesce((t.p ->> 'coins')::smallint, 0)
  from jsonb_array_elements(p_game -> 'players') with ordinality as t (p, ord);

  if not exists (select 1 from game_players where game_id = v_id and place = 1) then
    raise exception 'Someone has to finish 1st.';
  end if;
  if not exists (select 1 from game_players where game_id = v_id and not is_cpu) then
    raise exception 'At least one player must be a person.';
  end if;
  if exists (select 1 from game_players where game_id = v_id and place > v_n) then
    raise exception 'A place is higher than the number of players.';
  end if;

  if p_photo is not null then
    insert into game_photos (game_id, data) values (v_id, p_photo);
  end if;

  return v_id;
end;
$$;


-- ---------------------------------------------------------------------
-- 4. Views: the aggregated results. security_invoker makes each view
--    run with the caller's permissions, so table RLS still applies.
--    "Ranked" means at least 3 games (2 for a player + character pair),
--    so one lucky game does not top the leaderboard.
-- ---------------------------------------------------------------------

-- Display name per person: the spelling they used most often.
create or replace view public.player_names with (security_invoker = true) as
select player_key,
       mode() within group (order by player_name) as player
from public.game_players
where not is_cpu
group by player_key;


-- Leaderboard: one row per person.
create or replace view public.player_stats with (security_invoker = true) as
with seats as (
  select gp.*, g.board, g.mode,
         count(*) over (partition by gp.game_id) as n_players   -- includes CPUs
  from public.game_players gp
  join public.games g on g.id = gp.game_id
),
humans as (
  select * from seats where not is_cpu
),
agg as (
  select player_key,
         count(*)::int                              as games,
         (count(*) filter (where place = 1))::int   as wins,
         -- Wins that pure luck would give in these same games:
         -- 1/n for a free-for-all, 1/2 for a 2v2 Partner Party.
         sum(case when mode = 'Partner Party' then 0.5
                  else 1.0 / n_players end)         as expected_wins,
         sum(stars)::int                            as stars,
         avg(stars)                                 as avg_stars,
         avg(place)                                 as avg_place
  from humans
  group by player_key
),
mains as (
  select distinct on (player_key) player_key, character as main_character
  from humans
  group by player_key, character
  order by player_key, count(*) desc, character
),
best_boards as (
  select distinct on (player_key) player_key, board as best_board, count(*)::int as best_board_wins
  from humans
  where place = 1
  group by player_key, board
  order by player_key, count(*) desc, board
)
select case when a.games >= 3 then
         rank() over (partition by a.games >= 3
                      order by a.wins::numeric / a.games desc, a.wins desc, a.stars desc)
       end                                        as rank,
       n.player,
       a.player_key,
       a.games,
       a.wins,
       round(100.0 * a.wins / a.games, 1)         as win_pct,
       round(a.wins / a.expected_wins, 2)         as vs_luck,
       a.stars,
       round(a.avg_stars, 1)                      as stars_per_game,
       round(a.avg_place, 2)                      as avg_place,
       m.main_character,
       b.best_board,
       b.best_board_wins
from agg a
join public.player_names n using (player_key)
left join mains m using (player_key)
left join best_boards b using (player_key);


-- Characters: every character, even ones nobody has picked yet.
create or replace view public.character_stats with (security_invoker = true) as
with humans as (
  select * from public.game_players where not is_cpu
),
agg as (
  select character,
         count(*)::int                            as picks,
         (count(*) filter (where place = 1))::int as wins,
         avg(stars)                               as avg_stars,
         avg(place)                               as avg_place
  from humans
  group by character
),
fans as (
  select distinct on (h.character) h.character, n.player as top_player, count(*)::int as top_player_picks
  from humans h
  join public.player_names n using (player_key)
  group by h.character, n.player
  order by h.character, count(*) desc, n.player
)
select case when coalesce(a.picks, 0) >= 3 then
         rank() over (partition by coalesce(a.picks, 0) >= 3
                      order by a.wins::numeric / nullif(a.picks, 0) desc nulls last, a.wins desc, a.picks desc)
       end                                                  as rank,
       c.name                                               as character,
       coalesce(a.picks, 0)                                 as picks,
       coalesce(a.wins, 0)                                  as wins,
       round(100.0 * a.wins / nullif(a.picks, 0), 1)        as win_pct,
       round(a.avg_stars, 1)                                as stars_per_game,
       round(a.avg_place, 2)                                as avg_place,
       f.top_player,
       f.top_player_picks
from public.characters c
left join agg  a on a.character = c.name
left join fans f on f.character = c.name;


-- The aggregated ranking: one row per (player, character) pair, ranked
-- three ways by win ratio.
--   rank_for_player:    a player's best character         (PARTITION BY player)
--   rank_for_character: who plays each character best     (PARTITION BY character)
--   rank_overall:       best player + character combos    (2+ games only)
create or replace view public.player_character_stats with (security_invoker = true) as
with combo as (
  select player_key,
         character,
         count(*)::int                            as games,
         (count(*) filter (where place = 1))::int as wins,
         sum(stars)::int                          as stars,
         avg(place)                               as avg_place
  from public.game_players
  where not is_cpu
  group by player_key, character
)
select n.player,
       c.player_key,
       c.character,
       c.games,
       c.wins,
       round(100.0 * c.wins / c.games, 1)   as win_pct,
       c.stars,
       round(c.stars::numeric / c.games, 1) as stars_per_game,
       round(c.avg_place, 2)                as avg_place,
       rank() over (partition by c.player_key
                    order by c.wins::numeric / c.games desc, c.wins desc, c.games desc) as rank_for_player,
       rank() over (partition by c.character
                    order by c.wins::numeric / c.games desc, c.wins desc, c.games desc) as rank_for_character,
       case when c.games >= 2 then
         rank() over (partition by c.games >= 2
                      order by c.wins::numeric / c.games desc, c.wins desc, c.games desc)
       end                                  as rank_overall
from combo c
join public.player_names n using (player_key);


-- Head to head: a self-join on game_players. Only games both people
-- played count, which is the fair comparison when the group changes.
create or replace view public.head_to_head with (security_invoker = true) as
select a.player_key,
       na.player,
       b.player_key                                          as opponent_key,
       nb.player                                             as opponent,
       count(*)::int                                         as games,
       (count(*) filter (where a.place < b.place))::int      as ahead,
       (count(*) filter (where a.place > b.place))::int      as behind,
       (count(*) filter (where a.place = b.place))::int      as ties,
       round(100.0 * count(*) filter (where a.place < b.place) / count(*), 1) as ahead_pct
from public.game_players a
join public.game_players b
  on b.game_id = a.game_id
 and b.player_key <> a.player_key
join public.player_names na on na.player_key = a.player_key
join public.player_names nb on nb.player_key = b.player_key
where not a.is_cpu and not b.is_cpu
group by a.player_key, na.player, b.player_key, nb.player;


create or replace view public.board_stats with (security_invoker = true) as
with played as (
  select board, count(*)::int as games from public.games group by board
),
top_winner as (
  select distinct on (g.board) g.board, n.player as top_winner, count(*)::int as top_winner_wins
  from public.games g
  join public.game_players gp on gp.game_id = g.id
  join public.player_names n  on n.player_key = gp.player_key
  where gp.place = 1 and not gp.is_cpu
  group by g.board, n.player
  order by g.board, count(*) desc, n.player
),
stars as (
  select g.board, avg(gp.stars) as avg_stars
  from public.games g
  join public.game_players gp on gp.game_id = g.id
  where not gp.is_cpu
  group by g.board
)
select b.name                       as board,
       b.sort_order,
       coalesce(p.games, 0)         as games,
       t.top_winner,
       t.top_winner_wins,
       round(s.avg_stars, 1)        as stars_per_player
from public.boards b
left join played     p on p.board = b.name
left join top_winner t on t.board = b.name
left join stars      s on s.board = b.name;


-- Game list for the History tab, players nested as JSON.
create or replace view public.game_history with (security_invoker = true) as
select g.id,
       g.played_on,
       g.board,
       g.mode,
       g.turns,
       g.created_at,
       exists (select 1 from public.game_photos ph where ph.game_id = g.id) as has_photo,
       (select json_agg(json_build_object(
                  'name', gp.player_name, 'cpu', gp.is_cpu, 'character', gp.character,
                  'place', gp.place, 'stars', gp.stars, 'coins', gp.coins)
                order by gp.place, gp.seat)
        from public.game_players gp
        where gp.game_id = g.id)                                         as players
from public.games g;


-- ---------------------------------------------------------------------
-- 5. Permissions and row level security
-- ---------------------------------------------------------------------
alter table public.characters   enable row level security;
alter table public.boards       enable row level security;
alter table public.games        enable row level security;
alter table public.game_players enable row level security;
alter table public.game_photos  enable row level security;

drop policy if exists "public read" on public.characters;
drop policy if exists "public read" on public.boards;
drop policy if exists "public read" on public.games;
drop policy if exists "public read" on public.game_players;
drop policy if exists "public read" on public.game_photos;
drop policy if exists "public delete" on public.games;

create policy "public read"   on public.characters   for select to anon, authenticated using (true);
create policy "public read"   on public.boards       for select to anon, authenticated using (true);
create policy "public read"   on public.games        for select to anon, authenticated using (true);
create policy "public read"   on public.game_players for select to anon, authenticated using (true);
create policy "public read"   on public.game_photos  for select to anon, authenticated using (true);
create policy "public delete" on public.games        for delete to anon, authenticated using (true);

-- Supabase grants broad table rights to anon by default. Narrow them.
revoke all on public.characters, public.boards, public.games,
              public.game_players, public.game_photos
  from anon, authenticated;

grant select on public.characters, public.boards, public.games,
                public.game_players, public.game_photos,
                public.player_names, public.player_stats, public.character_stats,
                public.player_character_stats, public.head_to_head,
                public.board_stats, public.game_history
  to anon, authenticated;

grant delete on public.games to anon, authenticated;

revoke execute on function public.add_game(jsonb, text) from public;
grant  execute on function public.add_game(jsonb, text) to anon, authenticated;
