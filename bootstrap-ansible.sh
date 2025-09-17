#!/usr/bin/env bash
# bootstrap-ansible-lite.sh (safe to source)
# Carrega variáveis de ambiente a partir de arquivos *.env no diretório do projeto,
# ignorando '.env.example' e '*.env.example'.
# IMPORTANTE: Este script pode ser "sourced" (recomendado) sem quebrar seu shell.

# -------------------- detecção de modo --------------------
__BOOTSTRAP_SOURCED=0
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  __BOOTSTRAP_SOURCED=1
fi

# Requer bash ao ser sourced
if (( __BOOTSTRAP_SOURCED )) && [[ -z "${BASH_VERSION:-}" ]]; then
  echo "[ERROR] Use 'bash' para dar source neste script (ex.: 'source ./bootstrap-ansible-lite.sh')."
  return 1 2>/dev/null || exit 1
fi

# Salva opções/traps para restaurar ao final quando sourced
if (( __BOOTSTRAP_SOURCED )); then
  __OLD_SET_OPTS="$(set +o)"
  __OLD_TRAP_ERR="$(trap -p ERR || true)"
else
  # Execução direta: pode usar flags rígidas sem afetar o shell do usuário
  set -Eeuo pipefail
  trap 'echo "[ERROR] Falha na linha $LINENO. Abortando." >&2; exit 1' ERR
fi

log()   { printf "[INFO ] %s\n" "$*"; }
warn()  { printf "[WARN ] %s\n" "$*" >&2; }
err()   { printf "[ERROR] %s\n" "$*" >&2; }
die()   {
  err "$*"
  if (( __BOOTSTRAP_SOURCED )); then
    return 1
  else
    exit 1
  fi
}

# -------------------- parâmetros --------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ENV_DIR="${ENV_DIR:-$SCRIPT_DIR}"

# -------------------- carga de .env --------------------
load_envs() {
  local files=()
  local f

  # coleta arquivos .env válidos (não recursivo)
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find "$ENV_DIR" -maxdepth 1 -type f \( \
              -name ".env" -o -name "*.env" -o -name ".env.*" -o -name "*.envs" \
            \) ! -name ".env.example" ! -name "*.env.example" -print0 | sort -z)

  if ((${#files[@]} == 0)); then
    warn "Nenhum arquivo .env encontrado em $ENV_DIR (ou apenas arquivos de exemplo)."
    return 0
  fi

  log "Carregando ${#files[@]} arquivo(s) .env do diretório: $ENV_DIR"
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
    set -a  # auto-export
    # shellcheck disable=SC1090,SC1091
    source <(sed -e 's/\r$//' "$f")
    set +a
    log "   · Variáveis carregadas de $(basename "$f"): ${count} (valores ocultos)"
  done
}

main() {
  log "Diretório do script : $SCRIPT_DIR"
  log "Diretório de .envs  : $ENV_DIR"
  load_envs || return $?

  log "Ambiente carregado. Agora rode: ansible-playbook playbooks/deploy.yml -K"
}

main_ret=0
main || main_ret=$?

# -------------------- restauração quando sourced --------------------
if (( __BOOTSTRAP_SOURCED )); then
  # restaura opções e trap do shell chamador
  eval "$__OLD_SET_OPTS"
  if [[ -n "${__OLD_TRAP_ERR:-}" ]]; then
    eval "$__OLD_TRAP_ERR"
  else
    trap - ERR
  fi
  # limpa variáveis/funções internas
  unset -f log warn err die load_envs main
  unset __BOOTSTRAP_SOURCED __OLD_SET_OPTS __OLD_TRAP_ERR SCRIPT_DIR ENV_DIR main_ret
else
  exit "$main_ret"
fi
