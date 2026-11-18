# Hospedando a página de aviso no Dokploy

Guia para publicar a página estática de desativação do sistema de ponto
(`index.html`) usando o **Dokploy** (PaaS open-source, auto-hospedado).

---

## 0. Entenda a estratégia antes de começar

O objetivo é que quem abrir o endereço antigo **http://10.105.35.172:5005/login**
veja a página de aviso (e seja levado ao novo endereço `https://ponto.praticus.com.br/login`).

Como `10.105.35.172` é um **IP**, a página precisa ser servida **por essa máquina**,
na **porta 5005**. Há dois cenários:

| Cenário | O que fazer |
|---|---|
| **A — Dokploy no próprio servidor antigo (10.105.35.172)** | Siga este guia completo. O Dokploy publica a porta `5005 → 80` do contêiner. |
| **B — Dokploy em outro servidor (ex.: na cloud)** | O Dokploy de lá **não consegue** responder pelo IP antigo. Nesse caso, rode o contêiner direto na máquina antiga com `docker compose up -d --build` (seção 8), ou instale o Dokploy nela também. |

> Em ambos os casos, **pare o app antigo** que ocupava a porta 5005 antes de subir a página.

### Arquivos deste diretório

```
aviso-desativacao/
├── index.html          ← a página de aviso
├── nginx.conf          ← serve o aviso em QUALQUER rota (/login inclusive)
├── Dockerfile          ← imagem nginx:alpine com a página
├── docker-compose.yml  ← alternativa (Compose / docker direto), porta 5005
└── DEPLOY-DOCKPLOY.md  ← este guia
```

---

## 1. Pré-requisitos do servidor

- Linux (Ubuntu 20.04+/Debian 11+ são os mais testados), acesso **root**
- Mínimo **2 GB de RAM** e **30 GB de disco** (recomendação oficial do Dokploy)
- Portas **80**, **443** e **3000** livres (a instalação falha se estiverem ocupadas)
- Docker — se não existir, o instalador do Dokploy instala automaticamente

Verifique as portas ocupadas:

```bash
ss -tlnp | grep -E ':(80|443|3000|5005)\b'
```

Se o app antigo de ponto ainda estiver rodando na 5005, pare-o
(`docker stop <container>`, `systemctl stop <serviço>`, etc.).

## 2. Instalar o Dokploy (pule se já tiver)

```bash
curl -sSL https://dokploy.com/install.sh | sh
```

Ao terminar:

1. Acesse `http://IP-DO-SERVIDOR:3000`
2. Crie a conta de administrador (a primeira conta criada é o admin)

> Se o servidor tiver mais de uma interface de rede e o instalador não detectar
> o IP certo: `curl -sSL https://dokploy.com/install.sh | sudo ADVERTISE_ADDR=10.105.35.172 sh`

## 3. Colocar os arquivos em um repositório Git

O Dokploy faz deploy a partir de um repositório (GitHub, GitLab, Bitbucket, Gitea
ou Git puro). Crie um repositório, ex. `aviso-ponto`, com os arquivos deste diretório:

```bash
cd aviso-desativacao
git init
git add index.html nginx.conf Dockerfile .dockerignore
git commit -m "Página de aviso: sistema de ponto migrado para a nuvem"
git remote add origin git@github.com:SUA-ORG/aviso-ponto.git
git push -u origin main
```

> Não tem Git externo? Use o provider **Git** do Dokploy com qualquer URL de
> repositório acessível pelo servidor (inclusive um Gitea interno).

## 4. Criar a aplicação no Dokploy

1. No painel: **Create Project** → dê um nome (ex.: `Aviso Ponto`)
2. Dentro do projeto: **Create Service → Application**
3. Nome: `aviso-ponto`
4. Na aba **Provider**, conecte sua conta GitHub/GitLab (ou use **Git** com a URL do repo)
5. Selecione o **repositório** e a **branch** (`main`)

## 5. Configurar o build (aba General → Build Type)

Escolha **Dockerfile** e preencha:

| Campo | Valor |
|---|---|
| Dockerfile Path | `./Dockerfile` |
| Docker Context Path | `.` |
| Docker Build Stage | *(deixe vazio)* |

