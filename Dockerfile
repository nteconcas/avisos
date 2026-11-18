# Página de aviso — Sistema de Ponto Praticus
# App Python mínimo (apenas stdlib) que entrega o aviso em QUALQUER rota,
# na porta 5005. Não usa nginx nem dependências externas.
#
# Build: docker build -t aviso-ponto .
# Run:   docker run -d --name aviso-ponto -p 5005:5005 --restart unless-stopped aviso-ponto
FROM python:3.12-slim

# Logs sem buffer, sem .pyc (roda como usuário sem escrita em /app)
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    HOST=0.0.0.0 \
    PORT=5005

WORKDIR /app

# Só o necessário: o servidor, a página e a música
COPY app.py index.html audio.mp3 ./

# Usuário sem privilégios (UID numérico: não precisa existir em /etc/passwd)
USER 10001:10001

EXPOSE 5005

# /healthz responde 200 quando o app está de pé (Docker/Dokploy usam isso)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:5005/healthz', timeout=2).getcode()==200 else 1)"

CMD ["python3", "app.py"]

