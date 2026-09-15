-- Centro de Monitoreo MT5 - esquema inicial
-- Correr en Supabase: Dashboard -> SQL Editor -> New query -> pegar y RUN

create table if not exists cuentas (
  id uuid primary key default gen_random_uuid(),
  login bigint not null unique,
  broker text,
  prop_firm text,
  fase text,
  alias text,
  activa boolean not null default true,
  alta_en timestamptz not null default now()
);

create table if not exists estado (
  cuenta_id uuid primary key references cuentas(id) on delete cascade,
  saldo numeric,
  equity numeric,
  flotante numeric,
  margen_libre numeric,
  algo_trading boolean,
  visto_en timestamptz not null default now()
);

create table if not exists posiciones (
  id uuid primary key default gen_random_uuid(),
  cuenta_id uuid not null references cuentas(id) on delete cascade,
  ticket bigint not null,
  simbolo text,
  tipo text,
  volumen numeric,
  apertura numeric,
  sl numeric,
  tp numeric,
  beneficio numeric,
  abierta_en timestamptz,
  unique (cuenta_id, ticket)
);

create table if not exists operaciones (
  id uuid primary key default gen_random_uuid(),
  cuenta_id uuid not null references cuentas(id) on delete cascade,
  ticket bigint not null,
  simbolo text,
  tipo text,
  volumen numeric,
  entrada numeric,
  salida numeric,
  beneficio numeric,
  comision numeric,
  abierta_en timestamptz,
  cerrada_en timestamptz,
  unique (cuenta_id, ticket)
);

create table if not exists bots (
  id uuid primary key default gen_random_uuid(),
  cuenta_id uuid not null references cuentas(id) on delete cascade,
  nombre text,
  grafico_id bigint not null,
  simbolo text,
  periodo text,
  interruptor text not null default 'arrancado' check (interruptor in ('arrancado', 'parado')),
  confirmado text,
  confirmado_en timestamptz,
  unique (cuenta_id, grafico_id)
);

create table if not exists ordenes (
  id uuid primary key default gen_random_uuid(),
  cuenta_id uuid not null references cuentas(id) on delete cascade,
  bot_id uuid references bots(id) on delete cascade,
  tipo text not null check (tipo in ('PARAR', 'ARRANCAR', 'DESCARGAR')),
  estado text not null default 'pendiente' check (estado in ('pendiente', 'entregada', 'hecha')),
  creada_en timestamptz not null default now(),
  entregada_en timestamptz,
  hecha_en timestamptz
);

create table if not exists reglas (
  cuenta_id uuid primary key references cuentas(id) on delete cascade,
  saldo_inicial numeric,
  perdida_diaria_max numeric,
  drawdown_max numeric,
  objetivo_fase numeric,
  hora_reset time,
  zona_horaria text
);

alter table cuentas enable row level security;
alter table estado enable row level security;
alter table posiciones enable row level security;
alter table operaciones enable row level security;
alter table bots enable row level security;
alter table ordenes enable row level security;
alter table reglas enable row level security;

-- Las políticas (quién puede leer/escribir qué) se agregan en un paso
-- aparte, una vez creado el usuario de autenticación dedicado al Agente.
