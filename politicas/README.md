# Música automática (sem interação) — política de autoplay

O `index.html` pede a música **com som** já no carregamento e insiste de segundo
em segundo. Mesmo assim, Chrome/Edge/Firefox **só liberam áudio com som
automaticamente quando o site tem permissão de autoplay** — é uma proteção do
navegador, não uma limitação da página. Para o aviso tocar sozinho em todos os
computadores, libere o autoplay na máquina (uma vez, como Administrador).

Enquanto a política não estiver aplicada, a página não fica muda: a faixa segue
rodando em mudo (sem perder o lugar), a dica aparece e o som entra no primeiro
toque/clique — e a página continua tentando o som sozinha.

## Opção A — Registro do Windows (recomendada: vale para a máquina toda)

1. Copie esta pasta para o computador.
2. Clique com o botão direito em `liberar-autoplay-chrome.reg` (ou
   `liberar-autoplay-edge.reg`) → **Executar como administrador** → confirmar.
3. Feche e reabra o navegador.
4. Confirme em `chrome://policy` (ou `edge://policy`): `AutoplayAllowed` = `true`
   e `AutoplayAllowlist` com `http://10.105.35.172:5005`.
5. Abra `http://10.105.35.172:5005/login`: a música começa **com som** e o
   painel "Música de fundo" mostra "Tocando em loop".

O que os arquivos fazem:

| Política | Valor | Efeito |
|---|---|---|
| `AutoplayAllowed` | `1` | permite a mídia tocar sozinha, com som |
| `AutoplayAllowlist` | `http://10.105.35.172:5005`, `http://10.105.35.172:*` | restringe a liberação ao aviso |

> Mudou o IP/endereço do aviso? Edite as chaves `AutoplayAllowlist` (ou o `.reg`)
> com o novo endereço.

## Opção B — Domínio (GPO / Intune / Active Directory)

As mesmas políticas, pelo modelo administrativo oficial:

- Chrome: `Computer Configuration → Administrative Templates → Google Chrome →
  Media → Allow autoplay of media` + `Allow autoplay of media for these URLs`.
- Edge: `... → Microsoft Edge → Media → Allow autoplay of media` + allowlist.

Depois da GPO: `gpupdate /force` e reabrir o navegador.

## Opção C — Sem administrador, só no usuário (1 minuto)

- Chrome: `chrome://settings/content/sound` → **Adicionar** →
  `http://10.105.35.172:5005` em **Permitido**.
- Edge: `edge://settings/content/mediaAutoplay` → **Permitir** para o endereço.

## Opção D — Modo quiosque / TV de avisos

Atalho do navegador com a flag (só em máquina controlada — a flag vale para
qualquer site):

```
chrome.exe --autoplay-policy=no-user-gesture-required --kiosk http://10.105.35.172:5005/login
```

## Por que isso é necessário?

Navegadores modernos exigem "ativação do usuário" para tocar som. Depois que o
site toca uma vez com sucesso, o navegador costuma liberar as visitas seguintes
(MEI no Chrome), então a tendência é o aviso já abrir com som nas máquinas que
já foram liberadas — a política serve para garantir isso desde a primeira vez,
para todos os usuários.

## Checklist rápido

- [ ] `.reg` aplicado como Administrador
- [ ] navegador fechado e reaberto
- [ ] `chrome://policy` mostra `AutoplayAllowed = true`
- [ ] `http://10.105.35.172:5005/login` toca a música sem tocar em nada
- [ ] a contagem regressiva continua correndo até o redirecionamento
