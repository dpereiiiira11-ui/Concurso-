-- =====================================================================
-- RUMO TCE — schema completo (Supabase/Postgres)
-- Rode isto inteiro no SQL Editor do seu projeto Supabase.
-- É seguro rodar de novo: usa "if not exists" e "on conflict" onde possível.
-- =====================================================================

create extension if not exists "uuid-ossp";

-- ---------------------------------------------------------------------
-- PROFILES (1 por usuário autenticado)
-- ---------------------------------------------------------------------
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text,
  meta_diaria_minutos int not null default 180,
  tema text not null default 'noite',
  modo_aparencia text not null default 'dark',
  sequencia_dias int not null default 0,
  criado_em timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- DISCIPLINAS E TÓPICOS (conteúdo do edital — leitura pública p/ autenticados)
-- ---------------------------------------------------------------------
create table if not exists disciplinas (
  id uuid primary key default uuid_generate_v4(),
  slug text unique not null,
  nome text not null,
  bloco text not null check (bloco in ('gerais','especificos')),
  peso_por_questao int not null default 1,
  cor text,
  ordem int not null default 0
);

create table if not exists topicos (
  id uuid primary key default uuid_generate_v4(),
  disciplina_id uuid not null references disciplinas(id) on delete cascade,
  nome text not null,
  ordem int not null default 0
);

-- ---------------------------------------------------------------------
-- QUESTÕES
-- ---------------------------------------------------------------------
create table if not exists questions (
  id uuid primary key default uuid_generate_v4(),
  disciplina_id uuid not null references disciplinas(id) on delete cascade,
  topico_id uuid references topicos(id) on delete set null,
  enunciado text not null,
  explicacao text,
  nivel text not null default 'basico' check (nivel in ('basico','intermediario','avancado','nivel_prova')),
  origem_tipo text not null default 'inedita' check (origem_tipo in ('real','adaptada','inedita')),
  orgao text,
  ano_origem int,
  ativa boolean not null default true,
  criado_em timestamptz not null default now()
);

create table if not exists question_options (
  id uuid primary key default uuid_generate_v4(),
  question_id uuid not null references questions(id) on delete cascade,
  texto text not null,
  correta boolean not null default false,
  ordem int not null default 0
);

-- ---------------------------------------------------------------------
-- SESSÕES DE ESTUDO / TENTATIVAS / ANOTAÇÕES
-- ---------------------------------------------------------------------
create table if not exists study_sessions (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  modo text not null default 'por_materia',
  disciplina_id uuid references disciplinas(id),
  quantidade_planejada int,
  quantidade_respondida int,
  acertos int,
  criado_em timestamptz not null default now(),
  finalizada_em timestamptz
);

create table if not exists question_attempts (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  question_id uuid not null references questions(id) on delete cascade,
  session_id uuid references study_sessions(id) on delete set null,
  status text not null check (status in ('acertou','errou','nao_sei_ainda')),
  alternativa_escolhida uuid references question_options(id),
  motivo_erro text,
  marcada_duvida boolean not null default false,
  tempo_segundos int,
  criado_em timestamptz not null default now()
);

create table if not exists question_notes (
  user_id uuid not null references auth.users(id) on delete cascade,
  question_id uuid not null references questions(id) on delete cascade,
  texto text not null,
  atualizado_em timestamptz not null default now(),
  primary key (user_id, question_id)
);

-- ---------------------------------------------------------------------
-- REVISÕES (repetição espaçada)
-- ---------------------------------------------------------------------
create table if not exists review_queue (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  question_id uuid not null references questions(id) on delete cascade,
  status text not null default 'preciso_entender',
  proxima_revisao date not null default current_date,
  concluida boolean not null default false,
  criado_em timestamptz not null default now(),
  unique (user_id, question_id)
);

-- ---------------------------------------------------------------------
-- SIMULADOS
-- ---------------------------------------------------------------------
create table if not exists mock_exams (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  tipo text not null,
  total_questoes int not null,
  nota_ponderada numeric(6,2),
  criado_em timestamptz not null default now(),
  finalizado_em timestamptz
);

create table if not exists mock_exam_answers (
  id uuid primary key default uuid_generate_v4(),
  mock_exam_id uuid not null references mock_exams(id) on delete cascade,
  question_id uuid not null references questions(id) on delete cascade,
  alternativa_escolhida uuid references question_options(id),
  correta boolean not null default false,
  ordem int not null default 0
);

-- ---------------------------------------------------------------------
-- FOCO (cronômetro / vela)
-- ---------------------------------------------------------------------
create table if not exists focus_sessions (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  minutos_sorteados int not null,
  limite_informado int,
  modo text not null default 'vela',
  minutos_realizados int,
  concluida boolean not null default false,
  iniciada_em timestamptz not null default now(),
  finalizada_em timestamptz
);

-- ---------------------------------------------------------------------
-- ÍNDICES
-- ---------------------------------------------------------------------
create index if not exists idx_topicos_disciplina on topicos(disciplina_id);
create index if not exists idx_questions_disciplina on questions(disciplina_id);
create index if not exists idx_questions_topico on questions(topico_id);
create index if not exists idx_options_question on question_options(question_id);
create index if not exists idx_attempts_user on question_attempts(user_id);
create index if not exists idx_attempts_question on question_attempts(question_id);
create index if not exists idx_review_user_due on review_queue(user_id, proxima_revisao) where not concluida;
create index if not exists idx_focus_user on focus_sessions(user_id);
create index if not exists idx_study_sessions_user on study_sessions(user_id);
create index if not exists idx_mock_exams_user on mock_exams(user_id);

-- =====================================================================
-- RLS
-- =====================================================================
alter table profiles enable row level security;
alter table disciplinas enable row level security;
alter table topicos enable row level security;
alter table questions enable row level security;
alter table question_options enable row level security;
alter table study_sessions enable row level security;
alter table question_attempts enable row level security;
alter table question_notes enable row level security;
alter table review_queue enable row level security;
alter table mock_exams enable row level security;
alter table mock_exam_answers enable row level security;
alter table focus_sessions enable row level security;

drop policy if exists profiles_self on profiles;
create policy profiles_self on profiles for all using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists disciplinas_read on disciplinas;
create policy disciplinas_read on disciplinas for select using (auth.role() = 'authenticated');
drop policy if exists topicos_read on topicos;
create policy topicos_read on topicos for select using (auth.role() = 'authenticated');
drop policy if exists questions_read on questions;
create policy questions_read on questions for select using (auth.role() = 'authenticated');
drop policy if exists options_read on question_options;
create policy options_read on question_options for select using (auth.role() = 'authenticated');

drop policy if exists study_sessions_self on study_sessions;
create policy study_sessions_self on study_sessions for all using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists attempts_self on question_attempts;
create policy attempts_self on question_attempts for all using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists notes_self on question_notes;
create policy notes_self on question_notes for all using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists review_self on review_queue;
create policy review_self on review_queue for all using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists mocks_self on mock_exams;
create policy mocks_self on mock_exams for all using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists focus_self on focus_sessions;
create policy focus_self on focus_sessions for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists mock_answers_self on mock_exam_answers;
create policy mock_answers_self on mock_exam_answers for all
  using (exists (select 1 from mock_exams m where m.id = mock_exam_answers.mock_exam_id and m.user_id = auth.uid()))
  with check (exists (select 1 from mock_exams m where m.id = mock_exam_answers.mock_exam_id and m.user_id = auth.uid()));

