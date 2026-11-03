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
| Repouso | O relógio, numa cápsula de verdade de 108 × 38. Se algo estiver ligado (gravação, Não perturbe, manter acordado, lembrete…), uma marca fica junto da hora. Com música tocando e nada mais ligado, a marca são três barrinhas na cor de destaque. |
| Hover | Nível 1: o relógio fixo no centro, os workspaces como pequenas cápsulas numeradas de um lado (a ativa preenchida com a cor de destaque), barras de rede e bateria do outro. Com música tocando, o elemento "tocando agora" (a capa, ou uma nota, e o título curto) fica antes dos workspaces. |
| Hover parado | Nível 2, depois de descansar o ponteiro por uns 1,6 s: a pílula alarga em três colunas, no máximo 640 × 64. À esquerda, o app em foco sobre os workspaces. No centro, um relógio grande sobre a data. À direita, o estado das notificações sobre rede e bateria. Com uma faixa carregada (tocando ou pausada), a linha do app em foco vira "título — artista" com um botão pequeno de tocar/pausar. |
| Painel | O mesmo objeto vira um painel. Não há linha de cabeçalho em cima dele. |

São dois níveis de hover. O ponteiro na faixa central de cima (600 px) ou na própria pílula abre o nível 1, a linha. Descansando ali por uns 1,6 s, vem o nível 2, então passar pela borda de cima não desdobra a pílula. Ao sair, volta o relógio. Nada troca sozinho. O clique no elemento "tocando agora", nos dois níveis, abre a Mídia. Sem player, nenhuma parte da música aparece.

| Lugar | Conteúdo | Toque |
|---|---|---|
| Esquerda | Workspaces deste monitor, cada um uma cápsula pequena com o seu número. A ativa é preenchida com a cor de destaque do tema. As ocupadas são claras. As vazias são quietas. | O clique numa cápsula foca esse workspace |
| Meio | Hora | Abre o Tempo |
| Direita | Barras de rede e bateria, a bateria preenchida na cor de destaque | Abre o Controle |

Apps, Controle, Captura, Estilo, Ferramentas e Energia não ficam desenhados na pílula. A paleta saiu da linha: o Estilo continua na tecla `4` e na roda. Cada painel abre nela, um de cada vez. Com algo ligado, o repouso mostra um único ponto.

## Painéis

Todos usam a mesma grade de 4 colunas e altura fixa por página, então a pílula não pula quando o conteúdo muda. A largura abraça o painel: 564 na maioria, 498 no Controle, 468 na Mídia. Com o mouse o painel mostra só os controles; as letras das teclas e a linha de rodapé (estado à esquerda, dicas à direita) só aparecem no modo teclado.

