# Deploy com Ansible + Docker — Multi-projetos (Traefik opcional)

Este repositório entrega um **pipeline de deploy automatizado com Ansible** para aplicações containerizadas, com **suporte a 1..N projetos** definidos por variáveis de ambiente.  
A automação segue **boas práticas** (roles, idempotência, coleções oficiais, YAML seguro) e cobre:

- **Prompts interativos (S/N)** no início da execução;
- **Instalação opcional** de Docker/Compose;
- **Proxy TLS opcional** com **Traefik + Let’s Encrypt** (cria a rede externa `proxy`);
- **Clonar/atualizar N repositórios**, **gerar/atualizar `.env` por projeto** a partir de arquivos `*.envs` no nó de controle;
- **Patch condicional** do `docker-compose.yml` para **usar a rede externa `proxy`** (apenas se a rede existir no host);
- **Build e Up via Docker Compose v2** e **checagem de saúde** pós-deploy.

---

## ✅ Antes de começar (instalação do Ansible)

Instale o **Ansible** e as **dependências do Galaxy** **antes** de rodar o script `.sh` ou o playbook.

Debian/Ubuntu:
```bash
sudo apt-get update -y
sudo apt-get install -y ansible
```
RHEL/CentOS/Alma/Rocky:
```bash
sudo dnf install -y ansible || sudo yum install -y ansible
```
Arch:
```bash
sudo pacman -S --noconfirm ansible
```

Dependências do Galaxy (obrigatório):
```bash
ansible-galaxy collection install -r requirements.yml
# se houver roles:
ansible-galaxy role install -r requirements.yml
```

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
│  ├─ hosts.ini                 # inventário (localhost ou remotos)
│  └─ group_vars/
│     └─ all.yml                # APENAS variáveis globais       
├─ requirements.yml             # coleções/roles Galaxy
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
- Python 3 no nó de controle.
- Internet para instalar pacotes e clonar repositórios.
- **Docker Compose v2** no host alvo (o módulo usa `docker compose` v2).

---

## 🚀 Bootstrap (opcional, recomendado)

Use o script **`bootstrap-ansible.sh`** para **carregar variáveis** de **todos os arquivos `.env`** no diretório do projeto, **exceto** os que terminem com `.env.example`/`*.env.example`.  
> **Atenção:** este script **não instala** Ansible nem dependências.

- Ordem de carga **lexicográfica** (o último pode sobrescrever chaves anteriores).
- Opção disponível:
  - `ENV_DIR=/caminho` para indicar onde estão os `.env` (default: diretório do script).

**Exemplo:**
```bash
chmod +x bootstrap-ansible.sh
# Carrega .env, *.env, .env.*, *.envs (exceto *.env.example)
./bootstrap-ansible.sh

# Ou indicando explicitamente o diretório de .envs
ENV_DIR=$PWD ./bootstrap-ansible.sh
```

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
PROJECTS="django,api,projeto3,projeto4" # ele executa entre 1..N projetos dependendo de como definido no env

<DJANGO__REPO_URL>           # obrigatório
<DJANGO__AUTH>               # ssh (padrão) | https
<DJANGO__REPO_SSH_PRIVATE_KEY> | <DJANGO__REPO_SSH_KEY_PATH>  # dependendo se você vai passar a chave ssh em texto ou apontar o arquivo
<DJANGO__REPO_USERNAME>      # se https (prefira token na URL)
<DJANGO__REPO_PASSWORD>      # se https (prefira token na URL)
<DJANGO__PROJECT_NAME>       # nome do projeto se preferir
<DJANGO__PROJECT_DIR>        # default: /opt/<project>
<DJANGO__COMPOSE_PATH>       # default: docker-compose.yml
<DJANGO__ENV_SRC>            # arquivo de envs no nó de controle; default: ./django.env
```

### Exemplo prático
```bash
export PROJECTS="django, flutter"

# projeto 1
export DJANGO__REPO_URL=git@github.com:org/connecta.git
export DJANGO__AUTH=ssh
export DJANGO__REPO_SSH_KEY_PATH=~/.ssh/id_rsa
export DJANGO__PROJECT_NAME=connecta
export DJANGO__COMPOSE_PATH=docker-compose.yml
export DJANGO__ENV_SRC=./connecta.envs

# projeto 2
export FLUTTER__REPO_URL=https://git.example.com/org/django-app.git
export FLUTTER__AUTH=https
export FLUTTER__PROJECT_DIR=/opt/django-app
export FLUTTER__COMPOSE_PATH=docker/compose/prod.yml
export FLUTTER__ENV_SRC=./django.envs
```

> **Dica:** consolide esses `export` em um `deploy.env` e rode o `bootstrap-ansible.sh` para carregá-los.

---

## 🔐 Sobre os arquivos `*.env` (control node) → `.env` do projeto
Para cada `<ID>`, crie um arquivo `./<id>.env` (ou aponte outro caminho via `<ID>__ENV_SRC`).  
Após o clone, a role `project_deploy` **gera/atualiza** o **`.env` na raiz do projeto** com merge **não destrutivo**:
- **Preserva** chaves já existentes no `.env` do repositório;
- **Adiciona** chaves ausentes a partir do `<id>.env`.

**Exemplo de `django.env`:**
```
APP_IMAGE=org/connecta:latest
APP_SECRET=supersegredo
DATABASE_URL=postgres://user:pass@db:5432/app
VIRTUAL_HOST=app.seu-dominio.gov.br
```

> Esses `*.env` vivem no **nó de controle** (não no host alvo).

---

## 📒 Inventário
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
1) Garanta as ENVs carregadas (ex.: `source deploy.env` **ou** use o `bootstrap-ansible.sh`).  
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
- **Falha no clone** → confira método `ssh|https` e credenciais (prefira **token na URL**).
- **`.env` incompleto** → revise o arquivo `<ID>__ENV_SRC` (ex.: `./connecta.envs`).
- **Rede `proxy` ausente** → instale a role `traefik` (responda **S**) ou crie manualmente:
  ```bash
  docker network create proxy
  ```
- **Certificados LE** → `LE_EMAIL` definido e portas 80/443 expostas; DNS correto.