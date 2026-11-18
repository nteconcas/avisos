#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Sobe a página de aviso na porta 5005 da VPS, de forma idempotente.
#
# Uso (na VPS, dentro desta pasta):
#   chmod +x deploy-vps.sh
#   ./deploy-vps.sh                   # sobe/atualiza na 5005
#   PORTA_HOST=8080 ./deploy-vps.sh   # muda a porta, se precisar
#
# O script: confere Docker, libera/recria o contêiner, faz build, sobe,
# espera ficar saudável e testa /, /login e /healthz.
# ---------------------------------------------------------------------------
set -uo pipefail

PORTA_HOST="${PORTA_HOST:-5005}"
PORTA_CONTAINER="${PORTA_CONTAINER:-5005}"
NOME_CONTAINER="${NOME_CONTAINER:-aviso-ponto}"
IMAGEM="${IMAGEM:-aviso-ponto:latest}"

# Usada pelo docker-compose.yml (fallback 5005 se não existir)
export PORTA_HOST

info() { printf '\033[1;36m»\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✔\033[0m %s\n' "$*"; }
aviso(){ printf '\033[1;33m!\033[0m %s\n' "$*"; }
erro() { printf '\033[1;31m✘\033[0m %s\n' "$*" >&2; }

# --- 0. Estamos na pasta certa? -------------------------------------------
if [ ! -f Dockerfile ] || [ ! -f app.py ] || [ ! -f index.html ]; then
  erro "Execute este script dentro da pasta do projeto (onde estão Dockerfile, app.py e index.html)."
  exit 1
fi

# --- 1. Docker instalado e funcionando? -----------------------------------
if ! command -v docker >/dev/null 2>&1; then
  erro "Docker não encontrado nesta VPS."
  echo "  Instale com:  curl -fsSL https://get.docker.com | sh"
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  erro "Sem permissão/falha ao falar com o Docker daemon."
  echo "  Rode como root ou com sudo:  sudo ./deploy-vps.sh"
  echo "  (ou: sudo usermod -aG docker \$USER && newgrp docker)"
  exit 1
fi
ok "Docker: $(docker --version | cut -d, -f1)"

# Compose v2 é preferível; se não existir, caímos para 'docker run'.
USAR_COMPOSE=0
if docker compose version >/dev/null 2>&1; then
  USAR_COMPOSE=1
  ok "Compose: $(docker compose version --short 2>/dev/null || echo v2)"
else
  aviso "Plugin 'docker compose' ausente — vou usar 'docker run' direto."
fi

# --- 2. A porta 5005 está livre? ------------------------------------------
porta_em_uso() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${PORTA_HOST}$"
  elif command -v netstat >/dev/null 2>&1; then
    netstat -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${PORTA_HOST}$"
  else
    return 1
  fi
}

# Quem está publicando a porta? (para mensagem de erro útil)
dono_da_porta() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltnp 2>/dev/null | grep -E "[:.]${PORTA_HOST}[[:space:]]" || true
  elif command -v netstat >/dev/null 2>&1; then
    netstat -ltnp 2>/dev/null | grep -E "[:.]${PORTA_HOST}[[:space:]]" || true
  fi
}

if porta_em_uso; then
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$NOME_CONTAINER"; then
    aviso "Porta ${PORTA_HOST} já está com o contêiner '${NOME_CONTAINER}' — vou recriá-lo."
  else
    erro "A porta ${PORTA_HOST} está ocupada por outro processo:"
    dono_da_porta | sed 's/^/    /'
    echo
    echo "  Pare o serviço antigo (app de ponto) e rode de novo. Exemplos:"
    echo "    docker ps                      # descobrir o contêiner"
    echo "    docker stop <container>        # parar"
    echo "    systemctl stop <servico>       # se for serviço do systemd"
    echo "    ss -ltnp | grep ${PORTA_HOST}  # confirmar que liberou"
    exit 1
  fi
fi

# --- 3. Remove contêiner anterior com o mesmo nome ------------------------
if docker ps -a --format '{{.Names}}' | grep -qx "$NOME_CONTAINER"; then
  info "Removendo contêiner anterior '${NOME_CONTAINER}'..."
  docker rm -f "$NOME_CONTAINER" >/dev/null || {
    erro "Não consegui remover o contêiner '${NOME_CONTAINER}'."
    exit 1
  }
fi

# --- 4. Build -------------------------------------------------------------
info "Fazendo build da imagem ${IMAGEM}..."
if ! docker build -t "$IMAGEM" .; then
  erro "Falha no build da imagem."
  exit 1
