#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Diagnóstico: "a página não aparece no endereço http://IP:5005"
#
# Uso (na VPS, dentro do projeto):
#   chmod +x diagnostico.sh
#   sudo ./diagnostico.sh
#
# Ele NÃO altera nada: só coleta e mostra o estado atual, e grava tudo em
# diagnostico-AAAAMMDD-HHMMSS.txt (pode colar esse conteúdo para análise).
# ---------------------------------------------------------------------------
set -uo pipefail

PORTA="${PORTA_HOST:-5005}"
NOME="${NOME_CONTAINER:-aviso-ponto}"
ARQ="diagnostico-$(date +%Y%m%d-%H%M%S).txt"

exec > >(tee "$ARQ") 2>&1

secao() { printf '\n===== %s =====\n' "$*"; }
sub()   { printf -- '--- %s\n' "$*"; }

secao "1. Ambiente"
echo "data:      $(date)"
echo "host:      $(hostname 2>/dev/null)"
echo "sistema:   $(uname -srm 2>/dev/null)"
echo "ip(s):     $(hostname -I 2>/dev/null || ip -4 addr show 2>/dev/null | grep -oE 'inet [0-9.]+' | tr '\n' ' ')"
echo "porta:     ${PORTA}"

secao "2. Docker"
if ! command -v docker >/dev/null 2>&1; then
  echo "DOCKER NÃO INSTALADO -> curl -fsSL https://get.docker.com | sh"
else
  docker --version
  docker compose version 2>/dev/null || echo "docker compose: ausente (usar docker run)"
  sub "Contêineres (todos)"
  docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
fi

secao "3. Quem está ouvindo na porta ${PORTA}"
if command -v ss >/dev/null 2>&1; then
  ss -ltnp | grep -E "[:.]${PORTA}[[:space:]]" || echo "NADA ouvindo na ${PORTA}"
elif command -v netstat >/dev/null 2>&1; then
  netstat -ltnp | grep -E "[:.]${PORTA}[[:space:]]" || echo "NADA ouvindo na ${PORTA}"
else
  echo "ss/netstat indisponível"
fi

secao "4. Contêiner que deveria servir a página"
if command -v docker >/dev/null 2>&1; then
  CID=$(docker ps -q --filter "publish=${PORTA}" | head -1)
  [ -z "$CID" ] && CID=$(docker ps -aq --filter "name=^${NOME}$" | head -1)
  if [ -z "$CID" ]; then
    echo "NENHUM contêiner publicado na ${PORTA} e nenhum chamado '${NOME}'."
    echo "-> A página não está no ar. Rode: sudo ./deploy-vps.sh"
  else
    docker inspect "$CID" --format 'nome:    {{.Name}}
imagem:  {{.Config.Image}}
status:  {{.State.Status}}  (health: {{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}})
erro:    {{.State.Error}}
portas:  {{json .NetworkSettings.Ports}}'
    sub "Mapeamento publicado (docker port)"
    docker port "$CID" || true
    sub "Arquivos servidos dentro do contêiner"
    docker exec "$CID" ls -la /usr/share/nginx/html 2>&1 || true
    sub "Config do nginx dentro do contêiner (/etc/nginx/conf.d/default.conf)"
    docker exec "$CID" cat /etc/nginx/conf.d/default.conf 2>&1 || true
    sub "Teste de sintaxe do nginx (nginx -t)"
    docker exec "$CID" nginx -t 2>&1 || true
  fi
fi

secao "5. Testes HTTP em 127.0.0.1:${PORTA}"
if command -v curl >/dev/null 2>&1; then
  for caminho in / /index.html /login /audio.mp3 /qualquer-coisa; do
    printf '  %-16s -> ' "$caminho"
    curl -s -o /tmp/_diag_body -w 'HTTP %{http_code} | tipo: %{content_type} | bytes: %{size_download}\n' \
      --max-time 5 "http://127.0.0.1:${PORTA}${caminho}" || echo "FALHOU (conexão recusada/timeout)"
  done
  sub "Primeiras linhas do que o / entrega"
  curl -s --max-time 5 "http://127.0.0.1:${PORTA}/" | head -8
else
  echo "curl não instalado -> apt-get install -y curl"
fi

