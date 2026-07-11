-- 룬 라이벌즈 전적 스키마 (Supabase / Postgres)
-- 적용: Supabase 대시보드 → SQL Editor → 아래 전체 붙여넣고 Run.
-- 쓰기는 서버(service_role)만, 읽기(리더보드)는 공개 허용.

-- 플레이어(닉네임 기반, 추후 auth 연동 확장 가능)
create table if not exists players (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  rating     int  not null default 1000,   -- 랭크용(추후)
  created_at timestamptz not null default now()
);

-- 한 판(매치). id 는 클라이언트가 생성한 UUID(중복 보고 방지 upsert 키).
create table if not exists matches (
  id          uuid primary key,
  mode        text not null check (mode in ('single','casual','ranked')),
  room_code   text,
  seed        bigint,
  num_players int  not null,
  winner_seat int,
  started_at  timestamptz not null default now(),
  ended_at    timestamptz not null default now()
);

-- 매치별 좌석 결과
create table if not exists match_results (
  id          bigint generated always as identity primary key,
  match_id    uuid not null references matches(id) on delete cascade,
  seat        int  not null,
  player_id   uuid references players(id),
  name        text not null,
  points      int  not null,
  evolutions  int  not null,
  cards       int  not null,
  rank        int  not null,               -- 1 = 우승
  is_ai       boolean not null default false,
  unique (match_id, seat)
);

create index if not exists idx_results_match  on match_results(match_id);
create index if not exists idx_results_player on match_results(player_id);

-- 플레이어 전적 요약(사람만)
create or replace view player_stats as
select
  r.name,
  count(*)                              as games,
  count(*) filter (where r.rank = 1)    as wins,
  round(100.0 * count(*) filter (where r.rank = 1) / nullif(count(*),0), 1) as win_rate,
  round(avg(r.points)::numeric, 1)      as avg_points,
  max(r.points)                         as best_points,
  sum(r.evolutions)                     as total_evolutions
from match_results r
where r.is_ai = false
group by r.name;

-- RLS: 공개 읽기 / 쓰기는 service_role(서버)만(=RLS 우회). anon 은 select 만.
alter table players       enable row level security;
alter table matches       enable row level security;
alter table match_results enable row level security;

drop policy if exists p_players_read on players;
drop policy if exists p_matches_read on matches;
drop policy if exists p_results_read on match_results;
create policy p_players_read on players       for select using (true);
create policy p_matches_read on matches       for select using (true);
create policy p_results_read on match_results for select using (true);
-- insert/update 정책 없음 → anon 쓰기 불가. 서버는 service_role 로 RLS 우회하여 기록.
