# Ilha

Barra flutuante para o [Omarchy](https://omarchy.org). Em repouso é o relógio. Com o ponteiro, vira uma linha só de status. Os painéis abrem um de cada vez, na mesma pílula.

English documentation: [README.md](README.md).

A Ilha substitui a barra (`kinds: ["bar"]`, id `esegnorelli.ilha`). Não é um widget dentro da barra padrão. Cores, cantos, vidro e fonte seguem o tema do Omarchy, e um clique no Estilo pinta a pílula antes de o resto da área de trabalho terminar a troca.

## Instalar

```bash
omarchy plugin add https://github.com/Esegnorelli/omarchy-ilha.git --enable
```

`--enable` troca a barra para a Ilha. O Omarchy pede confirmação, porque um plugin roda dentro do shell que fica aberto. Não há pacote extra, nem sudo, nem passo de instalação: tudo o que a Ilha usa vem com o Omarchy. O `omarchy plugin add` só clona o repositório e valida o `manifest.json`, e a Ilha não precisa de mais nada. Ela não grava nada fora da própria pasta.

Se a barra estiver escondida, mostre de novo com `omarchy toggle bar`.

## Atualizar

```bash
omarchy plugin update esegnorelli.ilha
```

Sem id, `omarchy plugin update` atualiza todo plugin instalado por git. Ele mostra o diff e não avança por cima de edições locais.

O Omarchy guarda a Ilha antiga no cache de QML, então depois de atualizar ou reinstalar rode `omarchy restart shell` para ver a versão nova.

## Remover

Voltar para a barra padrão e manter a Ilha instalada:

```bash
omarchy bar use omarchy.bar
```

O `uninstall.sh` faz a mesma coisa.

Apagar a cópia instalada (o repositório no GitHub continua):

```bash
omarchy plugin remove esegnorelli.ilha
```

Se a Ilha não carregar, o Omarchy volta sozinho para `omarchy.bar`.

## O que aparece

A pílula flutua a 12 px da borda de cima, na camada de overlay, e não reserva espaço. As janelas não se mexem quando ela cresce. Ela fica por cima de tela cheia. O tamanho que ela publica para o shell (`barSize`) é 50.

| Estado | O que está na pílula |
|---|---|
| Repouso | O relógio, numa cápsula de verdade de 108 × 38. Se algo estiver ligado (gravação, Não perturbe, manter acordado, lembrete…), uma marca fica junto da hora. |
| Hover | Nível 1: o relógio fixo no centro, os pontos dos workspaces de um lado (o ativo é uma pílula na cor de destaque), barras de rede e bateria do outro. |
| Hover parado | Nível 2, depois de uns 0,9 s de hover: a pílula alarga em três colunas. À esquerda, o app em foco sobre os pontos dos workspaces. No centro, um relógio grande sobre a data. À direita, o estado das notificações sobre rede e bateria. |
| Painel | O mesmo objeto vira um painel. Não há linha de cabeçalho em cima dele. |

O ponteiro na faixa central de cima (600 px) ou na própria pílula abre a linha. Parado ali, vem o nível 2. Ao sair, volta o relógio. Nada troca sozinho.

| Lugar | Conteúdo | Toque |
|---|---|---|
| Esquerda | Pontos dos workspaces deste monitor. O ativo é uma pílula alongada na cor de destaque do tema. Os ocupados são claros. Os vazios são quietos. | O clique num ponto foca esse workspace |
| Meio | Hora | Abre o Tempo |
| Direita | Barras de rede e bateria, a bateria preenchida na cor de destaque | Abre o Controle |

Apps, Controle, Captura, Estilo, Ferramentas e Energia não ficam desenhados na pílula. A paleta saiu da linha: o Estilo continua na tecla `4` e na roda. Cada painel abre nela, um de cada vez. Com algo ligado, o repouso mostra um único ponto.

## Painéis

Todos usam a mesma grade de 4 colunas, a mesma largura e altura fixa, então a pílula não pula quando o conteúdo muda.

| Tecla | Painel | Conteúdo |
|---|---|---|
| 0 | Tempo | O mês. Page Up e Page Down trocam o mês. Home volta para hoje |
| 1 | Apps | Busca de aplicativos. Setas, Enter. Esc limpa e depois fecha |
| 2 | Controle | Blocos em cápsula (um círculo de ícone que se enche com a cor de destaque quando ligado) e blocos redondos: microfone, Não perturbe, luz noturna, manter acordado, animações, modo jogo, Wi-Fi e Bluetooth quando existem. Volume, a rede atual, teste de velocidade. A seta da linha de volume abre a subpágina Som (saídas, entrada); um botão redondo `<` ou Esc volta |
| 3 | Captura | Print de região, tela, janela ou rolagem, e Inteligente no `V`. Gravação com som do sistema e microfone. OCR, QR code, conta-gotas |
| 4 | Estilo | `/` começa uma busca, e as letras de atalho funcionam na hora. Os temas são uma faixa compacta: cinco cartões, cada um uma amostra lisa das cores do tema, o do meio com aro. As setas escolhem. Enter, ou o clique no cartão do meio, aplica. Os fundos são um carrossel desse tema: busca, cinco miniaturas, a escolhida sobe e as vizinhas ficam mais baixas e mais quietas. O nome fica na miniatura. O fundo em uso continua claro. Enter, ou o clique na miniatura levantada, aplica. Um clique na vizinha só seleciona. O seletor de fundos tem um cabeçalho e um rodapé com o nome e `n/N · ↵ aplicar`. Todos os temas esconde os outros controles. Esc limpa a busca e depois volta. Próximo fundo, escolher, cores do fundo, cantos, transparência, fonte |
| 5 | Ferramentas | Área de transferência, emojis, atalhos, menu do Omarchy, notificações, sobre, atualizações e Plugins. A busca de atualizações roda no máximo a cada 10 minutos e desiste depois de 30 segundos |
| 6 | Energia | Uma fileira de botões quadrados arredondados, ícone e nome: bloquear, suspender, hibernar. Sair, reiniciar e desligar pedem um segundo toque |
| — | Plugins | Busca os plugins do shell. Enter liga ou desliga. Trocar a barra pede um segundo toque. A roda chega nele depois da Energia |
| — | OSD | Volume, brilho e outros avisos enviados para a ilha |
| — | Notificação | O clique no sino da linha abre a mais recente dentro da pílula: ícone, aplicativo e resumo numa linha. Ela não aparece sozinha. O toque na pílula devolve o relógio. Os cartões do Omarchy ficam, porque são eles que trazem as ações |

Os atalhos de painel do Omarchy caem no estado certo: áudio, Bluetooth e rede abrem o Controle, o relógio abre o Tempo, energia abre a Energia.

## Mouse e teclado

- Rolar o mouse na linha de status troca o painel. A primeira volta, com a linha ainda só linha, abre o Tempo. As seguintes andam Tempo, Apps, Controle, Captura, Estilo, Ferramentas, Energia, Plugins. Para baixo avança. Para cima volta. O painel aberto não tem linha no topo, mas a roda na borda de cima dele continua trocando os painéis.
- Listas e controles deslizantes guardam a própria roda. O volume fica no Controle.
- `0`–`6` ou `Alt`+dígito escolhem os mesmos painéis. `Ctrl+Tab` e `Ctrl+Shift+Tab` andam na ordem.
- Setas movem o foco. Enter e Espaço ativam.
- As letras seguem a grade: `Q W E R`, `A S D F`, `Z X C V`. A letra aparece no controle só no modo teclado ou no hover. O contorno de foco só aparece depois de navegar pelo teclado. As mesmas letras valem no QWERTY e no ABNT2.
- No Estilo, `[` e `]` só destacam a fonte. Enter ou o clique aplicam. Fontes de ícones ficam fora da lista.
- Esc cancela uma confirmação, depois limpa a busca, depois fecha.
- Um clique fora fecha o painel.
- Confirmações (reiniciar, desligar, sair) deixam o controle vermelho com "Confirmar?" por 4 segundos. Um segundo toque antes de 350 ms é ignorado.

Atalho opcional, em `~/.config/hypr/bindings.lua`. `Super+Z` está livre nos atalhos padrão do Omarchy. `Super+Ctrl+Z` é o zoom, então esse fica quieto.

```lua
o.bind("SUPER + Z", "Ilha", "omarchy-shell ilha toggle last")
```

## Aparência

O Estilo chega na pílula no clique. O comando do sistema continua depois.

- **Tema.** A pílula lê o `colors.toml` daquele tema (a sua camada, depois o tema de fábrica) e recolore na hora. O `omarchy theme set` espera 280 ms, então uma sequência rápida de cliques não empilha trocas. Papel de parede, terminais e bordas seguem o comando. Se o tema do sistema não chegar, a pílula volta para o tema que está valendo.
- **Cantos.** Arredondado usa cápsulas e um canto de painel de 32, e arredonda as janelas junto. Reto deixa a casca, os controles internos e as janelas com quina viva, inclusive o terminal. Tema segue o arredondamento atual do Hyprland; um tema com arredondamento 0 cai no visual arredondado em vez de deixar a ilha reta. Um desktop sem vão não achata a escolha arredondada. `omarchy hyprland corners`.
- **Vidro.** Opaco é sólido. Vidro pinta o tema a 0.92 na cápsula e 0.90 no painel, por cima do blur que o Omarchy já aplica ao namespace `omarchy-bar`. Transparente fica em 0.82 e 0.80. Não há fio de borda, a não ser uma linha de 1 px no Transparente. Botões, cartões, chips e o calendário usam o alfa do painel, então um controle escolhido não vira uma placa sólida. A exceção são as pequenas marcas de destaque (círculos de ícone ativos, preenchimento dos controles deslizantes, hoje, o workspace ativo, a bateria): elas ficam na cor de destaque sólida mesmo no vidro. A mesma escolha define a opacidade das janelas pelo próprio Omarchy; a Ilha não acrescenta regras de janela. `omarchy hyprland window transparency`.
- **Fonte.** A família escolhida entra na pílula na hora. O `omarchy font set` ainda reinicia o shell quando reescreve o fontconfig.
- **Movimento.** A pílula muda de forma em 200 ms fixos quando cresce e 160 ms quando encolhe, numa curva que desacelera, e o conteúdo troca com um fade cruzado. Passar de um painel para outro nunca fecha e reabre a pílula. Com `omarchy toggle animations` desligado, tudo aparece na hora.
- **Cor.** A pílula usa só `Commons.Color`. Não há paleta própria.

O modo jogo, no Controle, é outra ação. Ligar pode desligar animações, tirar os vãos e deixar as janelas opacas. Desligar devolve o que ele mudou.

## IPC

```bash
omarchy-shell ilha open <launcher|control|capture|style|tools|plugins|calendar|power|last>
omarchy-shell ilha toggle <view|last>
omarchy-shell ilha run <view> <tecla>   # exemplo: run calendar pgdn, run control q
omarchy-shell ilha close
omarchy-shell ilha osd '{"icon":"volume-high","value":"55","progressText":"55%","max":"100"}'
omarchy-shell ilha closeOsd
omarchy-shell ilha state
```

`open` e `toggle` abrem o painel e fecham se ele já estiver aberto. `state` imprime JSON (`view`, `lastView`, `keyboard`, `osd`, `hidden`, `screen`).

## Idiomas

Os textos ficam em `i18n/en.json` e `i18n/pt-BR.json` e seguem Configuração → Idioma sem reiniciar o shell. O que faltar cai no inglês.

## Dependências

O Omarchy, com o shell dele. Nenhum pacote extra. A Ilha não instala plugin de blur e não busca nada por conta própria. Os botões chamam os comandos do Omarchy que o nome diz (`omarchy theme`, `omarchy font`, `omarchy capture`, `omarchy hyprland corners`, `omarchy hyprland window transparency` e os serviços de painel correspondentes).

Uma barra substituta pode mostrar widgets instalados, mas um widget de terceiro que precise do serviço ao vivo de outro plugin pode ficar limitado aqui. Volte com `omarchy bar use omarchy.bar` quando esse widget precisar da barra padrão.

## Arquivos

| Arquivo | Papel |
|---|---|
| `manifest.json` | Id, versão e a entrada `bar` |
| `Island.qml` | Uma janela por monitor, a pílula, os painéis e o IPC |
| `Strip.qml` | A linha de status, níveis 1 e 2: workspaces, relógio, rede, bateria, estado das notificações |
| `Indicators.qml` | Marcas de status ao vivo |
| `ContinuousRect.qml` | Cápsula e cartão |
| `Metrics.qml` | Medidas da grade, raios, durações |
| `Tile.qml`, `TileArm.js`, `KeyBadge.qml` | Controle da grade e a letra |
| `GridRow.qml`, `PanelGrid.qml`, `LabeledRow.qml`, `InfoRow.qml`, `PanelFooter.qml` | Linhas, teclado, rodapé |
| `IconButton.qml`, `Icon.qml` | Botão e ícone Material Symbols |
| `Launcher.qml`, `ControlPanel.qml`, `CaptureMenu.qml`, `StyleMenu.qml`, `ToolsMenu.qml`, `PluginsMenu.qml`, `CalendarView.qml`, `PowerMenu.qml`, `OsdView.qml` | Painéis |
| `i18n/` | Inglês e português do Brasil |
| `install.sh`, `uninstall.sh` | Atalhos opcionais. O Omarchy não os executa |

Um painel recebe `active`, as cores, `shell` e `metrics`, e informa o tamanho com `implicitWidth` e `implicitHeight`. Pode implementar `closeRequested()`, `navigate(target)`, `handleKey`, `handleEscape` e `focusFirst`.

## Quando algo falha

- A cópia nova não virou a barra. Rode `omarchy restart shell` e depois `omarchy plugin enable esegnorelli.ilha`.
- O shell registrou `bar option esegnorelli.ilha failed to load, falling back to omarchy.bar`. Rode `omarchy plugin validate ~/.config/omarchy/plugins/esegnorelli.ilha` e leia `journalctl --user -t omarchy-shell`.
- A cor da pílula espera o papel de parede. Não deve. O Estilo lê o `colors.toml` antes do `omarchy theme set`. Papel de parede e terminais ainda seguem o comando.
- O `omarchy plugin update` recusa o pull. A cópia tem edições locais. Faça commit ou stash em `~/.config/omarchy/plugins/esegnorelli.ilha`.

## Licença

[MIT](LICENSE). Copyright 2026 Evandro Segnorelli.