secao "6. A página certa está dentro do contêiner?"
if [ -n "${CID:-}" ] && [ -f index.html ]; then
  MD5_LOCAL=$(md5sum index.html | awk '{print $1}')
  MD5_CONT=$(docker exec "$CID" md5sum /usr/share/nginx/html/index.html 2>/dev/null | awk '{print $1}')
  echo "  md5 local (projeto):   ${MD5_LOCAL:-?}"
  echo "  md5 no contêiner:      ${MD5_CONT:-não encontrado}"
  if [ "$MD5_LOCAL" = "$MD5_CONT" ]; then
    echo "  -> iguais: a imagem foi construída com ESTE index.html."
  else
    echo "  -> DIFERENTES: a imagem está velha/errada. Rode: sudo ./deploy-vps.sh (ele refaz o build)."
  fi
else
  echo "  (sem contêiner ou fora da pasta do projeto)"
fi

secao "7. O que está sendo entregue na raiz"
BODY=$(curl -s --max-time 5 "http://127.0.0.1:${PORTA}/" 2>/dev/null)
if [ -z "$BODY" ]; then
  echo "  corpo vazio (servidor não respondeu)"
else
  TITULO=$(printf '%s' "$BODY" | grep -o '<title>[^<]*</title>' | head -1)
  echo "  título: ${TITULO:-<sem title>}"
  case "$BODY" in
    *"Welcome to nginx"*)       echo "  -> É a PÁGINA PADRÃO do nginx: o nginx.conf do projeto NÃO foi aplicado (build/porta apontando para outro serviço)." ;;
    *"index.html foi desativado"*|*"Este endereço foi desativado"*) echo "  -> Página de aviso correta." ;;
    *"<html"*)                  echo "  -> HTML recebido." ;;
    *)                          echo "  -> Conteúdo inesperado (veja as primeiras linhas acima)." ;;
  esac
fi

secao "8. Logs do contêiner (últimas 30 linhas)"
if [ -n "${CID:-}" ]; then
  docker logs --tail=30 "$CID" 2>&1 || true
else
  echo "  (sem contêiner)"
fi

secao "9. Firewall do host"
command -v ufw >/dev/null 2>&1 && { sub "ufw"; ufw status 2>&1 | head -20; }
command -v firewall-cmd >/dev/null 2>&1 && { sub "firewalld"; firewall-cmd --list-all 2>&1 | head -20; }
sub "regras do Docker (DOCKER-USER)"
iptables -S DOCKER-USER 2>/dev/null | head -10 || echo "  (iptables indisponível/sem permissão)"

secao "10. Veredito"
COD_RAIZ=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:${PORTA}/" 2>/dev/null)
TIPO_RAIZ=$(curl -s -o /dev/null -w '%{content_type}' --max-time 5 "http://127.0.0.1:${PORTA}/" 2>/dev/null)
echo "  GET /  -> HTTP ${COD_RAIZ:-sem resposta} | Content-Type: ${TIPO_RAIZ:-?}"

if [ "${COD_RAIZ:-000}" = "200" ] && printf '%s' "$BODY" | grep -q '<title>'; then
  echo
  echo "  A página funciona em 127.0.0.1:${PORTA} (dentro da VPS)."
  echo "  Então o problema é no ACESSO EXTERNO. Verifique, nesta ordem:"
  echo "   1) você está usando o IP público correto?  curl -s https://ifconfig.me"
  echo "   2) firewall do host liberado?              sudo ufw allow ${PORTA}/tcp"
  echo "   3) Security Group/firewall do provedor (AWS/Lightsail/Azure/Oracle) libera ${PORTA}?"
  echo "   4) se usa Dokploy, a aplicação tem a porta publicada 5005 -> 80?"
  echo "   5) testando de dentro da rede? use o IP da interface: $(hostname -I 2>/dev/null | awk '{print $1}')"
else
  echo
  echo "  A página NÃO está sendo servida corretamente na ${PORTA}. Faça, na ordem:"
  echo "   1) sudo ./deploy-vps.sh        (refaz build e sobe de novo)"
  echo "   2) ss -ltnp | grep ${PORTA}    (ver se algo está ouvindo)"
  echo "   3) docker ps -a                (ver se o contêiner está Up, não Restarting)"
  echo "   4) docker logs ${NOME}         (erros do nginx)"
fi

echo
echo "Relatório salvo em: $(pwd)/${ARQ}"