> **Por que Dockerfile e não "Static"?** O tipo *Static* do Dokploy também usa
> nginx, mas com o nosso `nginx.conf` garantimos que **qualquer rota** — inclusive
> `/login`, que é o endereço salvo nos favoritos dos usuários — exiba o aviso em
> vez de um erro 404. O contêiner escuta na porta **80**.

## 6. Publicar a porta 5005 (aba Advanced → Ports)

Adicione uma porta:

| Campo | Valor |
|---|---|
| **Published Port** (host) | `5005` |
| **Target Port** (contêiner) | `80` |
| **Protocol** | `TCP` |

Clique em **Save**. É isso que faz `http://10.105.35.172:5005` apontar para a página.

> ⚠️ A porta 5005 precisa estar livre no host (app antigo parado — veja seção 1).
> ⚠️ Se houver firewall, libere: `ufw allow 5005/tcp` (se usar ufw).

## 7. Deploy e teste

1. Clique em **Deploy** e acompanhe os logs na aba **Logs/Deployments**
2. Quando ficar verde, teste de outra máquina da rede:

```bash
curl -I http://10.105.35.172:5005/login
# Esperado: HTTP/1.1 200 OK

curl -s http://10.105.35.172:5005/login | grep -o "<title>.*</title>"
# Esperado: <title>Aviso — Sistema de Ponto migrado | Praticus</title>
```

3. Abra no navegador: `http://10.105.35.172:5005/login` → deve aparecer o aviso,
   com redirecionamento automático para `https://ponto.praticus.com.br/login` em 15 s.

### (Opcional) Servir também por um domínio com HTTPS

Se quiser a página também em um domínio (ex.: `aviso.praticus.com.br`):

1. Aponte o DNS (registro A) para o IP do servidor Dokploy
2. Na aba **Domains** da aplicação: **Add Domain**
   - Host: `aviso.praticus.com.br` · Path: `/` · **Container Port: 80**
   - HTTPS: ativado · Certificate: **Let's Encrypt**
3. **Save** → **Deploy**

## 8. Alternativas de deploy

### 8.1 Via Dokploy tipo "Compose"

Em vez de Application, crie **Create Service → Compose**, aponte para o repo
(o `docker-compose.yml` já está pronto com `5005:80`) e clique em **Deploy**.
Mesmo resultado, sem precisar configurar a aba Ports.

### 8.2 Sem Dokploy na máquina antiga (cenário B)

Na máquina `10.105.35.172`, com Docker instalado:

```bash
git clone git@github.com:SUA-ORG/aviso-ponto.git
cd aviso-ponto
docker compose up -d --build
```

Ou sem compose:

```bash
docker build -t aviso-ponto .
docker run -d --name aviso-ponto -p 5005:80 --restart unless-stopped aviso-ponto
```

## 9. Atualizações futuras

1. Edite o `index.html` e faça `git push`
2. No Dokploy, clique em **Deploy** (ou ative o **Auto Deploy** via webhook nas
   configurações do provider para redeployar a cada push)

## 10. Solução de problemas

| Sintoma | Causa provável / solução |
|---|---|
| Deploy falha com erro de porta | 5005 (ou 80/443/3000) ocupada. `ss -tlnp \| grep 5005` e pare o serviço antigo. |
| Página não abre de outras máquinas | Firewall do servidor ou da rede: libere `5005/tcp`. |
| `/login` retorna 404 | Está usando build *Static* sem o nosso nginx. Use o build **Dockerfile** deste repo. |
| Aviso antigo aparece após edição | Cache do navegador — o nginx já envia `no-cache`; force `Ctrl+F5`. |
| Instalação do Dokploy falha | Portas 80/443/3000 em uso, ou menos de 2 GB de RAM. |

---

**Referências oficiais:**
- Instalação: https://docs.dokploy.com/docs/core/installation
- Build types (Static/Dockerfile): https://docs.dokploy.com/docs/core/applications/build-type
- Portas (Advanced → Ports): https://docs.dokploy.com/docs/core/applications/advanced#ports
- Domínios/Traefik: https://docs.dokploy.com/docs/core/domains
