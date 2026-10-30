# Ilha

> Ser prático sem perder a beleza — computadores podem ser divertidos.

Barra do Omarchy em forma de notch: fica escondida no topo da tela e aparece quando o mouse chega na borda de cima. Tudo do sistema fica num lugar só.

## Como funciona

- **Repouso:** nada no topo. Se algo estiver ligado (gravação, Não perturbe, Manter acordado, lembrete…), fica só uma marquinha colada na borda, na cor do aviso.
- **Mouse na borda de cima** (faixa central de 600 px): o notch desce colado à borda e se estica até mostrar tudo. Ao tirar o mouse, ele encolhe e some de novo.
- **Por cima de tudo:** fica na camada mais alta, inclusive sobre tela cheia, e não reserva espaço, então as janelas não se mexem.
- **Esc ou clique fora** fecham qualquer painel.

O notch mostra, da esquerda para a direita:

| Lado | Conteúdo | Por quê |
|---|---|---|
| Esquerda | Workspaces, app em foco e indicadores ativos | O que está acontecendo agora |
| Centro | Hora e data; tocar abre Tempo | O tempo |
| Direita | Apps, Controle, Captura, Estilo, Ferramentas, Energia | O que dá para fazer |

O notch tem sempre 568 px e três zonas fixas (216 | 104 | 216): o relógio fica no centro exato da tela e os seis ícones nunca mudam de lugar, com qualquer número de workspaces ou indicadores. O nome do app em foco ocupa o espaço que sobra, então não fica campo vazio. Indicadores que não cabem viram um `+N`.

## Estados

Todos os painéis usam a mesma grade de 4 colunas, com a mesma largura do notch e altura fixa por painel (nada pula quando um estado muda).

| Dígito | Estado | Conteúdo |
|---|---|---|
| 1 | Apps | Busca de aplicativos (setas, Enter; Esc limpa e depois fecha). |
| 2 | Controle | Microfone, Não perturbe, Luz noturna, Manter acordado, Animações, Modo jogo, Wi-Fi e Bluetooth (se existirem), volume e a rede atual com teste de velocidade. |
| 3 | Captura | Print de região, tela inteira, janela ou rolagem; gravação com som do sistema e microfone; OCR, QR code e conta-gotas. |
| 4 | Estilo | Temas com prévia, plano de fundo (próximo, escolher, cores do fundo, todos os temas), cantos, transparência e fonte. |
| 5 | Ferramentas | Área de transferência, emojis, atalhos, menu do Omarchy, notificações, sobre e atualizações. |
| 0 | Tempo | Calendário, lembretes rápidos (+5, +15, +30 min, +1 h), ver e limpar lembretes, fuso horário. |
| 6 | Energia | Bloquear, suspender, hibernar; sair, reiniciar e desligar pedem um segundo toque. |
| — | OSD | Volume, brilho e outros avisos enviados para a ilha. |

## Memória muscular

- **Mesmo lugar, sempre:** cada categoria tem posição e dígito fixos; o ícone ativo ganha uma pílula e um traço que desliza até ele.
- **Mouse:** clicar num ícone abre o painel; com um painel aberto, parar 150 ms sobre outro ícone troca de painel (só depois de o mouse se mexer: um cursor parado em cima não troca nada sozinho); clicar no ícone ativo volta para a faixa. Rolar sobre Controle muda o volume.
- **Teclado:** as teclas seguem a posição na grade — `Q W E R` na primeira linha, `A S D F` na segunda, `Z X C V` na terceira. A letra aparece no canto de cada botão.
  - `0`–`6` (ou `Alt`+dígito) trocam de categoria; `Ctrl+Tab` / `Ctrl+Shift+Tab` andam em ordem.
  - Setas movem o foco, `Enter`/`Espaço` ativam.
  - No Estilo, `[` `]` só escolhem a fonte; `Enter` ou o clique aplicam. Fontes de ícones ficam fora da lista.
  - Com o teclado em uso, os dígitos aparecem embaixo de cada ícone.
  - `Esc` desfaz em etapas: cancela uma confirmação, limpa a busca e então fecha.
