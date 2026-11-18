# Rodar na porta 5005 (VPS)

Resumo: este projeto é **uma página estática de aviso** (HTML + MP3) servida por
**nginx dentro de um contêiner**. O nginx escuta a porta **80 dentro do
contêiner** e o Docker publica essa porta como **5005 no host/VPS**.
Não há back-end, banco, Python ou Node para executar — só Docker.

```
Navegador -> VPS:5005 -> [docker-proxy] -> contêiner:80 (nginx) -> index.html
```

---

## 1. Jeito mais rápido (script pronto)

Na VPS, com o projeto já copiado/clonado:

```bash
cd ~/avisos                      # pasta com Dockerfile, index.html, nginx.conf
chmod +x deploy-vps.sh
sudo ./deploy-vps.sh
```

O script faz tudo e no final testa `GET /` e `GET /login` (precisa dar **200**):

```
✔ Página de aviso no ar:  http://10.105.35.172:5005/login
```

Se quiser outra porta: `sudo PORTA_HOST=8080 ./deploy-vps.sh`

## 2. Jeito manual (3 comandos)

```bash
docker compose up -d --build          # sobe publicando 0.0.0.0:5005 -> 80
docker compose logs -f                # acompanhar (Ctrl+C para sair)
curl -I http://127.0.0.1:5005/login   # esperado: HTTP/1.1 200 OK
```

Sem o plugin `docker compose` (Docker antigo):

```bash
docker build -t aviso-ponto .
docker run -d --name aviso-ponto --restart unless-stopped -p 0.0.0.0:5005:80 aviso-ponto
```

## 3. Deploy pelo Dokploy

Use o tipo **Compose** apontando para este repositório (o `docker-compose.yml`
já publica `5005:80`) **ou** o tipo **Application** com build *Dockerfile* e, em
**Advanced → Ports**, `Published 5005` → `Target 80`. Passo a passo completo em
[`DEPLOY-DOCKPLOY.md`](./DEPLOY-DOCKPLOY.md).

> Importante: o Dokploy só responde no IP da máquina onde ele está instalado.
> Se ele estiver em outra VPS, o `http://10.105.35.172:5005/login` **não** vai
> funcionar — use o script/`docker compose` na própria máquina antiga.

---

## 4. Conferir se está mesmo na 5005

```bash
docker port aviso-ponto
# 80/tcp -> 0.0.0.0:5005

ss -ltnp | grep :5005
# LISTEN ... 0.0.0.0:5005  users:(("docker-proxy",pid=...))

curl -s http://127.0.0.1:5005/login | grep -o '<title>.*</title>'
# <title>Aviso — Sistema de Ponto migrado | Praticus</title>
```

De outra máquina da rede: `curl -I http://10.105.35.172:5005/login`

---

## 5. Se a 5005 não subir

| Sintoma | Causa / solução |
|---|---|
| `bind: address already in use` | Porta ocupada pelo app **antigo** de ponto. Veja quem está nela: `ss -ltnp \| grep 5005` e pare (`docker stop <container>` / `systemctl stop <servico>`). O script já avisa quem é o dono da porta. |
| Funciona em `127.0.0.1` mas não de fora | Firewall: `sudo ufw allow 5005/tcp` **e** liberar 5005 no Security Group/firewall do provedor da VPS. |
| `/login` dá 404 | Você subiu um servidor estático simples (ex.: `python -m http.server`). Use a imagem deste repo: o `nginx.conf` tem `try_files ... /index.html`, então **qualquer** rota cai no aviso. |
| `docker: command not found` | `curl -fsSL https://get.docker.com \| sh` |
| `permission denied ... docker.sock` | Rode com `sudo` ou entre no grupo: `sudo usermod -aG docker $USER && newgrp docker` |
| Aviso antigo/cacheado no navegador | O nginx manda `no-cache`; force `Ctrl+F5`. |
| Quer trocar o IP/URL do texto | Edite `index.html` (IP antigo e `ponto.praticus.com.br`) e rode `sudo ./deploy-vps.sh` de novo. |

---

## 6. Comandos do dia a dia

```bash
docker logs -f aviso-ponto        # logs do nginx (access log)
docker restart aviso-ponto        # reiniciar
docker rm -f aviso-ponto          # parar e remover
docker compose up -d --build      # atualizar após editar index.html
```

O contêiner usa `--restart unless-stopped`, então volta sozinho se a VPS reiniciar.