| Tecla | Painel | Conteúdo |
|---|---|---|
| 0 | Tempo | O mês. Page Up e Page Down trocam o mês. Home volta para hoje |
| 1 | Apps | Busca de aplicativos. Setas, Enter. Esc limpa e depois fecha |
| 2 | Controle | Três linhas de 56 px, cada uma com dois blocos em cápsula (círculo do ícone, nome, estado) e um bloco redondo (só o ícone; o nome aparece num balão com o hover, ou no rodapé no modo teclado). `Q` Wi-Fi, `W` Não perturbe, `E` microfone; `A` Bluetooth, `S` modo jogo, `D` luz noturna; `Z` manter acordado, `X` animações, `C` Velocidade (teste de velocidade). Sem Wi-Fi, a primeira vaga vira Protetor de tela; sem Bluetooth, Suspensão. Ligado acende só o círculo do ícone na cor de destaque; Wi-Fi ou Bluetooth ligados sem conexão mostram só um véu leve de destaque. Abaixo dos blocos, o cartão Som: uma barra de volume (`-`/`=` ±5 %, `M` ou o toque no ícone deixa mudo) cuja seta, ou Enter, abre a subpágina Som (saídas, entrada); um botão redondo Voltar ou Esc volta. Por último, a linha da rede: interface e tipo, endereço IPv4 e um botão QR do Wi-Fi (`V`) quando no Wi-Fi. A Velocidade e o QR fecham a ilha e abrem os painéis do próprio Omarchy |
| 3 | Captura | Print de região, tela, janela ou rolagem, e Inteligente no `V`. Gravação com som do sistema e microfone. OCR, QR code, conta-gotas |
| 4 | Estilo | Três páginas, com abas no alto: Tema, Fundo, e Janelas e fonte. `Tab` e `Shift+Tab` trocam de página; a largura fica e só a altura muda. **Tema**: um carrossel de amostras de 140 × 80, cada uma o fundo do próprio tema com a paleta em pontos e o nome na cor do texto dele; o cartão do cursor fica no centro, com contorno, e os vizinhos esmaecem rumo às bordas. Um pontinho de destaque marca o tema em uso. As setas escolhem; Enter, ou o clique no cartão do centro, aplica; o clique num vizinho só seleciona. Sob a faixa, o tema atual e `n/N`. O botão de grade no cabeçalho, ou `R`, abre Todos os temas (uma grade de 4 colunas). **Fundo**: um carrossel dos fundos desse tema, a escolhida em 160 × 90 no centro com contorno de destaque, as vizinhas menores e mais quietas; o fundo em uso guarda um pontinho de destaque. Embaixo, o nome do arquivo e `n/N`, e depois três botões compactos: Próximo fundo, Escolher fundo e Cores do fundo (`Q W E`). O cabeçalho mostra o tema a que os fundos pertencem. **Janelas e fonte**: Cantos (Do tema, Retos, Redondos), Transparência (Opaca, Translúcida, Vidro) e Fonte. Em Tema e Fundo, `/` começa uma busca que toma o lugar das abas; as letras de atalho e os dígitos seguem funcionando até você digitar. Esc limpa a busca, fecha Todos os temas, volta à página Tema e depois fecha |
| 5 | Ferramentas | Área de transferência, emojis, atalhos, menu do Omarchy, notificações, sobre, atualizações e Plugins. A busca de atualizações roda no máximo a cada 10 minutos e desiste depois de 30 segundos |
| 6 | Energia | Uma fileira de botões quadrados arredondados, ícone e nome: bloquear, suspender, hibernar. Sair, reiniciar e desligar pedem um segundo toque |
| — | Plugins | Busca os plugins do shell. Enter liga ou desliga. Trocar a barra pede um segundo toque. A roda chega nele depois da Energia |
| — | Mídia | Um mini-player compacto, 440 × 98 dentro de uma ilha de 468 × 126, para o player MPRIS ativo (o serviço de mídia do Omarchy, quando existe). Linha de cima: capa de 64 px, título sobre "artista · álbum", e anterior, tocar/pausar, próxima. Linha de baixo: tempo decorrido, barra de progresso, duração. Clique ou arraste na barra para pular, quando o player deixa. Aleatório e repetir (desligado, lista, faixa) ficam nas pontas da barra, só quando o player suporta. Fichas para trocar de player aparecem sob a linha do artista quando há mais de um. Teclas: Espaço ou `K` tocar/pausar, `←`/`J` anterior, `→`/`L` próxima, `,` e `.` voltam ou avançam 10 s, `S` aleatório, `R` repetir, `P` próximo player. Sem nada tocando, mostra o vazio na mesma altura |
| — | OSD | Volume, brilho e outros avisos enviados para a ilha |
| — | Notificação | O clique no sino da linha abre a mais recente dentro da pílula: ícone, aplicativo e resumo numa linha. Ela não aparece sozinha. O toque na pílula devolve o relógio. Os cartões do Omarchy ficam, porque são eles que trazem as ações |

Os atalhos de painel do Omarchy caem no estado certo: áudio, Bluetooth e rede abrem o Controle, o relógio abre o Tempo, energia abre a Energia, mídia abre a Mídia.

## Mouse e teclado

- Rolar o mouse na linha de status troca o painel. A primeira volta, com a linha ainda só linha, abre o Tempo. As seguintes andam Tempo, Apps, Controle, Captura, Estilo, Ferramentas, Energia, Plugins, e a Mídia quando há uma faixa. Para baixo avança. Para cima volta. O painel aberto não tem linha no topo, mas a roda na borda de cima dele continua trocando os painéis.
- Listas e controles deslizantes guardam a própria roda. O volume fica no Controle.
- `0`–`6` ou `Alt`+dígito escolhem os mesmos painéis. `Ctrl+Tab` e `Ctrl+Shift+Tab` andam na ordem, com a Mídia só quando há uma faixa.
- Setas movem o foco. Enter e Espaço ativam.
- As letras seguem a grade: `Q W E R`, `A S D F`, `Z X C V`. A letra aparece no controle só no modo teclado. A linha de rodapé com estado e dicas também só aparece no modo teclado; com o mouse o painel termina com o mesmo respiro de cima. O contorno de foco só aparece depois de navegar pelo teclado. As mesmas letras valem no QWERTY e no ABNT2.
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
- **Vidro.** A superfície da ilha é o fundo do tema levado quase ao preto (num tema claro, um degrau na direção da cor do texto), então a pílula mantém a forma sobre um terminal do mesmo tema. Num tema escuro a superfície é o fundo do tema a 28 % (o Tokyo Night dá `#07080b`); num tema claro é o fundo levado 6 % na direção da cor do texto. Opaca é sólida (alfa 1). Vidro pinta essa superfície a 0.94 na cápsula e 0.92 no painel, por cima do blur que o Omarchy já aplica ao namespace `omarchy-bar`. Translúcida fica em 0.84 e 0.82. Opaca e Vidro não têm fio de borda num tema escuro; a Translúcida, e todo tema claro, mantêm um fio de 1 px na cor do texto com alfa baixo, para a borda não sumir. Não há sombra. Botões, cartões, chips e o calendário usam o alfa do painel, então um controle escolhido não vira uma placa sólida. A exceção são as pequenas marcas de destaque (círculos de ícone ativos, preenchimento dos controles deslizantes, hoje, o workspace ativo, a bateria): elas ficam na cor de destaque sólida mesmo no vidro. A mesma escolha define a opacidade das janelas pelo próprio Omarchy; a Ilha não acrescenta regras de janela. `omarchy hyprland window transparency`.
- **Fonte.** A família escolhida entra na pílula na hora. O `omarchy font set` ainda reinicia o shell quando reescreve o fontconfig.
- **Movimento.** A pílula muda de forma em 200 ms fixos quando cresce e 160 ms quando encolhe, numa curva que desacelera, e o conteúdo troca com um fade cruzado. Passar de um painel para outro nunca fecha e reabre a pílula. Com `omarchy toggle animations` desligado, tudo aparece na hora.
- **Cor.** A pílula usa só `Commons.Color`. Não há paleta própria.

