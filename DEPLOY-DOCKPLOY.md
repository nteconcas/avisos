# Hospedando a página de aviso no Dokploy

Guia para publicar a página de desativação do sistema de ponto
(`index.html`, servida pelo app Python mínimo `app.py`) usando o **Dokploy**
(PaaS open-source, auto-hospedado).

---

## 0. Entenda a estratégia antes de começar

O objetivo é que quem abrir o endereço antigo **http://10.105.35.172:5005/login**
veja a página de aviso (e seja levado ao novo endereço `https://ponto.praticus.com.br/login`).

Como `10.105.35.172` é um **IP**, a página precisa ser servida **por essa máquina**,
na **porta 5005**. Há dois cenários:

| Cenário | O que fazer |
|---|---|
| **A — Dokploy no próprio servidor antigo (10.105.35.172)** | Siga este guia completo. O Dokploy publica a porta `5005 → 5005` do contêiner (app Python). |
| **B — Dokploy em outro servidor (ex.: na cloud)** | O Dokploy de lá **não consegue** responder pelo IP antigo. Nesse caso, rode o contêiner direto na máquina antiga com `docker compose up -d --build` (seção 8), ou instale o Dokploy nela também. |

> Em ambos os casos, **pare o app antigo** que ocupava a porta 5005 antes de subir a página.

### Arquivos deste diretório

```
avisos/
├── app.py              ← servidor Python (só stdlib): aviso em QUALQUER rota, porta 5005
├── index.html          ← a página de aviso
├── audio.mp3           ← música de fundo (WAV original convertido para MP3)
├── Dockerfile          ← imagem python:3.12-slim com o app
├── docker-compose.yml  ← alternativa (Compose / docker direto), publica 5005:5005
├── deploy-vps.sh       ← sobe/valida na 5005 com um comando
├── verificar-musica.py ← confere página + MP3 pela rede (roda sem navegador)
├── diagnostico.sh      ← coleta o estado quando algo não abre
├── aviso-ponto.service ← unit do systemd (rodar sem Docker)
├── politicas/          ← como liberar o autoplay do som nas máquinas
├── QUICKSTART-VPS.md   ← passo a passo resumido
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

> **Atalho:** em vez de seguir este guia inteiro, rode `sudo ./deploy-vps.sh`
> na VPS — ele sobe a página na porta 5005 e testa `/`, `/login`, `/audio.mp3`
> e `/healthz`. Detalhes em [`QUICKSTART-VPS.md`](./QUICKSTART-VPS.md).
>
> **Sem Docker?** O app é Python puro: `python3 app.py` já sobe em `0.0.0.0:5005`
> (veja a seção 0 do QUICKSTART).

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
cd avisos
git init
git add .
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

> **Por que Dockerfile e não "Static"?** O tipo *Static* do Dokploy serve os
> arquivos com um nginx genérico e devolve **404** em `/login`, que é o endereço
> salvo nos favoritos dos usuários. Aqui quem responde é o `app.py`: **qualquer
> rota** exibe o aviso (200) e o áudio é servido com suporte a `Range`. O
> contêiner escuta na porta **5005**.

## 6. Publicar a porta 5005 (aba Advanced → Ports)

Adicione uma porta:

| Campo | Valor |
|---|---|
| **Published Port** (host) | `5005` |
| **Target Port** (contêiner) | `5005` |
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
   com redirecionamento automático para `https://ponto.praticus.com.br/login` após 10 s.
   A música de fundo pede para tocar **com som já no carregamento** e segue em loop
   até o redirecionamento (a contagem não pausa).

   > **Autoplay com som:** Chrome/Edge bloqueiam som sem interação do usuário por
   > padrão. A página insiste sozinha e libera no primeiro toque/clique, mas para
   > tocar automaticamente em todas as máquinas aplique a política
   > `AutoplayAllowed` / `AutoplayAllowlist` — arquivos prontos e instruções em
   > [`politicas/README.md`](politicas/README.md).

