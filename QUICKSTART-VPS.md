# Rodar na porta 5005 (VPS)

Resumo: este projeto é **uma página de aviso** (HTML) servida por um
**app Python mínimo** (`app.py`, só biblioteca padrão). Ele entrega o aviso em
**qualquer rota** — inclusive `/login`, que é o favorito salvo pelos usuários —
na porta **5005**. Não há banco, Node, nginx nem dependências para instalar.

```
Navegador -> VPS:5005 -> app.py (Python) -> index.html
```

| Rota | Resposta |
|---|---|
| `/`, `/login`, qualquer caminho | `index.html` com `200` (nunca 404) |
| `/healthz` | `200 ok` — usado pelo healthcheck do Docker |

> A música de fundo foi **retirada** da página (sem player, sem `audio.mp3`).

---

## 0. Jeito mais rápido, SEM Docker (1 comando)

Se a VPS tem Python 3.8+ (praticamente todas têm), não precisa de Docker:

```bash
cd ~/avisos
python3 app.py        # sobe em 0.0.0.0:5005
```

Em outro terminal, confirme: `curl -I http://127.0.0.1:5005/login` → `HTTP/1.1 200 OK`.

Para ficar rodando sempre (e voltar após reboot), use o `aviso-ponto.service`
que está neste repositório:

```bash
cd ~/avisos
sudo cp aviso-ponto.service /etc/systemd/system/
sudo sed -i "s#/root/avisos#$(pwd)#" /etc/systemd/system/aviso-ponto.service
sudo systemctl daemon-reload
sudo systemctl enable --now aviso-ponto
systemctl status aviso-ponto --no-pager
sudo journalctl -u aviso-ponto -f     # logs (Ctrl+C para sair)
```

> Confira se o `ExecStart` aponta para o python certo (`which python3`).
> Se o projeto estiver em outra pasta, ajuste o `WorkingDirectory` no arquivo.

## 1. Com Docker — script pronto

```bash
cd ~/avisos
chmod +x deploy-vps.sh
sudo ./deploy-vps.sh
```

O script constrói a imagem, recria o contêiner, espera ficar saudável e testa
`/`, `/login` e `/healthz` (todos precisam dar **200**):

```
✔ Página de aviso no ar:  http://10.105.35.172:5005/login
```

Outra porta: `sudo PORTA_HOST=8080 ./deploy-vps.sh`

## 2. Com Docker — manual

```bash
docker compose up -d --build          # publica 0.0.0.0:5005 -> 5005
docker compose logs -f                # Ctrl+C para sair
curl -I http://127.0.0.1:5005/login   # esperado: HTTP/1.1 200 OK
```

Sem o plugin `docker compose`:

```bash
docker build -t aviso-ponto .
docker run -d --name aviso-ponto --restart unless-stopped -p 0.0.0.0:5005:5005 aviso-ponto
```

## 3. Deploy pelo Dokploy

Use o tipo **Compose** apontando para este repositório (o `docker-compose.yml`
já publica `5005:5005`) **ou** o tipo **Application** com build *Dockerfile* e,
em **Advanced → Ports**, `Published 5005` → `Target 5005`. Passo a passo em
[`DEPLOY-DOCKPLOY.md`](./DEPLOY-DOCKPLOY.md).

> O Dokploy só responde no IP da máquina onde ele está instalado. Se estiver em
> outra VPS, `http://10.105.35.172:5005` **não** vai funcionar — rode na
> máquina antiga (seção 0 ou 1).

---

## 4. Conferir se está mesmo na 5005

```bash
ss -ltnp | grep :5005
# LISTEN 0.0.0.0:5005 users:(("python3",pid=...))        <- sem Docker
# LISTEN 0.0.0.0:5005 users:(("docker-proxy",pid=...))   <- com Docker

curl -s http://127.0.0.1:5005/login | grep -o '<title>.*</title>'
# <title>Aviso — Sistema de Ponto migrado | Praticus</title>

curl -s -o /dev/null -w '%{http_code} %{content_type}\n' http://127.0.0.1:5005/
# 200 text/html; charset=utf-8
```

De outra máquina da rede: `curl -I http://10.105.35.172:5005/login`

---

## 5. Se a página não aparecer

Rode o diagnóstico (não altera nada, só coleta):

```bash
chmod +x diagnostico.sh
sudo ./diagnostico.sh
```

Ele gera `diagnostico-AAAAMMDD-HHMMSS.txt` com: contêineres, **quem** está
ouvindo na 5005 (Docker ou `python3 app.py`), md5 do que é servido comparado ao
`index.html` local, testes HTTP em `/`, `/login` e `/healthz`,
logs, firewall e um veredito.

| Sintoma | Causa / solução |
|---|---|
| `address already in use` ao subir | Porta ocupada pelo app **antigo** de ponto. `ss -ltnp \| grep 5005` mostra o dono; pare (`docker stop ...` / `systemctl stop ...`). |
| Funciona em `127.0.0.1` mas não de fora | Firewall: `sudo ufw allow 5005/tcp` **e** liberar 5005 no Security Group/firewall do provedor. |
| `/login` dá **404** | Você está usando `python -m http.server` ou o build *Static* do Dokploy. Use `python3 app.py` ou a imagem deste repo (qualquer rota cai no aviso). |
| Aparece **"Welcome to nginx!"** | Outro nginx ainda responde na porta: pare esse serviço e suba este app. |
| Navegador **baixa** o arquivo / mostra o código | `Content-Type` errado (servidor estático antigo). O `app.py` envia `text/html; charset=utf-8`. |
| Abre o **sistema antigo** de ponto | Outro processo/contêiner ocupa a 5005 — pare o antigo antes. |
| `docker: command not found` | Use a seção 0 (sem Docker) ou `curl -fsSL https://get.docker.com \| sh`. |
| `permission denied ... docker.sock` | Rode com `sudo` ou `sudo usermod -aG docker $USER && newgrp docker`. |
| Aviso antigo no navegador | O app manda `no-cache`; force `Ctrl+F5`. |
| Quer trocar o IP/URL do texto | Edite `index.html` e reinicie (`systemctl restart aviso-ponto` ou `sudo ./deploy-vps.sh`). |

> Mudou `index.html` ou `app.py`? Com Docker é obrigatório **rebuildar**
> (`sudo ./deploy-vps.sh` ou `docker compose up -d --build`). `docker restart`
> sozinho **não** copia arquivos novos para dentro da imagem.

---

## 6. Comandos do dia a dia

```bash
# --- com Docker ---
docker logs -f aviso-ponto        # logs do app (um acesso por linha)
docker restart aviso-ponto        # reiniciar
docker rm -f aviso-ponto          # parar e remover
docker compose up -d --build      # atualizar após editar index.html/app.py
docker port aviso-ponto           # conferir o mapeamento (5005/tcp -> 0.0.0.0:5005)

# --- sem Docker ---
python3 app.py                    # primeiro plano (Ctrl+C para parar)
sudo systemctl restart aviso-ponto
sudo journalctl -u aviso-ponto -f
```

O contêiner usa `restart: unless-stopped` (e no modo systemd, `Restart=always`),
então a página volta sozinha se a VPS reiniciar.

