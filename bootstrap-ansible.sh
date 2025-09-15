#!/usr/bin/env bash
# bootstrap-ansible-lite.sh
# Objetivo: Carregar variáveis de ambiente a partir de arquivos *.env na raiz do projeto,
#           ignorando templates de exemplo ('.env.example' e '*.env.example').
#
# O script NÃO instala Ansible ou dependências. Antes de usá-lo, instale:
#   - Ansible
#   - Coleções/roles do requirements.yml
#
# Opções:
#   - ENV_DIR: diretório a procurar por arquivos .env (default: diretório deste script)
#
# Comportamento:
#   - Carrega, em ordem lexicográfica, arquivos que combinem:
#       .env, *.env, .env.*, *.envs
#     exceto: .env.example e *.env.example
#   - O último arquivo pode sobrescrever valores definidos nos anteriores.
#   - Não exibe valores no log (apenas contagem de chaves).

set -Eeuo pipefail

log()   { printf "[INFO ] %s\n" "$*"; }
warn()  { printf "[WARN ] %s\n" "$*" >&2; }
err()   { printf "[ERROR] %s\n" "$*" >&2; }
trap 'err "Falha na linha $LINENO. Abortando."' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ENV_DIR="${ENV_DIR:-$SCRIPT_DIR}"

load_envs() {
  local files=()
  local f
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find "$ENV_DIR" -maxdepth 1 -type f \( \
              -name ".env" -o -name "*.env" -o -name ".env.*" -o -name "*.envs" \
            \) ! -name ".env.example" ! -name "*.example.env" -print0 | sort -z)

  if ((${#files[@]} == 0)); then
    warn "Nenhum arquivo .env encontrado em $ENV_DIR (ou apenas arquivos de exemplo)."
    return 0
  fi

  log "Carregando ${#files[@]} arquivo(s) .env do diretório: $ENV_DIR"
  for f in "${files[@]}"; do
    log " - $(basename "$f")"
  done

  local count
  for f in "${files[@]}"; do
    if [[ ! -r "$f" ]]; then
      warn "Sem permissão de leitura: $f (ignorando)"; continue
    fi
    count="$(grep -E '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=' "$f" | grep -vc '^[[:space:]]*#' || true)"
    set -a
    # shellcheck disable=SC1090
    source <(sed -e 's/\r$//' "$f")
    set +a
    log "   · Variáveis carregadas de $(basename "$f"): ${count} (valores ocultos)"
  done
}

main() {
  log "Diretório do script : $SCRIPT_DIR"
  log "Diretório de .envs  : $ENV_DIR"
  load_envs
  log "Ambiente carregado. Agora você pode executar o playbook do Ansible."
}

main "$@"