-- =====================================================================
-- RPC — registrar_tentativa (é isso que faltava e travava o "Finalizar")
-- =====================================================================
create or replace function registrar_tentativa(
  p_question_id uuid,
  p_status text,
  p_alternativa uuid default null,
  p_session_id uuid default null,
  p_motivo_erro text default null,
  p_marcada_duvida boolean default false,
  p_tempo_segundos int default null
) returns void
language plpgsql
security invoker
as $$
begin
  insert into question_attempts(user_id, question_id, session_id, status, alternativa_escolhida, motivo_erro, marcada_duvida, tempo_segundos)
  values (auth.uid(), p_question_id, p_session_id, p_status, p_alternativa, p_motivo_erro, p_marcada_duvida, p_tempo_segundos);

  if p_status = 'errou' then
    insert into review_queue(user_id, question_id, status, proxima_revisao, concluida)
    values (auth.uid(), p_question_id, 'preciso_entender', current_date + 1, false)
    on conflict (user_id, question_id)
    do update set proxima_revisao = current_date + 1, concluida = false, status = 'preciso_entender';
  end if;
end;
$$;

-- =====================================================================
-- STREAK (sequencia_dias) — recalculada após cada sessão concluída
-- =====================================================================
create or replace function recompute_streak(p_user_id uuid) returns void
language plpgsql
security invoker
as $$
declare
  d date := current_date;
  streak int := 0;
  has_activity boolean;
begin
  loop
    select exists(
      select 1 from study_sessions where user_id = p_user_id and finalizada_em::date = d
      union all
      select 1 from focus_sessions where user_id = p_user_id and concluida and finalizada_em::date = d
    ) into has_activity;
    exit when not has_activity;
    streak := streak + 1;
    d := d - 1;
  end loop;
  update profiles set sequencia_dias = streak where id = p_user_id;
end;
$$;

create or replace function trg_recompute_streak() returns trigger
language plpgsql
security invoker
as $$
begin
  perform recompute_streak(new.user_id);
  return new;
end;
$$;

drop trigger if exists on_study_session_finalizada on study_sessions;
create trigger on_study_session_finalizada
  after insert or update of finalizada_em on study_sessions
  for each row when (new.finalizada_em is not null)
  execute function trg_recompute_streak();

drop trigger if exists on_focus_session_concluida on focus_sessions;
create trigger on_focus_session_concluida
  after insert or update of concluida on focus_sessions
  for each row when (new.concluida = true)
  execute function trg_recompute_streak();

-- =====================================================================
-- SEED — disciplinas (grupo "gerais" corrigido conforme edital oficial:
-- Português + Matemática/Raciocínio Lógico + Legislação Institucional)
-- =====================================================================
insert into disciplinas (slug, nome, bloco, peso_por_questao, cor, ordem) values

  ('portugues', 'Português', 'gerais', 1, '#8b5cf6', 1),
  ('matematica_raciocinio_logico', 'Matemática e Raciocínio Lógico', 'gerais', 1, '#22d3a7', 2),
  ('legislacao_institucional', 'Legislação Institucional', 'gerais', 1, '#ec4899', 3),
  ('direito_administrativo', 'Direito Administrativo', 'especificos', 2, '#f59e0b', 4),
  ('licitacoes_contratos', 'Licitações e Contratos (Lei 14.133/2021)', 'especificos', 2, '#4f8cff', 5),
  ('direito_constitucional', 'Direito Constitucional', 'especificos', 2, '#34d399', 6),
  ('controle_externo', 'Controle Externo', 'especificos', 2, '#fb7185', 7),
  ('afo', 'Administração Financeira e Orçamentária', 'especificos', 2, '#a78bfa', 8),
  ('contabilidade_publica', 'Contabilidade Pública', 'especificos', 2, '#67e8f9', 9),
  ('administracao_publica', 'Administração Pública', 'especificos', 2, '#e879f9', 10),
  ('administracao_geral', 'Administração Geral', 'especificos', 2, '#f97316', 11),
  ('administracao_estrategica', 'Administração Estratégica', 'especificos', 2, '#14b8a6', 12),
  ('comportamento_organizacional', 'Comportamento Organizacional', 'especificos', 2, '#c084fc', 13),
  ('gestao_pessoas', 'Gestão de Pessoas', 'especificos', 2, '#fbbf24', 14)

on conflict (slug) do update set nome=excluded.nome, bloco=excluded.bloco, peso_por_questao=excluded.peso_por_questao, cor=excluded.cor, ordem=excluded.ordem;

-- =====================================================================
-- SEED — tópicos
-- =====================================================================

insert into topicos (disciplina_id, nome, ordem)
select id, 'Interpretação de texto', 1 from disciplinas where slug='portugues'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Interpretação de texto');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Concordância verbal e nominal', 2 from disciplinas where slug='portugues'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Concordância verbal e nominal');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Regência verbal e nominal', 3 from disciplinas where slug='portugues'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Regência verbal e nominal');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Crase', 4 from disciplinas where slug='portugues'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Crase');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Pontuação', 5 from disciplinas where slug='portugues'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Pontuação');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Ortografia e acentuação', 6 from disciplinas where slug='portugues'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Ortografia e acentuação');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Proposições lógicas', 1 from disciplinas where slug='matematica_raciocinio_logico'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Proposições lógicas');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Porcentagem, razão e proporção', 2 from disciplinas where slug='matematica_raciocinio_logico'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Porcentagem, razão e proporção');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Regra de três', 3 from disciplinas where slug='matematica_raciocinio_logico'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Regra de três');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Conjuntos', 4 from disciplinas where slug='matematica_raciocinio_logico'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Conjuntos');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Sequências lógicas', 5 from disciplinas where slug='matematica_raciocinio_logico'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Sequências lógicas');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Lei Orgânica do TCE-GO', 1 from disciplinas where slug='legislacao_institucional'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Lei Orgânica do TCE-GO');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Regimento Interno do TCE-GO', 2 from disciplinas where slug='legislacao_institucional'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Regimento Interno do TCE-GO');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Princípios administrativos', 1 from disciplinas where slug='direito_administrativo'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Princípios administrativos');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Atos administrativos', 2 from disciplinas where slug='direito_administrativo'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Atos administrativos');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Poderes administrativos', 3 from disciplinas where slug='direito_administrativo'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Poderes administrativos');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Administração direta e indireta', 4 from disciplinas where slug='direito_administrativo'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Administração direta e indireta');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Responsabilidade civil do Estado', 5 from disciplinas where slug='direito_administrativo'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Responsabilidade civil do Estado');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Serviços públicos', 6 from disciplinas where slug='direito_administrativo'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Serviços públicos');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Controle da Administração Pública', 7 from disciplinas where slug='direito_administrativo'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Controle da Administração Pública');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Improbidade administrativa', 8 from disciplinas where slug='direito_administrativo'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Improbidade administrativa');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Acesso à informação', 9 from disciplinas where slug='direito_administrativo'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Acesso à informação');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Princípios da licitação', 1 from disciplinas where slug='licitacoes_contratos'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Princípios da licitação');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Modalidades de licitação', 2 from disciplinas where slug='licitacoes_contratos'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Modalidades de licitação');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Fases da licitação', 3 from disciplinas where slug='licitacoes_contratos'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Fases da licitação');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Contratos administrativos', 4 from disciplinas where slug='licitacoes_contratos'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Contratos administrativos');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Sanções e penalidades', 5 from disciplinas where slug='licitacoes_contratos'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Sanções e penalidades');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Princípios fundamentais', 1 from disciplinas where slug='direito_constitucional'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Princípios fundamentais');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Direitos e garantias fundamentais', 2 from disciplinas where slug='direito_constitucional'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Direitos e garantias fundamentais');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Organização do Estado', 3 from disciplinas where slug='direito_constitucional'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Organização do Estado');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Administração Pública na Constituição', 4 from disciplinas where slug='direito_constitucional'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Administração Pública na Constituição');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Sistema de controle da Administração Pública', 1 from disciplinas where slug='controle_externo'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Sistema de controle da Administração Pública');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Tribunais de Contas — competências', 2 from disciplinas where slug='controle_externo'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Tribunais de Contas — competências');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Fiscalização contábil, financeira e orçamentária', 3 from disciplinas where slug='controle_externo'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Fiscalização contábil, financeira e orçamentária');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Prestação e tomada de contas', 4 from disciplinas where slug='controle_externo'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Prestação e tomada de contas');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Orçamento público — princípios', 1 from disciplinas where slug='afo'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Orçamento público — princípios');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Ciclo orçamentário', 2 from disciplinas where slug='afo'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Ciclo orçamentário');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Receita e despesa pública', 3 from disciplinas where slug='afo'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Receita e despesa pública');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Créditos adicionais', 4 from disciplinas where slug='afo'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Créditos adicionais');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Lei de Responsabilidade Fiscal', 5 from disciplinas where slug='afo'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Lei de Responsabilidade Fiscal');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Conceitos e princípios', 1 from disciplinas where slug='contabilidade_publica'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Conceitos e princípios');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Patrimônio público', 2 from disciplinas where slug='contabilidade_publica'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Patrimônio público');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Demonstrações contábeis aplicadas ao setor público', 3 from disciplinas where slug='contabilidade_publica'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Demonstrações contábeis aplicadas ao setor público');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Modelos de administração (patrimonial, burocrática, gerencial)', 1 from disciplinas where slug='administracao_publica'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Modelos de administração (patrimonial, burocrática, gerencial)');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Princípios constitucionais da Administração', 2 from disciplinas where slug='administracao_publica'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Princípios constitucionais da Administração');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Funções da administração (PODC)', 1 from disciplinas where slug='administracao_geral'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Funções da administração (PODC)');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Estruturas organizacionais', 2 from disciplinas where slug='administracao_geral'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Estruturas organizacionais');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Planejamento estratégico', 1 from disciplinas where slug='administracao_estrategica'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Planejamento estratégico');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Ferramentas de análise (SWOT, BSC)', 2 from disciplinas where slug='administracao_estrategica'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Ferramentas de análise (SWOT, BSC)');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Motivação e liderança', 1 from disciplinas where slug='comportamento_organizacional'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Motivação e liderança');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Cultura e clima organizacional', 2 from disciplinas where slug='comportamento_organizacional'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Cultura e clima organizacional');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Recrutamento e seleção', 1 from disciplinas where slug='gestao_pessoas'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Recrutamento e seleção');
insert into topicos (disciplina_id, nome, ordem)
select id, 'Avaliação de desempenho', 2 from disciplinas where slug='gestao_pessoas'
and not exists (select 1 from topicos t where t.disciplina_id=disciplinas.id and t.nome='Avaliação de desempenho');