O modo jogo, no Controle, é outra ação. Ligar pode desligar animações, tirar os vãos e deixar as janelas opacas. Desligar devolve o que ele mudou.

## IPC

```bash
omarchy-shell ilha open <launcher|control|capture|style|tools|plugins|calendar|power|media|last>
omarchy-shell ilha toggle <view|last>
omarchy-shell ilha run <view> <tecla>   # exemplo: run calendar pgdn, run control q
omarchy-shell ilha close
omarchy-shell ilha osd '{"icon":"volume-high","value":"55","progressText":"55%","max":"100"}'
omarchy-shell ilha closeOsd
omarchy-shell ilha state
```

`open` e `toggle` abrem o painel e fecham se ele já estiver aberto. `open media` funciona mesmo sem nada tocando. `state` imprime JSON (`view`, `lastView`, `keyboard`, `osd`, `hidden`, `screen`).

## Idiomas

A Ilha traz um catálogo em `i18n/` para cada idioma que o Omarchy oferece. Ela segue Configuração → Idioma ao vivo, sem reiniciar o shell, inclusive números e relógio. O que faltar cai no inglês. Idiomas da direita para a esquerda (árabe, persa, hebraico, urdu) espelham a ilha inteira. O relógio, as barras da rede, a bateria e o progresso e os botões de transporte da Mídia ficam da esquerda para a direita de propósito.

## Dependências

O Omarchy, com o shell dele. Nenhum pacote extra. A Ilha não instala plugin de blur e não busca nada por conta própria. Os botões chamam os comandos do Omarchy que o nome diz (`omarchy theme`, `omarchy font`, `omarchy capture`, `omarchy hyprland corners`, `omarchy hyprland window transparency` e os serviços de painel correspondentes).

Uma barra substituta pode mostrar widgets instalados, mas um widget de terceiro que precise do serviço ao vivo de outro plugin pode ficar limitado aqui. Volte com `omarchy bar use omarchy.bar` quando esse widget precisar da barra padrão.

## Arquivos

| Arquivo | Papel |
|---|---|
| `manifest.json` | Id, versão e a entrada `bar` |
| `Island.qml` | Uma janela por monitor, a pílula, os painéis e o IPC |
| `Strip.qml` | A linha de status, níveis 1 e 2: workspaces, relógio, rede, bateria, estado das notificações, tocando agora |
| `Indicators.qml` | Marcas de status ao vivo |
| `ContinuousRect.qml` | Cápsula e cartão |
| `Metrics.qml` | Medidas da grade, raios, durações |
| `Tile.qml`, `TileArm.js`, `KeyBadge.qml` | Controle da grade e a letra |
| `GridRow.qml`, `PanelGrid.qml`, `LabeledRow.qml`, `InfoRow.qml`, `PanelFooter.qml` | Linhas, teclado, rodapé |
| `IconButton.qml`, `Icon.qml` | Botão e ícone Material Symbols |
| `Launcher.qml`, `ControlPanel.qml`, `CaptureMenu.qml`, `StyleMenu.qml`, `ToolsMenu.qml`, `PluginsMenu.qml`, `CalendarView.qml`, `PowerMenu.qml`, `MediaPanel.qml`, `OsdView.qml` | Painéis |
| `i18n/` | Um catálogo por idioma do Omarchy |
| `install.sh`, `uninstall.sh` | Atalhos opcionais. O Omarchy não os executa |

Um painel recebe `active`, as cores, `shell` e `metrics`, e informa o tamanho com `implicitWidth` e `implicitHeight`. Pode implementar `closeRequested()`, `navigate(target)`, `handleKey`, `handleEscape` e `focusFirst`.

## Quando algo falha

- A cópia nova não virou a barra. Rode `omarchy restart shell` e depois `omarchy plugin enable esegnorelli.ilha`.
- O shell registrou `bar option esegnorelli.ilha failed to load, falling back to omarchy.bar`. Rode `omarchy plugin validate ~/.config/omarchy/plugins/esegnorelli.ilha` e leia `journalctl --user -t omarchy-shell`.
- A cor da pílula espera o papel de parede. Não deve. O Estilo lê o `colors.toml` antes do `omarchy theme set`. Papel de parede e terminais ainda seguem o comando.
- O `omarchy plugin update` recusa o pull. A cópia tem edições locais. Faça commit ou stash em `~/.config/omarchy/plugins/esegnorelli.ilha`.

## Licença

[MIT](LICENSE). Copyright 2026 Evandro Segnorelli.
