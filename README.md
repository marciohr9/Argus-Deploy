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
source ./bootstrap-ansible.sh

# Ou indicando explicitamente o diretório de .envs
ENV_DIR=$PWD source ./bootstrap-ansible.sh
```

---

## 🔧 Variáveis globais (em `inventory/group_vars/all.yml`)
```yaml
# Diretório base onde os projetos serão clonados/implantados
base_opt_dir: "{{ lookup('env', 'BASE_DIR') | default('/opt', true) }}"
# Traefik (role opcional)
traefik_dir: "{{ base_opt_dir }}/traefik"
# nome do projeto docker-compose do traefik (usado para reiniciar o container)
traefik_compose_project: traefik
# variavel para definir se reinicia o contaienr de proxy ao final da instalação
restart_traefik_after_deploy: true
# Nome da network Docker usada pelo Traefik (e compartilhada com os projetos)
proxy_network_name: "{{ lookup('env', 'PROXY_NETWORK_NAME') | default('proxy', true) }}"
# E-mail do Let's Encrypt (forneça via ENV: LE_EMAIL)
le_email: "{{ lookup('env', 'LE_EMAIL') | default('', true) }}"
# Tempo máximo para health-check (segundos)
health_timeout_seconds: 300
#github_token: "__TOKEN__GITHUT__" # caso não queira usar o token via ambiente descomente esta linha e comente a de baixo e adicione o token como string
github_token: "{{ lookup('env','GITHUB_TOKEN') | default('', true) }}"
```
> **Importante:** **não** coloque variáveis específicas de projetos aqui.

---

## 📦 Definição dos projetos por ENV (1..N)
Defina a lista de projetos por `PROJECTS` e, para cada `<ID>`, configure ENVs com o **prefixo em maiúsculas e `__`**:

```
LE_EMAIL=example@example.com.br  # email que será usado pelo traefik para autenticação de certificados
PROXY_NETWORK_NAME=proxy         # nome da rede que gerência os containers que devem ter certificados (default: 'proxy')
BASE_OPT_DIR=/opt                # nome da pasta que deve armazenar os projetos e o traefik caso escolha (default: /opt)
PROJECTS="projeto1,projeto2,projeto3, django"  # nome dos projetos que devem ser criados. Ele executa os projetos de 1..N separado por ',' dentro desta lista.
GITHUB_TOKEN="ghp_exemplo_de_token"            # github token para acessar os projetos 

<DJANGO__REPO_URL>           # (obrigatório) url do repositório de preferência em https
<DJANGO__PROJECT_DIR>        # (opcional) caso queira mudar o nome da pasta do projeto independente do nome na lista; default: /opt/<project>
<DJANGO__COMPOSE_PATH>       # (opcional) caminho para o arquivo docker-compose.yml (ou arquivo com nome diferente); default: docker-compose.yml
<DJANGO__PROJECT_NAME>       # (opcional) caso queira mudar o nome do projeto independete do nome do projeto na lista; 
<DJANGO__ENV_SRC>            # (opcional) arquivo de envs no nó de controle; default: ./django.env
```

### Exemplo prático
```bash
export PROJECTS="django, flutter"

# projeto 1
export DJANGO__REPO_URL=https://git.example.com/org/django-app.git
export DJANGO__PROJECT_NAME=django-livre
export DJANGO__COMPOSE_PATH=docker-compose.yml
export DJANGO__ENV_SRC=./django.env

# projeto 2
export FLUTTER__REPO_URL=https://git.example.com/org/flutter-app.git
export FLUTTER__PROJECT_DIR=/opt/flutter-app
export FLUTTER__COMPOSE_PATH=docker/compose/prod.yml
export FLUTTER__ENV_SRC=./flutter.env
```

> **Dica:** consolide esses `export` em um `.env` e rode o `bootstrap-ansible.sh` para carregá-los.

---

## 🔐 Sobre os arquivos `*.env` (control node) → `.env` do projeto

Para cada `<ID>`, crie um arquivo `./<ID>.env` (ou aponte outro caminho via `<ID>__ENV_SRC`).  
Após o clone, a role `project_deploy` **copia** o **`<ID>.env` que está na raiz do playbook** e tranvere para o node **dentro da pasta do projeto com o nome `.env`**.

**Exemplo de `django.env`:**
```
APP_IMAGE=org/connecta:latest
APP_SECRET=supersegredo
DATABASE_URL=postgres://user:pass@db:5432/app
VIRTUAL_HOST=app.seu-dominio.gov.br
```

> Esses `<ID>.env` vivem no **nó de controle** (não no host alvo).
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
1) Garanta as ENVs carregadas (ex.: use `export EXAMPLE_ENV=teste` para cada uma das envs necessárias, `source .env` **ou** use o `source bootstrap-ansible.sh`).  
2) Rode o play:
```bash
ansible-playbook playbooks/deploy.yml
```

Durante a execução você verá **prompts S/N**:
1. Checar/instalar **Docker/Compose**? (S/N) (default **S**)  
2. Instalar **Traefik + Let’s Encrypt**? (S/N) (default **S**)

---

## 🔄 O que a automação faz (por projeto)
1. **Clona/atualiza** o repositório em `/opt/<id>` (ou `<ID>__PROJECT_DIR`).
2. **Gera/atualiza `.env`** a partir de `<ID>__ENV_SRC` (ex.: `./connecta.envs`).
3. **(Se a rede `proxy` existir)** injeta a network externa `proxy` no `docker-compose.yml` e vincula todos os serviços.
4. **Derruba** containers que pertencerem ao **mesmo projeto** sendo executado na lista ou que tenham **nome similar** ao container no projeto.
5. Executa **build** e **up -d** com Compose v2 (respeitando `COMPOSE_PATH`).
6. Faz **health-check**: containers com `HEALTHCHECK` devem ficar `healthy`; os demais ao menos `running`.

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