-- =====================================================================
-- SEED — questões inéditas (estilo FCC), 5 alternativas cada
-- Todas com origem_tipo='inedita' — nunca aparecem como questão oficial.
-- =====================================================================

do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='portugues';
  select id into tid from topicos where disciplina_id=did and nome='Interpretação de texto';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Em um texto dissertativo-argumentativo, a tese do autor é:', 'A tese é a posição central defendida pelo autor, sustentada por argumentos ao longo do texto.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A repetição literal do título do texto', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A ideia central que o autor defende e busca comprovar ao longo do texto', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Um resumo de todos os parágrafos do texto', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A opinião do leitor sobre o assunto', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A conclusão de um texto narrativo', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='portugues';
  select id into tid from topicos where disciplina_id=did and nome='Interpretação de texto';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Assinale a alternativa que indica corretamente a relação lógica estabelecida pelo conectivo "embora" numa frase como "Embora estivesse cansada, terminou o relatório":', '"Embora" introduz uma oração concessiva, indicando um fato que poderia impedir a ação principal, mas não impede.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Causa', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Consequência', false, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Concessão', true, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Condição', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Finalidade', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='portugues';
  select id into tid from topicos where disciplina_id=did and nome='Interpretação de texto';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Em textos oficiais e técnicos, a coesão referencial é obtida principalmente por meio de:', 'A coesão referencial ocorre por retomada (anáfora) ou antecipação (catáfora) de termos, evitando repetições desnecessárias.', 'avancado', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Uso exclusivo de sinônimos raros', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Pronomes, elipses e expressões que retomam ou antecipam termos já citados', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Repetição idêntica das mesmas palavras em todo o texto', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Ausência total de conectivos', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Uso de gírias regionais', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='portugues';
  select id into tid from topicos where disciplina_id=did and nome='Concordância verbal e nominal';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Assinale a frase com concordância verbal correta:', 'O verbo "fazer" indicando tempo decorrido é impessoal e fica na 3ª pessoa do singular: "Faz dois anos".', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Fazem dois anos que ele trabalha no tribunal.', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Faz dois anos que ele trabalha no tribunal.', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Fazem dois anos que eles trabalham no tribunal, respectivamente.', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Faziam dois anos que ele trabalhava, na época.', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Há de fazer dois anos, aproximadamente, sempre.', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='portugues';
  select id into tid from topicos where disciplina_id=did and nome='Concordância verbal e nominal';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, '"A maioria dos servidores ___ favorável à mudança." Assinale a opção que preenche corretamente a lacuna, considerando a concordância mais adequada em prova de concurso:', 'Com sujeitos coletivos partitivos ("a maioria de"), admite-se a concordância com o núcleo (singular) ou com o especificador no plural.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'são', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'é ou são (concordância pode ser com o núcleo "maioria" ou com o adjunto "servidores")', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'estão sendo', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'seria', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'fossem', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='portugues';
  select id into tid from topicos where disciplina_id=did and nome='Regência verbal e nominal';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Assinale a alternativa em que a regência verbal está de acordo com a norma-padrão:', '"Obedecer" exige a preposição "a": obedeceu às normas. As demais alternativas trazem desvios de regência (assistir a, aspirar a, preferir a, chegar a).', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Assistiu o jogo pela televisão, atentamente.', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Aspirava um cargo mais alto na carreira.', false, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Prefiro café do que chá.', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Obedeceu às normas do edital.', true, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Chegou no tribunal às oito horas.', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='portugues';
  select id into tid from topicos where disciplina_id=did and nome='Crase';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Assinale a alternativa em que o uso do acento grave (crase) está correto:', '"À disposição" é uma locução consagrada que exige crase. Nas demais, há erro: nomes de lugares sem artigo não recebem crase automaticamente, pronomes pessoais e "a pé" não admitem crase.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Ele se dirigiu à Goiânia ontem.', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Entreguei o documento à ela.', false, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Fico à disposição para esclarecimentos.', true, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Vou à pé até o tribunal.', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Referiu-se à v.exa. no ofício.', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='portugues';
  select id into tid from topicos where disciplina_id=did and nome='Pontuação';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Assinale a frase pontuada corretamente:', 'A oração "que chegou atrasado" é explicativa e deve vir isolada por vírgulas quando se refere a um sujeito já identificado.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'O servidor, que chegou atrasado foi advertido.', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'O servidor que chegou atrasado, foi advertido.', false, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'O servidor, que chegou atrasado, foi advertido.', true, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'O servidor que, chegou atrasado foi advertido.', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'O servidor que chegou, atrasado foi advertido.', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='portugues';
  select id into tid from topicos where disciplina_id=did and nome='Ortografia e acentuação';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Assinale a alternativa em que todas as palavras estão grafadas corretamente:', 'As formas corretas são "benefício", "privilégio" e "ascensão".', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Beneficiente, previlégio, ascensão', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Benefício, privilégio, ascensão', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Benefício, previlégio, ascenção', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Beneficiente, privilégio, ascenção', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Benefíssio, privilégio, ascensão', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='portugues';
  select id into tid from topicos where disciplina_id=did and nome='Ortografia e acentuação';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Assinale a alternativa em que a palavra está acentuada pela mesma regra que justifica o acento em "órgão":', '"Órgão" e "fácil" são paroxítonas terminadas em ditongo/consoante que seguem regra de acentuação de paroxítonas; as demais são oxítonas ou monossílabos tônicos.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Fácil', true, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Você', false, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Ninguém', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Também', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Já', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='matematica_raciocinio_logico';
  select id into tid from topicos where disciplina_id=did and nome='Proposições lógicas';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'A negação da proposição "Todos os servidores foram aprovados" é:', 'A negação de "todos são X" é "pelo menos um não é X", ou seja, "algum servidor não foi aprovado".', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Nenhum servidor foi aprovado', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Algum servidor não foi aprovado', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Todos os servidores não foram aprovados', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Poucos servidores foram aprovados', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Todos os servidores foram reprovados', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='matematica_raciocinio_logico';
  select id into tid from topicos where disciplina_id=did and nome='Proposições lógicas';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Se a proposição "P e Q" é falsa, e P é verdadeira, então Q é:', 'Numa conjunção (E), o resultado só é verdadeiro se ambas as partes forem verdadeiras. Sendo P verdadeira e o conjunto falso, Q deve ser falsa.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Verdadeira', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Falsa', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Indeterminada', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Também composta', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Necessariamente P', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='matematica_raciocinio_logico';
  select id into tid from topicos where disciplina_id=did and nome='Porcentagem, razão e proporção';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Um servidor acertou 42 de 60 questões de uma prova. Isso corresponde a que percentual de acerto?', '42/60 = 0,70, ou seja, 70% de aproveitamento.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, '60%', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, '70%', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, '65%', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, '75%', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, '80%', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='matematica_raciocinio_logico';
  select id into tid from topicos where disciplina_id=did and nome='Porcentagem, razão e proporção';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Um valor de R$ 1.200,00 sofre um aumento de 15% e, em seguida, um desconto de 10% sobre o novo valor. O valor final é:', '1.200 × 1,15 = 1.380; 1.380 × 0,90 = 1.242,00.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'R$ 1.230,00', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'R$ 1.242,00', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'R$ 1.200,00', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'R$ 1.218,00', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'R$ 1.260,00', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='matematica_raciocinio_logico';
  select id into tid from topicos where disciplina_id=did and nome='Regra de três';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Se 5 técnicos concluem uma tarefa em 8 dias, trabalhando no mesmo ritmo, quantos dias levariam 4 técnicos para concluir a mesma tarefa?', 'Regra de três inversa: 5×8 = 4×x → x = 40/4 = 10 dias.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, '6 dias', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, '8 dias', false, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, '10 dias', true, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, '12 dias', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, '4 dias', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='matematica_raciocinio_logico';
  select id into tid from topicos where disciplina_id=did and nome='Conjuntos';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Em uma repartição, 30 servidores falam inglês, 20 falam espanhol e 8 falam os dois idiomas. Quantos servidores falam pelo menos um dos dois idiomas?', '|A∪B| = |A|+|B|-|A∩B| = 30+20-8 = 42.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, '50', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, '42', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, '38', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, '46', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, '58', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='matematica_raciocinio_logico';
  select id into tid from topicos where disciplina_id=did and nome='Sequências lógicas';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Considere a sequência 3, 7, 11, 15, ... . Qual é o próximo termo?', 'A sequência tem razão constante 4 (progressão aritmética): 15+4=19.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, '17', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, '18', false, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, '19', true, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, '20', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, '21', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='legislacao_institucional';
  select id into tid from topicos where disciplina_id=did and nome='Lei Orgânica do TCE-GO';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'A Lei Orgânica de um Tribunal de Contas estadual tem como principal função:', 'A Lei Orgânica de um Tribunal de Contas estabelece sua estrutura, competências, processo de julgamento de contas e funcionamento interno.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Substituir a Constituição Estadual em matéria orçamentária', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Disciplinar a organização, competências e funcionamento do Tribunal de Contas', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Regular exclusivamente o processo eleitoral estadual', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Definir o orçamento anual de todos os órgãos do Estado', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Regulamentar apenas o regime de pessoal do Poder Executivo', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='legislacao_institucional';
  select id into tid from topicos where disciplina_id=did and nome='Lei Orgânica do TCE-GO';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'No exercício de suas competências de controle externo, um Tribunal de Contas estadual julga, entre outras, as contas de:', 'Compete aos Tribunais de Contas julgar as contas de administradores e responsáveis por bens, dinheiros e valores públicos da administração direta e indireta.', 'avancado', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Apenas o Governador do Estado', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Administradores e demais responsáveis por dinheiros, bens e valores públicos da administração direta e indireta', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Somente empresas privadas que contratam com o poder público', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Exclusivamente os membros do Poder Judiciário estadual', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Apenas os partidos políticos com representação na Assembleia', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='legislacao_institucional';
  select id into tid from topicos where disciplina_id=did and nome='Regimento Interno do TCE-GO';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'O Regimento Interno de um Tribunal de Contas tem por finalidade principal:', 'O Regimento Interno detalha o funcionamento interno do órgão, a organização de seus colegiados e a tramitação dos processos, em conformidade com a Lei Orgânica.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Criar novos cargos efetivos no quadro de pessoal', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Disciplinar o funcionamento interno, a tramitação processual e a organização dos trabalhos do Tribunal', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Substituir a Lei Orgânica em caso de conflito', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Definir alíquotas de tributos estaduais', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Regular concursos públicos de outros órgãos', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='legislacao_institucional';
  select id into tid from topicos where disciplina_id=did and nome='Regimento Interno do TCE-GO';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Segundo a prática regimental usual dos Tribunais de Contas, o julgamento colegiado dos processos ocorre, em regra, em:', 'O julgamento colegiado ocorre em sessões (Plenário ou Câmaras), com quórum e publicidade definidos no Regimento Interno.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Sessões públicas do Plenário ou de Câmaras, conforme a competência definida no Regimento', true, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Reuniões privadas sem registro em ata', false, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Deliberação exclusiva e individual do Presidente', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Assembleias abertas à população em geral, sem quórum definido', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Decisão do servidor responsável pela instrução do processo', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='direito_administrativo';
  select id into tid from topicos where disciplina_id=did and nome='Princípios administrativos';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'São princípios expressos da Administração Pública no art. 37 da Constituição Federal:', 'O art. 37, caput, da CF/88 elenca expressamente: legalidade, impessoalidade, moralidade, publicidade e eficiência (LIMPE).', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Legalidade, impessoalidade, moralidade, publicidade e eficiência', true, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Legalidade, hierarquia, autotutela, subsidiariedade e razoabilidade', false, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Impessoalidade, proporcionalidade, economicidade, boa-fé e eficácia', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Moralidade, publicidade, celeridade, gratuidade e livre iniciativa', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Legalidade, eficiência, lucratividade, hierarquia e subsidiariedade', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='direito_administrativo';
  select id into tid from topicos where disciplina_id=did and nome='Princípios administrativos';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'O princípio da impessoalidade impõe à Administração Pública, entre outras consequências, que:', 'A impessoalidade exige que a atuação administrativa seja voltada ao interesse público, sem favorecimentos ou perseguições pessoais.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Os atos administrativos sejam sempre sigilosos', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A atuação administrativa não favoreça nem prejudique pessoas determinadas, voltando-se ao interesse público', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Os agentes públicos possam usar bens públicos para fins particulares, desde que autorizados verbalmente', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'As decisões administrativas dependam exclusivamente da vontade do agente', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A publicidade dos atos seja facultativa', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='direito_administrativo';
  select id into tid from topicos where disciplina_id=did and nome='Atos administrativos';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'São atributos clássicos do ato administrativo:', 'Os atributos clássicos são: presunção de legitimidade/veracidade, imperatividade, autoexecutoriedade e tipicidade.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Presunção de legitimidade, imperatividade, autoexecutoriedade e tipicidade', true, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Retroatividade, gratuidade, informalidade e subsidiariedade', false, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Onerosidade, pessoalidade, revogabilidade absoluta e sigilo', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Consensualidade, bilateralidade e inegociabilidade', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Perpetuidade, incondicionalidade e irretratabilidade', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='direito_administrativo';
  select id into tid from topicos where disciplina_id=did and nome='Atos administrativos';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Um ato administrativo praticado por autoridade incompetente, mas que poderia ser praticado por outra autoridade da mesma Administração, admite, em regra:', 'Vícios de competência (não exclusiva) são sanáveis por convalidação, desde que não causem prejuízo e não se trate de competência indelegável.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Apenas a anulação, nunca a convalidação', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A convalidação, desde que não se trate de competência exclusiva e o vício seja sanável', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A conversão automática em ato de outra natureza', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A revogação por conveniência, exclusivamente', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A manutenção do ato sem qualquer necessidade de correção', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='direito_administrativo';
  select id into tid from topicos where disciplina_id=did and nome='Atos administrativos';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'A diferença essencial entre anulação e revogação de um ato administrativo está em que:', 'Anulação: vício de legalidade, efeitos retroativos (ex tunc). Revogação: juízo de conveniência/oportunidade sobre ato válido, efeitos prospectivos (ex nunc), respeitados direitos adquiridos.', 'avancado', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A anulação opera efeitos ex nunc e a revogação, ex tunc', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A anulação decorre de ilegalidade e retroage (ex tunc); a revogação decorre de conveniência e oportunidade e opera ex nunc', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Somente o Poder Judiciário pode revogar atos administrativos', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A revogação pode atingir atos que já geraram direitos adquiridos, sem exceção', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A anulação é sempre discricionária', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='direito_administrativo';
  select id into tid from topicos where disciplina_id=did and nome='Poderes administrativos';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'O poder que permite à Administração impor, unilateralmente, obrigações a terceiros, independentemente de sua concordância, é denominado:', 'O poder de polícia (e, de modo mais amplo, o chamado poder extroverso) permite à Administração condicionar e restringir direitos de terceiros, unilateralmente, em nome do interesse público.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Poder regulamentar', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Poder discricionário', false, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Poder de polícia ou poder extroverso, conforme a manifestação', true, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Poder hierárquico, exclusivamente', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Poder vinculado', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='direito_administrativo';
  select id into tid from topicos where disciplina_id=did and nome='Poderes administrativos';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'O poder hierárquico confere à Administração, entre outras prerrogativas, a de:', 'O poder hierárquico organiza a estrutura interna da Administração, permitindo ordenar, coordenar, controlar e corrigir a atuação dos subordinados.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Punir infrações cometidas por particulares em geral', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Editar regulamentos com força de lei', false, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Dar ordens, fiscalizar, rever atos de subordinados e distribuir competências internamente', true, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Delegar competência ao Poder Legislativo', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Suprimir direitos fundamentais de servidores', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='direito_administrativo';
  select id into tid from topicos where disciplina_id=did and nome='Administração direta e indireta';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Integram a Administração Pública indireta, entre outras entidades:', 'A Administração indireta é composta por autarquias, fundações públicas, empresas públicas e sociedades de economia mista, dotadas de personalidade jurídica própria.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Ministérios e Secretarias de Estado', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Autarquias, fundações públicas, empresas públicas e sociedades de economia mista', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Apenas os órgãos de cúpula do Poder Executivo', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'O Poder Legislativo e o Poder Judiciário, em sua totalidade', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Somente os órgãos sem personalidade jurídica própria', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='direito_administrativo';
  select id into tid from topicos where disciplina_id=did and nome='Administração direta e indireta';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Uma característica que diferencia as autarquias das empresas públicas é que as autarquias:', 'Autarquias têm personalidade jurídica de direito público, criadas por lei específica, e normalmente exercem atividades típicas de Estado; empresas públicas têm personalidade de direito privado.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'São regidas integralmente pelo regime jurídico de direito privado', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Possuem personalidade jurídica de direito público e exercem, tipicamente, atividades típicas de Estado', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Nunca possuem patrimônio próprio', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'São sempre criadas por decreto, sem necessidade de lei', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Não se sujeitam a controle do Tribunal de Contas', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='direito_administrativo';
  select id into tid from topicos where disciplina_id=did and nome='Responsabilidade civil do Estado';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Segundo a teoria adotada pela Constituição Federal para a responsabilidade civil do Estado por danos causados por seus agentes, no exercício da função, a responsabilidade é, em regra:', 'Prevalece a teoria da responsabilidade objetiva (art. 37, §6º, CF), bastando dano, conduta do agente na função e nexo causal, sem necessidade de provar culpa do Estado.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Subjetiva, dependendo da comprovação de dolo ou culpa do Estado', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Objetiva, bastando a comprovação do dano, da conduta do agente e do nexo causal', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Inexistente, pois o Estado é imune a indenizações', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Sempre solidária com o agente, independentemente de regresso', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Limitada exclusivamente a danos materiais, nunca morais', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='direito_administrativo';
  select id into tid from topicos where disciplina_id=did and nome='Responsabilidade civil do Estado';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Diante da responsabilidade objetiva do Estado, o direito de regresso contra o agente público causador do dano depende de:', 'Embora a responsabilidade do Estado perante a vítima seja objetiva, o regresso contra o agente exige comprovação de dolo ou culpa (responsabilidade subjetiva do agente).', 'avancado', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Nada, pois é automático e independe de comprovação', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Comprovação de dolo ou culpa do agente, em ação de regresso', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Autorização prévia do Tribunal de Contas', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Concordância expressa do próprio agente', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Decisão do Poder Legislativo', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='direito_administrativo';
  select id into tid from topicos where disciplina_id=did and nome='Serviços públicos';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'São formas de prestação de serviços públicos pelo Estado:', 'O serviço público pode ser prestado diretamente pelo Estado ou indiretamente, por delegação (concessão, permissão, autorização), sempre sob regulação estatal.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Apenas execução direta, sem possibilidade de delegação', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Execução direta pela Administração ou indireta, mediante concessão, permissão ou autorização', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Exclusivamente por meio de empresas privadas, sem qualquer regulação', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Somente por convênios internacionais', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Apenas por meio de parcerias com organismos privados sem fins lucrativos', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='direito_administrativo';
  select id into tid from topicos where disciplina_id=did and nome='Controle da Administração Pública';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'O controle exercido pelos Tribunais de Contas sobre a Administração Pública é classificado, quanto ao órgão que o exerce, como:', 'Os Tribunais de Contas exercem controle externo, auxiliando o Poder Legislativo na fiscalização contábil, financeira e orçamentária.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Controle interno', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Controle externo', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Controle judicial exclusivo', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Controle popular direto', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Controle social informal', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='direito_administrativo';
  select id into tid from topicos where disciplina_id=did and nome='Improbidade administrativa';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Constitui ato de improbidade administrativa, entre outras hipóteses previstas em lei, aquele que:', 'A Lei de Improbidade Administrativa tipifica atos que causam enriquecimento ilícito, prejuízo ao erário ou atentam contra os princípios da Administração, exigindo dolo, conforme alterações legislativas recentes.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Gera prejuízo ao erário, atenta contra os princípios da Administração ou importa enriquecimento ilícito', true, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Decorre de mera divergência de interpretação de norma legal, sem dolo', false, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Consiste em simples atraso na entrega de relatório, sem qualquer prejuízo', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Se refere apenas a crimes eleitorais', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Aplica-se exclusivamente a agentes políticos, nunca a servidores', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='direito_administrativo';
  select id into tid from topicos where disciplina_id=did and nome='Acesso à informação';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Segundo a legislação de acesso à informação, a regra geral aplicável aos dados e documentos públicos é:', 'A Lei de Acesso à Informação consagra a publicidade como regra e o sigilo como exceção, justificada em hipóteses legalmente previstas (sigilo pessoal, segurança do Estado, etc.).', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'O sigilo absoluto, salvo autorização judicial', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A publicidade, sendo o sigilo exceção, admitido apenas em hipóteses legalmente previstas', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A publicidade apenas para a imprensa credenciada', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'O acesso restrito a servidores do próprio órgão', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A necessidade de justificativa do requerente para qualquer pedido', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='licitacoes_contratos';
  select id into tid from topicos where disciplina_id=did and nome='Princípios da licitação';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'A Lei nº 14.133/2021 estabelece expressamente, entre os princípios que regem as licitações e contratações, além da legalidade e impessoalidade:', 'Entre os princípios da Lei 14.133/2021 estão o julgamento objetivo e a busca pela proposta mais vantajosa, junto com legalidade, impessoalidade, moralidade, publicidade, entre outros.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A gratuidade obrigatória de todos os contratos', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'O julgamento objetivo e a busca da proposta mais vantajosa', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A vedação à publicidade dos atos licitatórios', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A exclusão obrigatória de microempresas', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A obrigatoriedade de contratação verbal em casos de urgência', false, 5);
