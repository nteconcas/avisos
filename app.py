#!/usr/bin/env python3
"""Servidor mínimo da página de aviso — Sistema de Ponto Praticus.

Única função: entregar a página de aviso (index.html) em QUALQUER rota,
inclusive /login, que é o endereço salvo nos favoritos dos usuários.

Sem dependências externas: usa apenas a biblioteca padrão (Python 3.8+).

Uso:
    python3 app.py                  # 0.0.0.0:5005
    PORT=8080 python3 app.py        # outra porta
    HOST=127.0.0.1 python3 app.py   # só local
"""

from __future__ import annotations

import mimetypes
import os
import re
import signal
import sys
import threading
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit

BASE_DIR = Path(__file__).resolve().parent
INDEX = BASE_DIR / "index.html"

# Whitelist: só estes arquivos podem ser baixados. Qualquer outra rota
# (inclusive /app.py ou tentativa de ../etc/passwd) cai no aviso.
ARQUIVOS = {
    "/": INDEX,
    "/index.html": INDEX,
}

HOST = os.environ.get("HOST", "0.0.0.0")
PORT = int(os.environ.get("PORT", "5005"))
CACHE = "no-cache, no-store, must-revalidate"
BLOCO = 64 * 1024


class AvisoHandler(BaseHTTPRequestHandler):
    """Responde GET/HEAD: página de aviso e healthcheck."""

    server_version = "AvisoPonto/2.1"
    protocol_version = "HTTP/1.1"  # keep-alive

    # ------------------------------------------------------------------ rotas
    def do_GET(self) -> None:  # noqa: N802 (nome exigido pela stdlib)
        self._responder(head=False)

    def do_HEAD(self) -> None:  # noqa: N802
        self._responder(head=True)

    def _responder(self, head: bool) -> None:
        try:
            caminho = unquote(urlsplit(self.path).path)

            if caminho == "/healthz":
                self._texto(HTTPStatus.OK, "ok\n", head=head)
                return

            if caminho == "/favicon.ico":
                # O favicon já vai embutido no HTML (data URI).
                self.send_response(HTTPStatus.NO_CONTENT)
                self.send_header("Content-Length", "0")
                self.send_header("Cache-Control", CACHE)
                self.end_headers()
                return

            arquivo = ARQUIVOS.get(caminho, INDEX)  # rota desconhecida -> aviso
            self._servir(arquivo, head=head)
        except (BrokenPipeError, ConnectionResetError):
            self.close_connection = True  # navegador cancelou a requisição
        except Exception as exc:  # nunca derrubar o servidor por 1 requisição
            self.log_error("erro inesperado em %s: %s", self.path, exc)
            self.close_connection = True

    # -------------------------------------------------------------- respostas
    def _texto(self, status: HTTPStatus, corpo: str, head: bool = False) -> None:
        dados = corpo.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(dados)))
        self.send_header("Cache-Control", CACHE)
        self.end_headers()
        if not head:
            self.wfile.write(dados)

    def _servir(self, arquivo: Path, head: bool = False) -> None:
        if not arquivo.is_file():
            self.send_error(
                HTTPStatus.INTERNAL_SERVER_ERROR,
                f"{arquivo.name} não encontrado no diretório do app",
            )
            return

        tamanho = arquivo.stat().st_size
        tipo = mimetypes.guess_type(arquivo.name)[0] or "application/octet-stream"
        if tipo.startswith("text/"):
            tipo += "; charset=utf-8"

        faixa = self._faixa(tamanho)
        if faixa == "invalida":
            self.send_response(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
            self.send_header("Content-Range", f"bytes */{tamanho}")
            self.send_header("Content-Length", "0")
            self.send_header("Cache-Control", CACHE)
            self.end_headers()
            return

        inicio, fim = (0, tamanho - 1) if faixa is None else faixa
        trecho = max(fim - inicio + 1, 0)

        self.send_response(
            HTTPStatus.PARTIAL_CONTENT if faixa else HTTPStatus.OK
        )
        self.send_header("Content-Type", tipo)
        self.send_header("Content-Length", str(trecho))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Cache-Control", CACHE)
        if faixa:
            self.send_header("Content-Range", f"bytes {inicio}-{fim}/{tamanho}")
        self.end_headers()

        if head:
            return

        with arquivo.open("rb") as fh:
            fh.seek(inicio)
            restante = trecho
            while restante > 0:
                bloco = fh.read(min(BLOCO, restante))
                if not bloco:
                    break
                self.wfile.write(bloco)
                restante -= len(bloco)

    def _faixa(self, tamanho: int):
        """Interpreta 'Range': devolve (inicio, fim), None (sem range) ou 'invalida'."""
        cabecalho = self.headers.get("Range")
        if not cabecalho:
            return None
        casamento = re.fullmatch(r"bytes=(\d*)-(\d*)", cabecalho.strip())
        if not casamento:
            return "invalida"
        bruto_ini, bruto_fim = casamento.group(1), casamento.group(2)
        if bruto_ini == "" and bruto_fim == "":
            return "invalida"
        if bruto_ini == "":
            ultimos = int(bruto_fim)
            if ultimos == 0 or tamanho == 0:
                return "invalida"
            return max(tamanho - ultimos, 0), tamanho - 1
        inicio = int(bruto_ini)
        fim = int(bruto_fim) if bruto_fim else tamanho - 1
        if inicio >= tamanho or fim < inicio:
            return "invalida"
        return inicio, min(fim, tamanho - 1)

    # ------------------------------------------------------------------- logs
    def log_message(self, formato: str, *args) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), formato % args))


class Servidor(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main() -> int:
    if not INDEX.is_file():
        print(f"ERRO: {INDEX} não encontrado.", file=sys.stderr)
        print("Rode o app dentro da pasta do projeto (com index.html).", file=sys.stderr)
        return 1

    try:
        servidor = Servidor((HOST, PORT), AvisoHandler)
    except OSError as exc:
        print(f"ERRO: não consegui ouvir em {HOST}:{PORT} -> {exc}", file=sys.stderr)
        print(
            f"Dica: veja quem está usando a porta:  ss -ltnp | grep {PORT}",
            file=sys.stderr,
        )
        return 1

    def encerrar(_sinal, _frame):
        # shutdown() precisa rodar em outra thread (não na do serve_forever).
        threading.Thread(target=servidor.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, encerrar)
    signal.signal(signal.SIGINT, encerrar)

    print(f"Página de aviso no ar em http://{HOST}:{PORT}/  (Ctrl+C para parar)")
    print("  /login e qualquer outra rota -> index.html")
    print("  saúde: /healthz")
    try:
        servidor.serve_forever()
    finally:
        servidor.server_close()
    print("Servidor encerrado.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

