# Página estática de aviso — Sistema de Ponto Praticus
# Build: docker build -t aviso-ponto .
# Run:   docker run -d -p 5005:80 --restart unless-stopped aviso-ponto
FROM nginx:1.27-alpine

# Configuração do servidor: qualquer rota (inclusive /login) exibe o aviso
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Página de aviso
COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1/ >/dev/null || exit 1
