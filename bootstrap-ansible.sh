#!/usr/bin/env bash
# bootstrap-ansible.sh
# Objetivos:
#  1) Carregar variáveis de TODOS os arquivos .env na pasta do projeto Ansible,
#     exceto os que terminam com ".example" (ex.: .env.example, connecta.env.example).
#     (Mantém compatibilidade com ENV_FILE: se informado, carrega primeiro, se existir)
#  2) Verificar/instalar Ansible
#  3) Instalar dependências do Ansible (collections/roles) do requirements.yml
#
# Variáveis de ambiente opcionais:
#  - ENV_DIR : diretório a varrer por *.env (default: diretório deste script)
#  - ENV_FILE: caminho de um arquivo .env específico para carregar ANTES (opcional)
#  - RYML    : caminho do requirements.yml (default: <script_dir>/requirements.yml)
#
# Observações:
#  - A ordem de carregamento é determinística (ordenada lexicograficamente). O último arquivo
#    pode sobrescrever chaves definidas em anteriores.
#  - Valores NÃO são exibidos no log.
#  - Requer bash e utilitários básicos (find, grep, sed).

set -Eeuo pipefail

# ---------- Utilidades ----------
log()   { printf "[INFO ] %s\n" "$*"; }
warn()  { printf "[WARN ] %s\n" "$*" >&2; }
err()   { printf "[ERROR] %s\n" "$*" >&2; }
die()   { err "$*"; exit 1; }
trap 'err "Falha na linha $LINENO. Abortando."' ERR

is_root() { [[ "${EUID:-$(id -u)}" -eq 0 ]]; }
as_root() {
  if is_root; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    die "Permissões elevadas necessárias e 'sudo' não encontrado. Execute como root."
  fi
}

detect_pkg_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    PKG_MGR="apt"
    PM_UPDATE=(apt-get update -y)
    PM_INSTALL=(apt-get install -y)
  elif command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
    PM_UPDATE=(dnf -y makecache)
    PM_INSTALL=(dnf install -y)
  elif command -v yum >/dev/null 2>&1; then
    PKG_MGR="yum"
    PM_UPDATE=(yum makecache -y)
    PM_INSTALL=(yum install -y)
  elif command -v zypper >/dev/null 2>&1; then
    PKG_MGR="zypper"
    PM_UPDATE=(zypper refresh)
    PM_INSTALL=(zypper install -y)
  elif command -v pacman >/dev/null 2>&1; then
    PKG_MGR="pacman"
    PM_UPDATE=(pacman -Sy --noconfirm)
    PM_INSTALL=(pacman -S --noconfirm)
  else
    die "Gerenciador de pacotes não suportado. Instale o Ansible manualmente."
  fi
}

# ---------- Caminhos padrão ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ENV_DIR="${ENV_DIR:-$SCRIPT_DIR}"
RYML="${RYML:-$SCRIPT_DIR/requirements.yml}"
ENV_FILE="${ENV_FILE:-}"