end $$;do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='licitacoes_contratos';
  select id into tid from topicos where disciplina_id=did and nome='Modalidades de licitação';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'São modalidades de licitação previstas na Lei nº 14.133/2021:', 'A Lei 14.133/2021 prevê como modalidades: pregão, concorrência, concurso, leilão e diálogo competitivo (extinguindo convite e tomada de preços da lei anterior).', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Convite, tomada de preços e concorrência, exclusivamente', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Pregão, concorrência, concurso, leilão e diálogo competitivo', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Apenas pregão eletrônico', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Tomada de preços e carta-convite, apenas', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Licitação verbal e licitação simplificada', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='licitacoes_contratos';
  select id into tid from topicos where disciplina_id=did and nome='Modalidades de licitação';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'O diálogo competitivo, modalidade introduzida pela Lei nº 14.133/2021, é adequado, entre outras hipóteses, para contratações que envolvam:', 'O diálogo competitivo destina-se a contratações complexas, com inovação técnica ou tecnológica, quando a Administração não tem, de antemão, a solução mais adequada definida.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Objetos simples e de baixo valor, sem inovação técnica', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Inovação tecnológica ou técnica, ou quando a Administração não conseguir definir previamente a solução mais adequada', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Aquisição de bens de prateleira, com especificações padronizadas', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Contratação direta sem qualquer processo licitatório', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Compras de pequeno valor realizadas por dispensa', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='licitacoes_contratos';
  select id into tid from topicos where disciplina_id=did and nome='Fases da licitação';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Na sequência procedimental estabelecida pela Lei nº 14.133/2021 para a licitação, a fase de julgamento das propostas ocorre, via de regra:', 'A Lei 14.133/2021 consolidou, como regra, a inversão de fases: julgamento das propostas antes da habilitação, salvo exceções previstas na própria lei.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Antes da fase preparatória', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Após a apresentação de propostas e antes da fase de habilitação (regra geral da inversão de fases)', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Somente após a assinatura do contrato', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Concomitantemente à publicação do edital', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Após a homologação', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='licitacoes_contratos';
  select id into tid from topicos where disciplina_id=did and nome='Contratos administrativos';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Uma das prerrogativas da Administração nos contratos administrativos, decorrente do regime jurídico de direito público, é a possibilidade de:', 'As chamadas cláusulas exorbitantes conferem à Administração prerrogativas como alteração e rescisão unilaterais, fiscalização e aplicação de penalidades, dentro dos limites legais.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Alterar unilateralmente cláusulas contratuais, respeitados os limites legais', true, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Descumprir o contrato sem qualquer consequência', false, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Transferir o contrato a terceiros sem anuência da Administração', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Eliminar o direito ao equilíbrio econômico-financeiro do contratado', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Impedir qualquer fiscalização externa do contrato', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='licitacoes_contratos';
  select id into tid from topicos where disciplina_id=did and nome='Sanções e penalidades';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Entre as sanções administrativas previstas na Lei nº 14.133/2021 para infrações cometidas por licitantes ou contratados, encontra-se:', 'A Lei 14.133/2021 prevê sanções como advertência, multa, impedimento de licitar e contratar e declaração de inidoneidade para licitar ou contratar, aplicadas mediante processo administrativo.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Apenas a advertência verbal, sem registro', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Advertência, multa, impedimento de licitar e contratar, e declaração de inidoneidade', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Prisão administrativa imediata', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Cassação de mandato eletivo', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Confisco de bens pessoais do sócio, sem processo', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='direito_constitucional';
  select id into tid from topicos where disciplina_id=did and nome='Princípios fundamentais';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'São fundamentos da República Federativa do Brasil, conforme o art. 1º da Constituição Federal:', 'O art. 1º da CF/88 elenca como fundamentos: soberania, cidadania, dignidade da pessoa humana, valores sociais do trabalho e da livre iniciativa e pluralismo político.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Soberania, cidadania, dignidade da pessoa humana, valores sociais do trabalho e da livre iniciativa, e pluralismo político', true, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Legalidade, publicidade, impessoalidade, moralidade e eficiência', false, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Independência, harmonia e separação absoluta entre os Poderes', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Livre concorrência, propriedade privada e função social da empresa', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'República, federação, presidencialismo e bicameralismo', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='direito_constitucional';
  select id into tid from topicos where disciplina_id=did and nome='Direitos e garantias fundamentais';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'O remédio constitucional adequado para proteger direito líquido e certo, não amparado por habeas corpus ou habeas data, lesado por ato de autoridade pública, é:', 'O mandado de segurança protege direito líquido e certo, quando não amparado por habeas corpus ou habeas data, contra ato de autoridade pública.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Ação popular', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Mandado de segurança', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Ação civil pública', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Mandado de injunção', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Habeas corpus', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='direito_constitucional';
  select id into tid from topicos where disciplina_id=did and nome='Organização do Estado';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'São entes que compõem a organização político-administrativa da República Federativa do Brasil:', 'A CF/88 estabelece a organização político-administrativa em União, Estados, Distrito Federal e Municípios, todos dotados de autonomia.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Apenas a União e os Estados', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A União, os Estados, o Distrito Federal e os Municípios, todos autônomos', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Somente a União, de forma centralizada', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Estados e Municípios, sem autonomia da União', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Apenas o Distrito Federal e a União', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='direito_constitucional';
  select id into tid from topicos where disciplina_id=did and nome='Administração Pública na Constituição';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Segundo a Constituição Federal, a investidura em cargo ou emprego público depende, em regra, de:', 'O art. 37, II, da CF/88 exige aprovação prévia em concurso público de provas ou de provas e títulos, ressalvadas as nomeações para cargos em comissão.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Aprovação prévia em concurso público de provas ou de provas e títulos', true, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Indicação política, sem necessidade de processo seletivo', false, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Livre escolha do chefe do Poder Executivo, em qualquer caso', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Herança de cargo público entre familiares', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Simples experiência profissional comprovada, sem seleção formal', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='controle_externo';
  select id into tid from topicos where disciplina_id=did and nome='Sistema de controle da Administração Pública';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'O controle externo da Administração Pública, no âmbito estadual, é exercido pelo Poder Legislativo com o auxílio:', 'O controle externo é exercido pelo Poder Legislativo com o auxílio do Tribunal de Contas, conforme modelo da CF/88 aplicável aos Estados.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Do Ministério Público Estadual, exclusivamente', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Do Tribunal de Contas do Estado', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Do Poder Judiciário estadual', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Da Controladoria-Geral da União', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'De órgãos privados de auditoria contratados livremente', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='controle_externo';
  select id into tid from topicos where disciplina_id=did and nome='Tribunais de Contas — competências';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Entre as competências típicas de um Tribunal de Contas estadual está:', 'Compete ao Tribunal de Contas julgar as contas de administradores e demais responsáveis, além de emitir parecer prévio sobre as contas do Chefe do Executivo, submetido a julgamento do Legislativo.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Legislar sobre matéria tributária estadual', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Julgar as contas dos administradores públicos e apreciar, para fins de emissão de parecer prévio, as contas do Chefe do Poder Executivo', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Processar e julgar crimes comuns cometidos por servidores', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Nomear diretamente Secretários de Estado', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Aprovar o orçamento anual do Estado, substituindo a Assembleia Legislativa', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='controle_externo';
  select id into tid from topicos where disciplina_id=did and nome='Fiscalização contábil, financeira e orçamentária';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'A fiscalização contábil, financeira, orçamentária, operacional e patrimonial da Administração Pública, quanto à legalidade, legitimidade e economicidade, é realizada mediante as seguintes formas de controle, entre outras:', 'A Constituição prevê a fiscalização exercida de forma integrada pelo sistema de controle interno de cada Poder e pelo controle externo (Tribunal de Contas).', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Apenas auditoria interna do próprio órgão fiscalizado', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Fiscalização contábil, operacional e patrimonial exercida pelo controle interno e pelo controle externo, de forma integrada', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Somente controle popular direto, sem participação de órgãos técnicos', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Fiscalização exclusivamente eleitoral', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Controle apenas sobre atos de natureza penal', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='controle_externo';
  select id into tid from topicos where disciplina_id=did and nome='Prestação e tomada de contas';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'A tomada de contas especial é um processo instaurado, tipicamente, quando:', 'A tomada de contas especial é instaurada diante de omissão no dever de prestar contas, ou de indício de irregularidade que resulte em dano ao erário, para apurar responsabilidade e quantificar o dano.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'O gestor apresenta suas contas anuais regularmente, sem qualquer irregularidade', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Há omissão no dever de prestar contas ou indícios de irregularidade que causem dano ao erário', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'O órgão deseja apenas prestar informações estatísticas', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Ocorre eleição de novos dirigentes, independentemente de irregularidade', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'O Tribunal de Contas decide arquivar o processo sem análise', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='afo';
  select id into tid from topicos where disciplina_id=did and nome='Orçamento público — princípios';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'O princípio orçamentário segundo o qual todas as receitas e despesas devem constar de uma única lei orçamentária, vedada a existência de fundos não incluídos no orçamento, denomina-se:', 'O princípio da unidade determina que o orçamento deve ser uno, reunindo todas as receitas e despesas em um único documento.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Princípio da anualidade', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Princípio da unidade', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Princípio da universalidade', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Princípio do equilíbrio', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Princípio da exclusividade', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='afo';
  select id into tid from topicos where disciplina_id=did and nome='Orçamento público — princípios';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'O princípio orçamentário que veda o início de programas ou projetos não incluídos na lei orçamentária anual é o princípio da:', 'O princípio da anualidade (ou periodicidade) estabelece que o orçamento vigora por um exercício financeiro, sendo vedado iniciar programas não previstos na LOA daquele período.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Legalidade orçamentária', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Universalidade', false, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Anualidade', true, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Exclusividade', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Não afetação de receitas', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='afo';
  select id into tid from topicos where disciplina_id=did and nome='Ciclo orçamentário';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Compõem o ciclo orçamentário, entre outras etapas:', 'O ciclo orçamentário compreende, de forma geral: elaboração da proposta, discussão e aprovação legislativa, execução orçamentária e controle/avaliação dos resultados.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Apenas a elaboração da proposta orçamentária', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Elaboração, discussão e aprovação, execução, e controle e avaliação', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Somente a fase de execução da despesa', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Exclusivamente a fiscalização pelo Tribunal de Contas', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Apenas a sanção presidencial ou do governador', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='afo';
  select id into tid from topicos where disciplina_id=did and nome='Receita e despesa pública';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Os estágios da despesa pública, segundo a Lei nº 4.320/1964, compreendem:', 'Os estágios da despesa pública são: empenho, liquidação e pagamento (a fixação, arrecadação e recolhimento referem-se à receita).', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Lançamento, arrecadação e recolhimento', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Empenho, liquidação e pagamento', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Previsão, arrecadação e transferência', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Fixação, arrecadação e recolhimento', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Autorização, homologação e adjudicação', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='afo';
  select id into tid from topicos where disciplina_id=did and nome='Créditos adicionais';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Os créditos adicionais destinados a despesas urgentes e imprevisíveis, como em caso de calamidade pública, para as quais não há dotação orçamentária específica, são denominados créditos:', 'Créditos extraordinários destinam-se a despesas urgentes e imprevisíveis, como guerra, comoção interna ou calamidade pública, podendo ser abertos por medida provisória ou decreto, conforme o caso.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Suplementares', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Especiais', false, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Extraordinários', true, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Provisórios', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Rotativos', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='afo';
  select id into tid from topicos where disciplina_id=did and nome='Lei de Responsabilidade Fiscal';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'A Lei de Responsabilidade Fiscal estabelece, como um de seus principais instrumentos de planejamento e controle, a exigência de compatibilidade entre:', 'A LRF exige compatibilidade entre a LOA e as metas fiscais fixadas na LDO, reforçando o planejamento fiscal responsável.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'O orçamento e o plano de carreira dos servidores', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A Lei Orçamentária Anual (LOA) e as metas fiscais estabelecidas na Lei de Diretrizes Orçamentárias (LDO)', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'O orçamento municipal e o orçamento da União, de forma automática', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Apenas as despesas com pessoal do Poder Judiciário', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'As leis tributárias estaduais e federais, exclusivamente', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='contabilidade_publica';
  select id into tid from topicos where disciplina_id=did and nome='Conceitos e princípios';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'A Contabilidade Pública tem por objeto, fundamentalmente:', 'A Contabilidade Pública registra e evidencia os atos e fatos relacionados ao patrimônio público e à execução orçamentária, financeira e patrimonial das entidades do setor público.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Apenas o controle de estoques de empresas privadas', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'O patrimônio público e as variações decorrentes da execução orçamentária, financeira e patrimonial', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Exclusivamente a apuração de tributos federais', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'O controle de metas eleitorais', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A fiscalização de contratos trabalhistas privados', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='contabilidade_publica';
  select id into tid from topicos where disciplina_id=did and nome='Patrimônio público';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'No âmbito da Contabilidade Aplicada ao Setor Público, os bens, direitos e valores pertencentes a uma entidade pública compõem o(a):', 'O ativo representa os bens, direitos e valores da entidade, integrando o patrimônio público ao lado do passivo e do patrimônio líquido.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Passivo exclusivamente', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Ativo do patrimônio público', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Resultado orçamentário apenas', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Superávit financeiro obrigatoriamente', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Dívida consolidada líquida', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='contabilidade_publica';
  select id into tid from topicos where disciplina_id=did and nome='Demonstrações contábeis aplicadas ao setor público';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'O Balanço Orçamentário, uma das demonstrações contábeis aplicadas ao setor público, tem por finalidade evidenciar, principalmente:', 'O Balanço Orçamentário confronta as receitas e despesas orçamentárias previstas (orçadas) com as efetivamente realizadas no exercício.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A situação patrimonial da entidade ao final do exercício', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'As receitas e despesas orçamentárias previstas em confronto com as realizadas', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'O fluxo de caixa financeiro apenas', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'O resultado consolidado das empresas estatais', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Exclusivamente os investimentos em ativos permanentes', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='administracao_publica';
  select id into tid from topicos where disciplina_id=did and nome='Modelos de administração (patrimonial, burocrática, gerencial)';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'O modelo de administração pública caracterizado pela ênfase em hierarquia rígida, formalismo excessivo e controle de procedimentos é denominado:', 'A administração burocrática busca superar o patrimonialismo por meio de hierarquia, impessoalidade, formalismo e controle rígido de procedimentos.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Administração patrimonialista', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Administração burocrática', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Administração gerencial', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Administração empreendedora', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Administração participativa', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='administracao_publica';
  select id into tid from topicos where disciplina_id=did and nome='Modelos de administração (patrimonial, burocrática, gerencial)';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'A administração pública gerencial, em contraposição à burocrática, tem como uma de suas características centrais:', 'O modelo gerencial enfatiza resultados, eficiência, flexibilidade e a orientação para o cidadão-usuário, em contraste com o formalismo da burocracia clássica.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A confusão entre o patrimônio público e o privado', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A ênfase em resultados, eficiência e no atendimento ao cidadão como cliente/usuário do serviço público', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A ausência total de controle sobre os gestores', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'O foco exclusivo em processos e formalidades, sem avaliação de resultados', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'A eliminação de qualquer forma de planejamento', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='administracao_publica';
  select id into tid from topicos where disciplina_id=did and nome='Princípios constitucionais da Administração';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'O princípio constitucional que exige a divulgação dos atos administrativos como condição de eficácia e instrumento de controle social é o da:', 'A publicidade assegura transparência aos atos administrativos, permitindo seu conhecimento e controle pela sociedade.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Eficiência', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Publicidade', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Legalidade', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Impessoalidade', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Moralidade', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='administracao_geral';
  select id into tid from topicos where disciplina_id=did and nome='Funções da administração (PODC)';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'As funções administrativas clássicas, segundo a Teoria Clássica da Administração, compreendem:', 'As funções administrativas clássicas (PODC) são: planejar, organizar, dirigir (comandar/liderar) e controlar.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Planejar, organizar, dirigir e controlar', true, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Vender, produzir, financiar e contratar', false, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Recrutar, selecionar, treinar e avaliar', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Diagnosticar, planejar, executar e arquivar', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Prever, comandar apenas', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='administracao_geral';
  select id into tid from topicos where disciplina_id=did and nome='Funções da administração (PODC)';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'A função administrativa que consiste em definir objetivos e os meios para alcançá-los, antecipando cenários futuros, é a função de:', 'Planejar consiste em definir objetivos, estratégias e planos de ação, antecipando cenários futuros para orientar a atuação organizacional.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Organizar', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Planejar', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Dirigir', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Controlar', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Coordenar apenas', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='administracao_geral';
  select id into tid from topicos where disciplina_id=did and nome='Estruturas organizacionais';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'A estrutura organizacional em que cada subordinado se reporta a um único superior hierárquico, caracterizando unidade de comando, é denominada:', 'A estrutura linear caracteriza-se pela unidade de comando, em que cada subordinado responde a um único superior.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Estrutura matricial', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Estrutura linear', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Estrutura em rede', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Estrutura funcional pura', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Estrutura divisional apenas', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='administracao_estrategica';
  select id into tid from topicos where disciplina_id=did and nome='Planejamento estratégico';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'O planejamento estratégico, em relação ao tático e ao operacional, caracteriza-se por:', 'O planejamento estratégico é de responsabilidade da alta administração, tem horizonte de longo prazo e considera a organização como um todo em relação ao ambiente externo.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Ter foco em curtíssimo prazo e detalhamento operacional', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Envolver a alta administração, ter horizonte de longo prazo e abranger a organização como um todo', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Ser de responsabilidade exclusiva de níveis operacionais', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Não considerar o ambiente externo da organização', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Ser revisado apenas uma vez na história da organização', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='administracao_estrategica';
  select id into tid from topicos where disciplina_id=did and nome='Ferramentas de análise (SWOT, BSC)';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Na análise SWOT, os itens "forças" e "fraquezas" referem-se ao ambiente:', 'Forças e fraquezas são fatores internos à organização, enquanto oportunidades e ameaças referem-se ao ambiente externo.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Externo à organização', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Interno à organização', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Exclusivamente político', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Apenas econômico', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Somente tecnológico', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='administracao_estrategica';
  select id into tid from topicos where disciplina_id=did and nome='Ferramentas de análise (SWOT, BSC)';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'O Balanced Scorecard (BSC) propõe a avaliação do desempenho organizacional sob múltiplas perspectivas, incluindo tipicamente:', 'O BSC avalia o desempenho sob quatro perspectivas: financeira, do cliente, dos processos internos e de aprendizado e crescimento.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Apenas a perspectiva financeira', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Financeira, do cliente, dos processos internos e de aprendizado e crescimento', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Somente processos internos e fornecedores', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Exclusivamente aspectos jurídicos e regulatórios', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Apenas a perspectiva de mercado de ações', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='comportamento_organizacional';
  select id into tid from topicos where disciplina_id=did and nome='Motivação e liderança';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Segundo a Teoria da Hierarquia das Necessidades de Maslow, as necessidades fisiológicas e de segurança situam-se, respectivamente, em que posição da pirâmide?', 'Na pirâmide de Maslow, as necessidades fisiológicas ocupam a base, seguidas pelas de segurança, sendo as primeiras a demandar satisfação.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'No topo da pirâmide, sendo as últimas a serem satisfeitas', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Na base da pirâmide, sendo as primeiras a demandar satisfação', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Apenas as necessidades sociais estão na base', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Não fazem parte da teoria de Maslow', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Ficam no mesmo nível das necessidades de autorrealização', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='comportamento_organizacional';
  select id into tid from topicos where disciplina_id=did and nome='Motivação e liderança';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'O estilo de liderança caracterizado pela centralização das decisões no líder, com pouca participação dos subordinados, é denominado liderança:', 'A liderança autocrática centraliza as decisões no líder, com pouca ou nenhuma participação dos subordinados no processo decisório.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Democrática', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Autocrática', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Liberal (laissez-faire)', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Situacional apenas', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Transformacional, exclusivamente', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='comportamento_organizacional';
  select id into tid from topicos where disciplina_id=did and nome='Cultura e clima organizacional';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'A cultura organizacional pode ser definida como:', 'A cultura organizacional é o conjunto de valores, crenças, normas e pressupostos compartilhados que orientam o comportamento dos membros de uma organização.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'O layout físico exclusivo dos escritórios da empresa', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'O conjunto de valores, crenças, normas e pressupostos compartilhados que orientam o comportamento dos membros da organização', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Apenas o organograma formal da instituição', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'O salário médio pago aos empregados', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Exclusivamente as normas jurídicas externas aplicáveis à organização', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='gestao_pessoas';
  select id into tid from topicos where disciplina_id=did and nome='Recrutamento e seleção';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'O recrutamento interno, em comparação ao recrutamento externo, apresenta como vantagem típica:', 'O recrutamento interno tende a ser mais rápido e econômico, além de motivar os funcionários ao oferecer oportunidades de crescimento na própria organização.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Trazer sempre novas ideias e perspectivas externas', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Ser geralmente mais rápido, econômico e motivador para os empregados já pertencentes à organização', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Ampliar imediatamente a diversidade de perfis na organização', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Eliminar totalmente a necessidade de treinamento', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Ser obrigatório em qualquer processo seletivo público', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='gestao_pessoas';
  select id into tid from topicos where disciplina_id=did and nome='Recrutamento e seleção';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'Entre as técnicas de seleção de pessoal, a que se baseia na simulação de situações reais de trabalho para observar o comportamento do candidato é:', 'Técnicas de simulação, como dinâmicas de grupo, reproduzem situações de trabalho para observar comportamentos e competências dos candidatos na prática.', 'intermediario', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Entrevista estruturada apenas', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Prova de conhecimentos gerais', false, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Dinâmica de grupo ou técnica de simulação', true, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Análise curricular exclusivamente', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Teste psicométrico de personalidade, apenas', false, 5);
end $$;
do $$
declare qid uuid; did uuid; tid uuid;
begin
  select id into did from disciplinas where slug='gestao_pessoas';
  select id into tid from topicos where disciplina_id=did and nome='Avaliação de desempenho';
  insert into questions(disciplina_id, topico_id, enunciado, explicacao, nivel, origem_tipo)
  values (did, tid, 'A avaliação de desempenho denominada "avaliação 360 graus" caracteriza-se por:', 'A avaliação 360 graus coleta feedback de múltiplas fontes — superiores, pares, subordinados e, em alguns modelos, clientes — para uma visão mais completa do desempenho.', 'basico', 'inedita')
  returning id into qid;
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Ser realizada exclusivamente pelo superior imediato', false, 1);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Coletar percepções de múltiplas fontes: superiores, pares, subordinados e, por vezes, clientes', true, 2);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Utilizar apenas autoavaliação do próprio empregado', false, 3);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Ser aplicada uma única vez na carreira do servidor', false, 4);
  insert into question_options(question_id, texto, correta, ordem) values (qid, 'Desconsiderar completamente a opinião dos pares', false, 5);
end $$;