- **Confirmações** (reiniciar, desligar, sair): o botão fica vermelho com "Confirmar?" por 4 s; um segundo toque rápido demais (menos de 350 ms) é ignorado.

## Ligação com o sistema

- **Atalhos de painel do Omarchy** abrem o estado certo: áudio, Bluetooth e rede → Controle, relógio → Tempo, energia → Energia.
- **Não perturbe, Manter acordado e Luz noturna** vêm dos serviços do próprio Omarchy.
- **Gravação, lembretes e atualizações** são relidos quando os comandos do Omarchy avisam a barra (`omarchy.indicators refresh`, `omarchy.system-update clear`). Começar a gravar faz a ilha aparecer sozinha por um instante.
- **Notificações:** a ilha mostra quantas há na tela e abre o histórico. Os cartões continuam sendo do Omarchy.
- **Barra escondida** (`omarchy toggle bar`): a ilha respeita.

## Aparência

- **Cores:** 100% do tema atual, via `Commons.Color`, inclusive o vermelho de confirmação. Trocar o tema recolore tudo na hora.
- **Forma:** notch com curvas côncavas onde encontra a tela e cantos contínuos, desenhado na GPU (`Shape.CurveRenderer`).
- **Movimento:** mola sem quique para o tamanho e fades curtos. Com `omarchy toggle animations` desligado, tudo aparece sem animar.
- **Idiomas:** `i18n/pt-BR.json` e `i18n/en.json`, seguindo o idioma do Omarchy.

## Instalar e desinstalar

```bash
~/.config/omarchy/plugins/esegnorelli.ilha/install.sh     # ativa como barra
~/.config/omarchy/plugins/esegnorelli.ilha/uninstall.sh   # volta para a barra padrão
```

Se o plugin não carregar, o Omarchy volta sozinho para a barra padrão.

## IPC

```bash
omarchy-shell ilha open <launcher|control|capture|style|tools|calendar|power|last>
omarchy-shell ilha toggle <view|last>
omarchy-shell ilha run <view> <tecla>      # ex.: run calendar pgdn, run control q
omarchy-shell ilha close
omarchy-shell ilha osd '{"icon":"volume-high","value":"55","progressText":"55%","max":"100"}'
omarchy-shell ilha state
```

Atalho sugerido (livre no Omarchy padrão), em `~/.config/hypr/bindings.lua`: `SUPER+Z` → `omarchy-shell ilha toggle last`.

## Arquivos

| Arquivo | Papel |
|---|---|
| `manifest.json` | Plugin `kind: "bar"`. |
| `Island.qml` | Janelas por monitor, revelar/esconder, notch, hover, contrato com o shell e IPC. |
| `Indicators.qml` | Indicadores e leituras de status. |
| `NotchShape.qml`, `ContinuousRect.qml` | Formas com cantos contínuos. |
| `Strip.qml` | Faixa do notch: zonas fixas, relógio, categorias, dicas e volume na roda. |
| `Metrics.qml` | Medidas da grade, opacidades e tempos. |
| `Tile.qml`, `TileArm.js`, `KeyBadge.qml` | Botão da grade (ação, liga/desliga, confirmar) e a letra do teclado. |
| `GridRow.qml`, `PanelGrid.qml`, `LabeledRow.qml`, `InfoRow.qml`, `PanelFooter.qml` | Linhas da grade, navegação por teclado e rodapé. |
| `IconButton.qml`, `Icon.qml` | Botão e ícone Material Symbols. |
| `Launcher.qml`, `ControlPanel.qml`, `CaptureMenu.qml`, `StyleMenu.qml`, `ToolsMenu.qml`, `CalendarView.qml`, `PowerMenu.qml`, `OsdView.qml` | Estados. |
| `i18n/` | Textos. |

Todo estado segue o mesmo contrato: `active` (verdadeiro enquanto está na tela), `closeRequested()`, `navigate(target)`, `handleKey`/`handleEscape`/`focusFirst`, `footerStatus`/`footerHints`, cores `fg`/`bg`/`accent`/`danger` e tamanho por `implicitWidth`/`implicitHeight`.