fi
ok "Imagem construída."

# --- 5. Subir o serviço na porta 5005 ------------------------------------
if [ "$USAR_COMPOSE" -eq 1 ] && [ -f docker-compose.yml ]; then
  info "Subindo via docker compose (${PORTA_HOST} -> ${PORTA_CONTAINER})..."
  if ! docker compose up -d --build; then
    erro "Falha no 'docker compose up'. Veja: docker compose logs --tail=100"
    exit 1
  fi
else
  info "Subindo via docker run (${PORTA_HOST} -> ${PORTA_CONTAINER})..."
  if ! docker run -d \
      --name "$NOME_CONTAINER" \
      --restart unless-stopped \
      -p "0.0.0.0:${PORTA_HOST}:${PORTA_CONTAINER}" \
      "$IMAGEM"; then
    erro "Falha no 'docker run'. Veja: docker logs ${NOME_CONTAINER}"
    exit 1
  fi
fi

# --- 6. Esperar ficar de pé ----------------------------------------------
info "Aguardando o serviço responder em http://127.0.0.1:${PORTA_HOST}/ ..."
PRONTO=0
for _ in $(seq 1 30); do
  if curl -fsS -o /dev/null "http://127.0.0.1:${PORTA_HOST}/" 2>/dev/null; then
    PRONTO=1
    break
  fi
  sleep 1
done

if [ "$PRONTO" -ne 1 ]; then
  erro "O serviço não respondeu em 30s."
  echo "  Últimas linhas do log:"
  docker logs --tail=50 "$NOME_CONTAINER" 2>&1 | sed 's/^/    /'
  exit 1
fi
ok "Serviço respondendo."

# --- 7. Testes de aceitação ----------------------------------------------
CODIGO_RAIZ=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORTA_HOST}/")
CODIGO_LOGIN=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORTA_HOST}/login")
CODIGO_SAUDE=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORTA_HOST}/healthz")
TIPO_RAIZ=$(curl -s -o /dev/null -w '%{content_type}' "http://127.0.0.1:${PORTA_HOST}/")
TITULO=$(curl -fsS "http://127.0.0.1:${PORTA_HOST}/login" 2>/dev/null | grep -o '<title>[^<]*</title>' | head -1)

printf '   /          -> HTTP %s (%s)\n' "$CODIGO_RAIZ" "${TIPO_RAIZ:-?}"
printf '   /login     -> HTTP %s  (precisa ser 200: é o favorito dos usuários)\n' "$CODIGO_LOGIN"
printf '   /healthz   -> HTTP %s\n' "$CODIGO_SAUDE"
printf '   título     -> %s\n' "${TITULO:-<não encontrado>}"

if [ "$CODIGO_RAIZ" != "200" ] || [ "$CODIGO_LOGIN" != "200" ] || [ "$CODIGO_SAUDE" != "200" ]; then
  erro "Os testes falharam. Verifique: docker logs ${NOME_CONTAINER}"
  exit 1
fi

if ! printf '%s' "$TITULO" | grep -q 'Aviso'; then
  aviso "A página respondeu, mas o título esperado não apareceu."
  aviso "Provável imagem velha em cache: rode novamente com --build (o script já faz)."
fi

info "Mapeamento publicado pelo Docker:"
docker port "$NOME_CONTAINER" 2>/dev/null | sed 's/^/    /' || true

IP_DETECTADO=$(hostname -I 2>/dev/null | awk '{print $1}')
echo
ok "Página de aviso no ar:  http://${IP_DETECTADO:-IP-DA-VPS}:${PORTA_HOST}/login"
echo "   Local:                http://127.0.0.1:${PORTA_HOST}/login"
echo
echo "Se não abrir de outras máquinas, libere o firewall:"
echo "  ufw:       sudo ufw allow ${PORTA_HOST}/tcp"
echo "  firewalld: sudo firewall-cmd --permanent --add-port=${PORTA_HOST}/tcp && sudo firewall-cmd --reload"
echo "  cloud:     libere a porta ${PORTA_HOST} no Security Group / firewall do provedor"
echo
echo "Logs:   docker logs -f ${NOME_CONTAINER}"
echo "Parar:  docker rm -f ${NOME_CONTAINER}   (ou: docker compose down)"
echo
echo "Sem Docker? O app é Python puro e roda direto:"
echo "  python3 app.py            # sobe em 0.0.0.0:5005"
echo "  (detalhes do modo systemd em QUICKSTART-VPS.md)"
