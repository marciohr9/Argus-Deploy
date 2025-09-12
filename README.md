# Deploy com Ansible + Docker — Multi-projetos - (Traefik opcional)

Este repositório entrega um **pipeline de deploy automatizado com Ansible** para aplicações containerizadas, com **suporte a 1..N projetos** definidos por variáveis de ambiente.  
A automação segue **boas práticas** (roles, idempotência, coleções oficiais, YAML seguro) e cobre:

- **Prompts interativos (S/N)** no início da execução;
- **Instalação opcional** de Docker/Compose;
- **Proxy TLS opcional** com **Traefik + Let’s Encrypt** (cria a rede externa `proxy`);
- **Clonar/atualizar N repositórios**, **gerar/atualizar `.env` por projeto** a partir de arquivos `*.envs` no nó de controle;
- **Patch condicional** do `docker-compose.yml` para **usar a rede externa `proxy`** (apenas se a rede existir no host);
- **Build e Up via Docker Compose v2** e **checagem de saúde** pós-deploy.

---

## 🧭 Padrões e boas práticas adotados
- **Organização por roles**: `setup_docker`, `traefik`, `project_deploy`.
- **Idempotência**: nada é recriado sem necessidade; permissões e arquivos sensíveis preservados.
- **Segurança**: etapas com segredos usam `no_log`; `.env` criado com `0640`.
- **Coleções oficiais**: `community.docker`, `community.general`, `ansible.utils`.
- **Patch YAML estrutural** do Compose (sem regex).
- **Compatível com linters**: construção de objetos em YAML, sem dicionários Jinja inline complexos.

---

## 📁 Estrutura do repositório
```
ansible-deploy/
├─ ansible.cfg
├─ inventory/
│  └─ hosts.ini                 # inventário (localhost ou remotos)
├─ requirements.yml             # coleções/roles Galaxy
├─ group_vars/
│  └─ all.yml                   # APENAS variáveis globais
├─ playbooks/
│  └─ deploy.yml                # play principal (com prompts S/N)
└─ roles/
   ├─ setup_docker/
   │  └─ tasks/main.yml
   ├─ traefik/
   │  ├─ tasks/main.yml
   │  └─ templates/traefik.compose.yml.j2
   └─ project_deploy/
      ├─ tasks/main.yml         # orquestra multi-projetos
      ├─ tasks/_per_project.yml # pipeline por projeto
      ├─ tasks/patch_compose.yml
      └─ templates/.git-ssh-key.j2 (opcional)
```

---

## ✅ Pré-requisitos
- Host(es) alvo(s) com Linux e **sudo** (ou root).
- Python 3 no nó de controle (de onde você executa o Ansible).
- Internet para instalar pacotes e clonar repositórios.
- **Docker Compose v2** (o módulo usa `docker compose`).

---

## 🚀 Bootstrap (opcional, recomendado)
Use o script utilitário **`bootstrap-ansible.sh`** para:
1) **Carregar** variáveis de **todos os arquivos `.env`** no diretório do projeto **(exceto os que terminam com `.example`)**;  
   - Ordem de carga **lexicográfica**; o último arquivo pode sobrescrever chaves anteriores.  
   - Opções:
     - `ENV_DIR=/caminho` para indicar onde estão os `.env` (default: diretório do script).
     - `ENV_FILE=/caminho/deploy.env` (opcional) carregado **antes** dos demais.
     - `RYML=/caminho/requirements.yml` para apontar o `requirements.yml`.
2) **Instalar** Ansible caso ausente;  
3) **Instalar** as dependências do **`requirements.yml`** (collections/roles Galaxy).

**Exemplo:**
```bash
chmod +x bootstrap-ansible.sh
# Carrega .envs do diretório do script + instala Ansible + requirements
./bootstrap-ansible.sh

# Ou indicando caminhos explicitamente
ENV_DIR=$PWD RYML=$PWD/requirements.yml ./bootstrap-ansible.sh
```

> O `deploy.env` (se usado via `ENV_FILE`) é um arquivo de **variáveis de ambiente do shell** (não o `.env` do projeto).

---

## 🔧 Variáveis globais (em `group_vars/all.yml`)
```yaml
base_opt_dir: /opt
traefik_dir: "{{ base_opt_dir }}/traefik"
proxy_network_name: proxy
le_email: "{{ lookup('env', 'LE_EMAIL') | default('', true) }}"  # usado só se Traefik = S
health_timeout_seconds: 300
```
> **Importante:** **não** coloque variáveis específicas de projetos aqui.

---

## 📦 Definição dos projetos por ENV (1..N)
Defina a lista de projetos por `PROJECTS` e, para cada `<ID>`, configure ENVs com o **prefixo em maiúsculas e `__`**:

```
PROJECTS="connecta,sei,novosga"

<CONNECTA__REPO_URL>           # obrigatório
<CONNECTA__AUTH>               # ssh (padrão) | https
<CONNECTA__REPO_SSH_PRIVATE_KEY> | <CONNECTA__REPO_SSH_KEY_PATH>  # se ssh
<CONNECTA__REPO_USERNAME>      # se https (prefira token na URL)
<CONNECTA__REPO_PASSWORD>      # se https (prefira token na URL)
<CONNECTA__PROJECT_NAME>       # default: connecta
<CONNECTA__PROJECT_DIR>        # default: /opt/connecta
<CONNECTA__COMPOSE_PATH>       # default: docker-compose.yml
<CONNECTA__ENV_SRC>            # arquivo de envs no nó de controle; default: ./connecta.envs
```

