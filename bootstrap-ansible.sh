#!/usr/bin/env sh
# bootstrap-ansible.sh
# Carrega variáveis de todos os arquivos .env do diretório do projeto,
# ignorando *.env.example. Use via:   . ./bootstrap-ansible.sh   (ou: source ...)
# Diretório a varrer (default: diretório atual); pode sobrescrever: ENV_DIR=/caminho
ENV_DIR="${ENV_DIR:-$PWD}"

echo "[INFO ] Carregando .env a partir de: $ENV_DIR"

# Monta a lista (ordem lexicográfica natural das globs)
set --  # zera parâmetros posicionais
for pat in ".env" "*.env" ".env.*" "*.envs"; do
  for f in "$ENV_DIR"/$pat; do
    [ -f "$f" ] || continue
    case "$f" in
      *.env.example|*.envs.example|*/.env.example) continue ;;
    esac
    set -- "$@" "$f"
  done
done

if [ $# -eq 0 ]; then
  echo "[WARN ] Nenhum arquivo .env encontrado (ou só *.env.example)."
  return 0 2>/dev/null || exit 0
fi

# Carrega cada arquivo, filtrando apenas linhas válidas KEY=VALUE (aceita 'export KEY=VALUE')
i=0
for f in "$@"; do
  i=$((i+1))
  echo "[INFO ] -> $(basename "$f")"
  # arquivo temporário sanitizado (só KEY=VALUE; remove CRLF; aceita 'export ')
  tmp="${TMPDIR:-/tmp}/envload.$$.$i"
  # Filtra:
  #  - remove CR (\r)
  #  - aceita linhas 'export KEY=VALUE' e 'KEY=VALUE'
  #  - ignora comentários e vazias
  #  - NOTE: valores com espaços precisam estar devidamente entre aspas no arquivo .env
  sed 's/\r$//' "$f" \
    | grep -E '^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=' \
    | sed -E 's/^[[:space:]]*export[[:space:]]+//' > "$tmp"

  # Exporta no shell chamador (precisa ser "sourced")
  set -a
  # shellcheck disable=SC1090
  . "$tmp"
  set +a
  rm -f "$tmp"
done

echo "[INFO ] Variáveis carregadas para o ambiente atual."
echo "[INFO ] Agora rode: ansible-playbook playbooks/deploy.yml"