> Se quiser confirmar o que está no ar sem abrir o navegador:
> `curl -s -o /dev/null -w '%{http_code} %{content_type}\n' http://IP:5005/`
> (esperado: `200 text/html; charset=utf-8`).
>
> Verificação completa (página + player + MP3 + `Range`), sem navegador:
> `python3 verificar-musica.py http://IP:5005` → termina em `TUDO OK`.

### (Opcional) Servir também por um domínio com HTTPS

Se quiser a página também em um domínio (ex.: `aviso.praticus.com.br`):

1. Aponte o DNS (registro A) para o IP do servidor Dokploy
2. Na aba **Domains** da aplicação: **Add Domain**
   - Host: `aviso.praticus.com.br` · Path: `/` · **Container Port: 5005**
   - HTTPS: ativado · Certificate: **Let's Encrypt**
3. **Save** → **Deploy**

## 8. Alternativas de deploy

### 8.1 Via Dokploy tipo "Compose"

Em vez de Application, crie **Create Service → Compose**, aponte para o repo
(o `docker-compose.yml` já está pronto, publicando `5005:5005`) e clique em
**Deploy**. Mesmo resultado, sem precisar configurar a aba Ports.

### 8.2 Sem Dokploy na máquina antiga (cenário B)

Na máquina `10.105.35.172`, **sem Docker** (mais simples, só precisa de Python 3):

```bash
git clone git@github.com:SUA-ORG/aviso-ponto.git
cd aviso-ponto
python3 app.py                 # sobe em 0.0.0.0:5005
```

Para deixar como serviço, veja o `aviso-ponto.service` (systemd) na seção 0 do
[`QUICKSTART-VPS.md`](./QUICKSTART-VPS.md).

Com Docker:

```bash
docker compose up -d --build
# ou, sem compose:
docker build -t aviso-ponto .
docker run -d --name aviso-ponto -p 5005:5005 --restart unless-stopped aviso-ponto
```

## 9. Atualizações futuras

1. Edite o `index.html` (ou o `app.py`) e faça `git push`
2. No Dokploy, clique em **Deploy** (ou ative o **Auto Deploy** via webhook nas
   configurações do provider para redeployar a cada push)
3. Sem Dokploy: `sudo ./deploy-vps.sh` (Docker) ou `sudo systemctl restart aviso-ponto`

## 10. Solução de problemas

| Sintoma | Causa provável / solução |
|---|---|
| Deploy falha com erro de porta | 5005 (ou 80/443/3000) ocupada. `ss -tlnp \| grep 5005` e pare o serviço antigo. |
| Página não abre de outras máquinas | Firewall do servidor ou da rede: libere `5005/tcp`. |
| `/login` retorna 404 | Build *Static* (nginx genérico) ou `python -m http.server`. Use o build **Dockerfile** deste repo ou `python3 app.py`. |
| Aparece "Welcome to nginx!" | Outro serviço responde na porta: pare o contêiner/nginx antigo. |
| Página em branco ou baixando o arquivo | `Content-Type` errado — o `app.py` envia `text/html; charset=utf-8`; use a imagem deste repo. |
| Healthcheck vermelho no Dokploy | O app responde em `/healthz`; se falhar, veja os logs do deploy (porta errada no `Target Port`). |
| Aviso antigo aparece após edição | Cache do navegador — o app já envia `no-cache`; force `Ctrl+F5`. |
| Instalação do Dokploy falha | Portas 80/443/3000 em uso, ou menos de 2 GB de RAM. |

---

**Referências oficiais:**
- Instalação: https://docs.dokploy.com/docs/core/installation
- Build types (Static/Dockerfile): https://docs.dokploy.com/docs/core/applications/build-type
- Portas (Advanced → Ports): https://docs.dokploy.com/docs/core/applications/advanced#ports
- Domínios/Traefik: https://docs.dokploy.com/docs/core/domains
