#!/usr/bin/env python3
"""Confere, pela rede, se a página e a música estão sendo entregues certos.

Serve para testar a VPS SEM navegador (não precisa de Node, Chrome, docker):

    python3 verificar-musica.py                            # http://127.0.0.1:5005
    python3 verificar-musica.py http://10.105.35.172:5005  # de qualquer máquina
    python3 verificar-musica.py 10.105.35.172:5005         # http:// é implícito

O que ele prova:
  * /healthz, /login, / e rota desconhecida respondem 200 com o index.html;
  * o HTML entregue tem o <audio> com autoplay e a lógica de música/contagem;
  * /audio.mp3 vem com Content-Type de áudio, Accept-Ranges e tamanho real;
  * o servidor aceita pedidos parciais (Range 0-1023 e sufixo -2048), que é o
    que o navegador usa para tocar/loopar sem baixar tudo de novo;
  * o começo do arquivo é um MP3 de verdade (não uma página de erro).

O que ele NÃO prova: o som automático — isso é decisão do navegador do usuário
(política de autoplay). Veja politicas/README.md para liberar nas máquinas.

Código de saída: 0 = tudo certo, 1 = alguma verificação falhou.
"""

from __future__ import annotations

import re
import sys
import urllib.error
import urllib.request

TIMEOUT = 15
UA = "verificar-musica/1.0 (+aviso-ponto)"

# Marcas da lógica no index.html (garantem que a versão publicada é a nova).
MARCAS_HTML = (
    'id="bg-audio"',
    "autoplay",
    "audio.mp3",
    "tentarComSom",
    "falhouLiberacao",
    "visibilitychange",
    "window.location.href = DESTINO",
)

falhas = 0


def checar(nome: str, condicao: bool, detalhe: str = "") -> bool:
    """Imprime uma linha de resultado e conta as falhas."""
    global falhas
    if condicao:
        print(f"  ok    | {nome}")
    else:
        falhas += 1
        print(f"  FALHA | {nome}" + (f"  ({detalhe})" if detalhe else ""))
    return condicao


def pedir(url: str, cabecalhos: dict[str, str] | None = None):
    """GET simples -> (status, cabecalhos, corpo). Erro HTTP vira resposta."""
    pedido = urllib.request.Request(url, headers={"User-Agent": UA, **(cabecalhos or {})})
    try:
        with urllib.request.urlopen(pedido, timeout=TIMEOUT) as resposta:
            return resposta.getcode(), resposta.headers, resposta.read()
    except urllib.error.HTTPError as erro:
        return erro.code, erro.headers, erro.read()
    except Exception as erro:  # DNS, conexão recusada, timeout...
        return 0, {}, str(erro).encode()


def tamanho(cabecalhos) -> int:
    """Content-Length como int (0 quando ausente/ilegível)."""
    try:
        return int(cabecalhos.get("Content-Length", "0"))
    except (TypeError, ValueError):
        return 0


def eh_mp3(inicio: bytes) -> bool:
    """ID3 (tag) ou frame MPEG (0xFF 0xEx/0xFx) no começo do arquivo."""
    if inicio[:3] == b"ID3":
        return True
    return len(inicio) >= 2 and inicio[0] == 0xFF and (inicio[1] & 0xE0) == 0xE0


def main() -> int:
    base = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:5005").strip()
    if "://" not in base:
        base = "http://" + base
    base = base.rstrip("/")
    print(f"Verificando {base}\n")

    # ------------------------------------------------------------- servidor
    print("Servidor e rotas")
    status, _, _ = pedir(base + "/healthz")
    checar("/healthz responde 200", status == 200, f"HTTP {status}")

    paginas = {}
    for rota in ("/", "/index.html", "/login", "/qualquer-rota"):
        status, cab, corpo = pedir(base + rota)
        paginas[rota] = corpo
        tipo = cab.get("Content-Type", "") if cab else ""
        checar(f"{rota} responde 200", status == 200, f"HTTP {status}")
        checar(f"{rota} vem como HTML", tipo.startswith("text/html"), tipo or "sem Content-Type")

    # ------------------------------------------------------------- conteúdo
    print("\nConteúdo da página")
    html = paginas.get("/login", b"").decode("utf-8", "replace")
    checar("página tem o player de fundo", 'id="bg-audio"' in html)
    checar("player aponta para audio.mp3", 'src="audio.mp3"' in html)
    checar("player com autoplay", re.search(r'id="bg-audio"[^>]*autoplay', html) is not None)
    checar("player em loop", re.search(r'id="bg-audio"[^>]*loop', html) is not None)
    for marca in MARCAS_HTML:
        checar(f"lógica presente: {marca}", marca in html)
    checar("contagem aponta para o destino", "ponto.praticus.com.br" in html)
    checar(
        "/login entrega o MESMO html de /",
        bool(paginas.get("/login")) and paginas.get("/login") == paginas.get("/"),
    )

    # ---------------------------------------------------------------- áudio
    print("\nÁudio (/audio.mp3)")
    status, cab, corpo = pedir(base + "/audio.mp3")
    tipo = cab.get("Content-Type", "") if cab else ""
    total = tamanho(cab)
    checar("/audio.mp3 responde 200", status == 200, f"HTTP {status}")
    checar("Content-Type de áudio", tipo.startswith("audio/"), tipo or "sem Content-Type")
    checar("aceita Range (necessário ao loop)", (cab.get("Accept-Ranges", "") if cab else "") == "bytes")
    checar("tamanho declarado > 100 kB", total > 100_000, f"{total} bytes")
    checar("tamanho baixado = declarado", len(corpo) == total, f"{len(corpo)} de {total}")
    checar("o arquivo é um MP3 de verdade", eh_mp3(corpo[:4]), "cabeçalho inesperado")

    status, cab, corpo = pedir(base + "/audio.mp3", {"Range": "bytes=0-1023"})
    faixa = cab.get("Content-Range", "") if cab else ""
    checar("Range 0-1023 -> 206", status == 206, f"HTTP {status}")
    checar("Range 0-1023 -> 1024 bytes", len(corpo) == 1024, f"{len(corpo)} bytes")
    checar(
        "Content-Range coerente",
        faixa.startswith("bytes 0-1023/") and faixa.endswith(str(total)),
        faixa or "ausente",
    )

    status, cab, corpo = pedir(base + "/audio.mp3", {"Range": "bytes=-2048"})
    checar("Range sufixo (-2048) -> 206", status == 206, f"HTTP {status}")
    checar("Range sufixo -> 2048 bytes", len(corpo) == 2048, f"{len(corpo)} bytes")

    # --------------------------------------------------------------- resumo
    print()
    if falhas:
        print(f"FALHAS: {falhas} -> corrija antes de publicar.")
        return 1
    print("TUDO OK: a página e a música estão sendo entregues corretamente.")
    print("Falta só o som automático, que depende do navegador do usuário:")
    print("  aplique as políticas de politicas/README.md nas máquinas.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
