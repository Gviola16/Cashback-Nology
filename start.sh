#!/usr/bin/env bash
set -euo pipefail

# ─── cores ────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${CYAN}[cashvault]${RESET} $*"; }
ok()   { echo -e "${GREEN}[✓]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
die()  { echo -e "${RED}[✗]${RESET} $*" >&2; exit 1; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
FRONTEND_DIR="$ROOT_DIR/frontend"
ENV_FILE="$BACKEND_DIR/.env"

BACKEND_PORT=8000
FRONTEND_PORT=3000

# PIDs dos processos filhos
BACKEND_PID=""
FRONTEND_PID=""

# ─── cleanup ao sair (Ctrl+C ou erro) ─────────────────────────
cleanup() {
  echo ""
  log "Encerrando serviços..."

  [[ -n "$BACKEND_PID" ]]  && kill "$BACKEND_PID"  2>/dev/null && ok "Backend encerrado"
  [[ -n "$FRONTEND_PID" ]] && kill "$FRONTEND_PID" 2>/dev/null && ok "Frontend encerrado"

  log "Docker mantido rodando. Para parar: ${BOLD}docker compose down${RESET}"
  exit 0
}
trap cleanup INT TERM

# ─── 1. verificar dependências ─────────────────────────────────
log "Verificando dependências..."

command -v docker   >/dev/null 2>&1 || die "Docker não encontrado. Instale em https://docs.docker.com/get-docker/"
command -v python3  >/dev/null 2>&1 || die "Python 3 não encontrado."

ok "Dependências OK"

# ─── 2. criar .env se não existir ─────────────────────────────
if [[ ! -f "$ENV_FILE" ]]; then
  warn ".env não encontrado — criando a partir do .env.example"
  cp "$BACKEND_DIR/.env.example" "$ENV_FILE"
  ok ".env criado em $ENV_FILE"
fi

# ─── 3. docker compose ─────────────────────────────────────────
log "Iniciando PostgreSQL via Docker..."

cd "$ROOT_DIR"
docker compose up -d

log "Aguardando PostgreSQL ficar saudável..."
RETRIES=30
until docker compose exec -T postgres pg_isready -U cashback_user -d cashback_db -q 2>/dev/null; do
  RETRIES=$((RETRIES - 1))
  if [[ $RETRIES -le 0 ]]; then
    die "PostgreSQL não respondeu após 30 tentativas. Verifique: docker compose logs postgres"
  fi
  sleep 1
done
ok "PostgreSQL pronto"

# ─── 4. virtualenv + dependências Python ──────────────────────
VENV_DIR="$BACKEND_DIR/venv"

if [[ ! -d "$VENV_DIR" ]]; then
  log "Criando virtualenv..."
  python3 -m venv "$VENV_DIR"
  ok "Virtualenv criado"
fi

PYTHON="$VENV_DIR/bin/python"
PIP="$VENV_DIR/bin/pip"

log "Instalando dependências Python..."
"$PIP" install -q -r "$BACKEND_DIR/requirements.txt"
ok "Dependências instaladas"

# ─── 5. backend ───────────────────────────────────────────────
log "Iniciando backend na porta ${BACKEND_PORT}..."

cd "$BACKEND_DIR"
"$VENV_DIR/bin/uvicorn" main:app \
  --host 0.0.0.0 \
  --port "$BACKEND_PORT" \
  --reload \
  --log-level warning \
  > "$ROOT_DIR/backend.log" 2>&1 &
BACKEND_PID=$!

# aguarda o backend responder
RETRIES=20
until curl -sf "http://localhost:${BACKEND_PORT}/api/health" >/dev/null 2>&1; do
  RETRIES=$((RETRIES - 1))
  if [[ $RETRIES -le 0 ]]; then
    die "Backend não subiu. Verifique: tail -f $ROOT_DIR/backend.log"
  fi
  sleep 1
done
ok "Backend rodando → http://localhost:${BACKEND_PORT}"
ok "Swagger UI       → http://localhost:${BACKEND_PORT}/docs"

# ─── 6. frontend ──────────────────────────────────────────────
log "Iniciando frontend na porta ${FRONTEND_PORT}..."

cd "$FRONTEND_DIR"
python3 -m http.server "$FRONTEND_PORT" \
  > "$ROOT_DIR/frontend.log" 2>&1 &
FRONTEND_PID=$!

sleep 1
if ! kill -0 "$FRONTEND_PID" 2>/dev/null; then
  die "Frontend não subiu. Verifique: tail -f $ROOT_DIR/frontend.log"
fi
ok "Frontend rodando → http://localhost:${FRONTEND_PORT}"

# ─── resumo ───────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║         CashVault — rodando              ║${RESET}"
echo -e "${BOLD}╠══════════════════════════════════════════╣${RESET}"
echo -e "${BOLD}║${RESET}  Frontend  →  http://localhost:${FRONTEND_PORT}       ${BOLD}║${RESET}"
echo -e "${BOLD}║${RESET}  Backend   →  http://localhost:${BACKEND_PORT}       ${BOLD}║${RESET}"
echo -e "${BOLD}║${RESET}  Swagger   →  http://localhost:${BACKEND_PORT}/docs  ${BOLD}║${RESET}"
echo -e "${BOLD}║${RESET}  Banco     →  localhost:5432              ${BOLD}║${RESET}"
echo -e "${BOLD}╠══════════════════════════════════════════╣${RESET}"
echo -e "${BOLD}║${RESET}  Logs:  tail -f backend.log              ${BOLD}║${RESET}"
echo -e "${BOLD}║${RESET}         tail -f frontend.log             ${BOLD}║${RESET}"
echo -e "${BOLD}╠══════════════════════════════════════════╣${RESET}"
echo -e "${BOLD}║${RESET}  Ctrl+C para encerrar                    ${BOLD}║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${RESET}"
echo ""

# ─── aguarda processos filhos ─────────────────────────────────
wait "$BACKEND_PID" "$FRONTEND_PID"
