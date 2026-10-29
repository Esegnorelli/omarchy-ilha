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
| Esquerda | Workspaces do monitor e indicadores ativos | O que está acontecendo agora |
| Centro | Hora e data; tocar abre o calendário | O tempo |
| Direita | Apps, Controle, Captura, Estilo, Ferramentas, Energia | O que dá para fazer |

Cada lado tem só a largura do próprio conteúdo.

## Estados

| Estado | Conteúdo |
|---|---|
| Apps | Busca de aplicativos (setas, Enter, Esc). |
| Controle | Microfone, Wi-Fi e Bluetooth (se existirem), Luz noturna, Não perturbe, Manter acordado, Animações, volume e atalhos para Captura, Estilo, Ferramentas e Energia. |
| Captura | Print de região, janela, tela inteira ou rolagem; gravação com áudio do sistema e microfone; OCR, QR code e conta-gotas. |
| Estilo | Temas com prévia, plano de fundo, fonte, cantos e transparência das janelas. |
| Ferramentas | Internet (conexão, IP, QR do Wi-Fi, teste de velocidade), área de transferência, emojis, atalhos, sobre, fuso horário, menu do Omarchy, atualizações e lembretes. |
| Calendário | Mês atual, com navegação. |
| Energia | Bloquear, suspender, hibernar, sair, reiniciar e desligar (os três últimos pedem um segundo toque). |
| OSD | Volume, brilho e outros avisos enviados para a ilha. |

## Ligação com o sistema

- **Atalhos de painel do Omarchy** abrem o estado certo: áudio e Bluetooth → Controle, rede → Ferramentas, relógio → Calendário, energia → Energia.
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
omarchy-shell ilha open <launcher|control|capture|style|tools|calendar|power>
omarchy-shell ilha close
omarchy-shell ilha osd '{"icon":"volume-high","value":"55","progressText":"55%","max":"100"}'
omarchy-shell ilha state
```

## Arquivos

| Arquivo | Papel |
|---|---|
| `manifest.json` | Plugin `kind: "bar"`. |
| `Island.qml` | Janelas por monitor, revelar/esconder, notch, hover, contrato com o shell e IPC. |
| `Indicators.qml` | Indicadores e leituras de status. |
| `NotchShape.qml`, `ContinuousRect.qml` | Formas com cantos contínuos. |
| `IconButton.qml` | Botão de ícone. |
| `Launcher.qml`, `ControlPanel.qml`, `CaptureMenu.qml`, `StyleMenu.qml`, `ToolsMenu.qml`, `CalendarView.qml`, `PowerMenu.qml`, `OsdView.qml` | Estados. |
| `i18n/` | Textos. |

Todo estado segue o mesmo contrato: `active` (verdadeiro enquanto está na tela), `closeRequested()`, `navigate(target)`, cores `fg`/`bg`/`accent`/`danger` e tamanho por `implicitWidth`/`implicitHeight`.