# ---------- 1) Carregar arquivos .env ----------
load_dotenv_files() {
  local files=()
  local f

  # (Opcional) arquivo único legado
  if [[ -n "$ENV_FILE" ]]; then
    if [[ -f "$ENV_FILE" ]]; then
      if [[ "$ENV_FILE" == *.example ]]; then
        warn "ENV_FILE aponta para '* .example'; ignorando: $ENV_FILE"
      else
        files+=("$ENV_FILE")
      fi
    else
      warn "ENV_FILE informado mas não encontrado: $ENV_FILE"
    fi
  fi

  # Todos os .env no diretório, exceto os que terminam com .example
  # Inclui: .env, .env.local, .env.prod, qualquer arquivo *.env (ex.: connecta.env)
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find "$ENV_DIR" -maxdepth 1 -type f \( -name ".env" -o -name "*.env" -o -name ".env.*" \) ! -name "*.example" -print0 | sort -z)

  # Remover duplicatas preservando ordem
  if ((${#files[@]} == 0)); then
    warn "Nenhum arquivo .env encontrado em: $ENV_DIR (ou todos eram *.example)."
    return 0
  fi
  declare -A seen=()
  local unique=()
  for f in "${files[@]}"; do
    [[ -n "${seen[$f]:-}" ]] && continue
    seen["$f"]=1
    unique+=("$f")
  done
  files=("${unique[@]}")

  log "Carregando variáveis de ${#files[@]} arquivo(s) .env (ordem determinística):"
  for f in "${files[@]}"; do
    log " - $(basename "$f")"
  done

  # Exporta variáveis de cada arquivo (sem exibir valores)
  local count
  for f in "${files[@]}"; do
    if [[ ! -r "$f" ]]; then
      warn "Sem permissão de leitura: $f (ignorando)"
      continue
    fi
    count="$(grep -E '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=' "$f" | grep -vc '^[[:space:]]*#' || true)"
    set -a
    # shellcheck disable=SC1090
    source <(sed -e 's/\r$//' "$f")
    set +a
    log "   · Variáveis carregadas de $(basename "$f"): ${count} (valores ocultos)"
  done
}

# ---------- 2) Verificar/instalar Ansible ----------
install_ansible() {
  detect_pkg_manager
  log "Gerenciador detectado: $PKG_MGR"

  if command -v ansible >/dev/null 2>&1; then
    log "Ansible já instalado: $(ansible --version | head -n1)"
    return 0
  fi

  log "Instalando Ansible…"
  case "$PKG_MGR" in
    apt)
      as_root "${PM_UPDATE[@]}"
      as_root "${PM_INSTALL[@]}" software-properties-common python3 python3-pip
      as_root "${PM_INSTALL[@]}" ansible
      ;;
    dnf|yum)
      as_root "${PM_UPDATE[@]}"
      as_root "${PM_INSTALL[@]}" python3 python3-pip ansible
      ;;
    zypper)
      as_root "${PM_UPDATE[@]}"
      as_root "${PM_INSTALL[@]}" python3 python3-pip ansible
      ;;
    pacman)
      as_root "${PM_UPDATE[@]}"
      as_root "${PM_INSTALL[@]}" ansible python-pip
      ;;
    *)
      die "Fluxo de instalação não implementado para $PKG_MGR"
      ;;
  esac

  command -v ansible >/dev/null 2>&1 || die "Ansible não pôde ser instalado."
  log "Ansible instalado: $(ansible --version | head -n1)"
}

# ---------- 3) Instalar requirements Galaxy ----------
install_requirements() {
  if [[ ! -f "$RYML" ]]; then
    warn "Arquivo requirements.yml não encontrado em: $RYML (pulando dependências Galaxy)."
    return 0
  fi

  log "Verificando/instalando dependências do Galaxy a partir de: $RYML"

  if grep -qE '^[[:space:]]*collections:' "$RYML"; then
    log "Instalando collections…"
    ansible-galaxy collection install -r "$RYML" --force-with-deps
  else
    log "Nenhuma seção 'collections:' encontrada."
  fi

  if grep -qE '^[[:space:]]*roles:' "$RYML"; then
    log "Instalando roles…"
    ansible-galaxy role install -r "$RYML"
  else
    log "Nenhuma seção 'roles:' encontrada."
  fi

  log "Dependências Galaxy verificadas/instaladas."
}

# ---------- Execução ----------
main() {
  log "Diretório do script    : $SCRIPT_DIR"
  log "Diretório de .envs     : $ENV_DIR"
  log "Arquivo requirements   : $RYML"
  [[ -n "${ENV_FILE:-}" ]] && log "ENV_FILE (opcional)    : $ENV_FILE"

  load_dotenv_files
  install_ansible
  install_requirements

  log "Pronto! Ambiente do Ansible inicializado."
}

main "$@"