### Exemplo prático
```bash
export PROJECTS="connecta,sei"

# projeto 1
export CONNECTA__REPO_URL=git@github.com:org/connecta.git
export CONNECTA__AUTH=ssh
export CONNECTA__REPO_SSH_KEY_PATH=~/.ssh/id_rsa
export CONNECTA__PROJECT_NAME=connecta
export CONNECTA__COMPOSE_PATH=docker-compose.yml
export CONNECTA__ENV_SRC=./connecta.envs

# projeto 2
export SEI__REPO_URL=https://git.example.com/gov/sei.git
export SEI__AUTH=https
export SEI__PROJECT_DIR=/opt/sei502
export SEI__COMPOSE_PATH=docker/compose/prod.yml
export SEI__ENV_SRC=./sei.envs
```

> **Dica:** consolide esses `export` em um `deploy.env` e use o `bootstrap-ansible.sh` para carregá-los.

---

## 🔐 Sobre os arquivos `*.envs` (control node) → `.env` do projeto
Para cada `<ID>`, crie um arquivo `./<id>.envs` (ou aponte outro caminho via `<ID>__ENV_SRC`).  
Após o clone, a role `project_deploy` **gera/atualiza** o **`.env` na raiz do projeto** com merge **não destrutivo**:
- **Preserva** chaves já existentes no `.env` do repositório;
- **Adiciona** chaves ausentes a partir do `<id>.envs`.

**Exemplo de `connecta.envs`:**
```
APP_IMAGE=org/connecta:latest
APP_SECRET=supersegredo
DATABASE_URL=postgres://user:pass@db:5432/app
VIRTUAL_HOST=app.seu-dominio.gov.br
```

> Esses `*.envs` vivem no **nó de controle** (não no host alvo).

---

## 📦 Instalar dependências Galaxy
```bash
ansible-galaxy collection install -r requirements.yml
# se houver roles:
ansible-galaxy role install -r requirements.yml
```

`requirements.yml` típico:
```yaml
collections:
  - name: community.docker
  - name: community.general
  - name: ansible.utils
```

---

## 📒 Inventário
`inventory/hosts.ini` de exemplo:

**Localhost**
```ini
[targets]
localhost ansible_connection=local
```

**Hosts remotos**
```ini
[targets]
app01 ansible_host=10.0.0.11 ansible_user=ubuntu
app02 ansible_host=10.0.0.12 ansible_user=ubuntu
```

---

## ▶️ Execução
1) Garanta as ENVs carregadas (ex.: `source deploy.env` ou use o `bootstrap-ansible.sh`).  
2) Rode o play:
```bash
ansible-playbook playbooks/deploy.yml -K
```

Durante a execução você verá **prompts S/N**:
1. Checar/instalar **Docker/Compose**? (default **S**)  
2. Instalar **Traefik + Let’s Encrypt**? (S/N)

---

## 🔄 O que a automação faz (por projeto)
1. **Clona/atualiza** o repositório em `/opt/<id>` (ou `<ID>__PROJECT_DIR`).
2. **Gera/atualiza `.env`** a partir de `<ID>__ENV_SRC` (ex.: `./connecta.envs`).
3. **(Se a rede `proxy` existir)** injeta a network externa `proxy` no `docker-compose.yml` e vincula todos os serviços.
4. Executa **build** e **up -d** com Compose v2 (respeitando `COMPOSE_PATH`).
5. Faz **health-check**: containers com `HEALTHCHECK` devem ficar `healthy`; os demais ao menos `running`.

> A rede `proxy` é criada pela role **traefik**. Se você não instalar o Traefik, nenhum patch de rede é aplicado.

---

## 🔐 Traefik & roteamento HTTPS
A role `traefik` cria a rede externa `proxy` e publica 80/443 com Let’s Encrypt (e-mail em `LE_EMAIL`).  
Para rotear uma aplicação via HTTPS automático, adicione **labels** ao serviço `web` no Compose do **seu projeto**:

```yaml
services:
  web:
    # ...
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.web.rule=Host(`app.seu-dominio.gov.br`)"
      - "traefik.http.routers.web.entrypoints=websecure"
      - "traefik.http.routers.web.tls.certresolver=le"
    networks:
      - proxy
```

> Configure o **DNS** do domínio apontando para o host onde o Traefik está rodando.

---

## 🧪 Troubleshooting
- **Nenhum projeto encontrado** → verifique `PROJECTS="id1,id2"` e `<ID>__REPO_URL`.
- **Falha no clone** → confira método `ssh|https` e credenciais (preferível usar **token na URL**).
- **`.env` incompleto** → revise o arquivo `<ID>__ENV_SRC` (ex.: `./connecta.envs`).
- **Rede `proxy` ausente** → instale a role `traefik` (responda **S**) ou crie manualmente:
  ```bash
  docker network create proxy
  ```
- **Certificados LE** → `LE_EMAIL` definido e portas 80/443 expostas; DNS correto.

---

## 🔒 Segurança
- Use **Ansible Vault** para segredos em YAML quando necessário.
- Não versione chaves privadas ou senhas.
- `.env` dos projetos é criado com permissão `0640`.

---

## 🔧 Customizações & extensões
- **Múltiplos Compose por projeto**: adapte `files: [...]` no módulo `docker_compose_v2`.
- **Paralelismo**: para muitos projetos/hosts, considere `serial`, estratégias e/ou particionar lotes.
- **Health-check específico**: personalize o critério para serviços críticos.

---

**Pronto!** Você tem um fluxo padronizado para **deploy multi-projetos** com Ansible + Docker, com proxy TLS opcional via Traefik e geração automática de `.env` por projeto.