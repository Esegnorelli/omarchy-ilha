# Ilha

Barra flutuante para o [Omarchy](https://omarchy.org). Em repouso é só a hora. Com o ponteiro, vira uma cápsula com os workspaces do monitor, o relógio e os ícones das telas da Ilha; um clique no relógio ou num vão sobe ao nível 2, que acrescenta os widgets da barra do Omarchy numa fileira embaixo. Cada tela abre dentro da mesma pílula.

English documentation: [README.md](README.md).

A Ilha substitui a barra (`kinds: ["bar"]`, id `esegnorelli.ilha`, versão 2.4.0). Não é um widget dentro da barra padrão. As cores seguem o tema do Omarchy, e o texto segue o idioma do Omarchy.

> Depois de atualizar, se a pílula disser "Reinicie o shell para concluir a atualização da Ilha", toque nela ou rode `omarchy restart shell`.

## Instalar

```bash
omarchy plugin add https://github.com/Esegnorelli/omarchy-ilha.git --enable
```

O `omarchy plugin add` clona o repositório e valida o `manifest.json`. O `--enable` então troca a barra para a Ilha. O Omarchy pede confirmação antes, porque um plugin roda como código sem isolamento dentro do shell que fica aberto (`--yes` pula as perguntas). Não há pacote extra, nem sudo, nem passo de instalação. A Ilha não roda script de instalação e não grava nada quando começa.

Fora da própria pasta, a Ilha só grava isto:

- As chaves de ajuste, no `~/.config/omarchy/shell.json` do próprio Omarchy, sob `bar.ilha`, pela API de plugins do host (`mutateShellConfig`). Só quando você vira uma chave ou roda `ilha setting` (veja Ajustes).
- O próprio estado, em `~/.local/state/esegnorelli.ilha/` (`$XDG_STATE_HOME`, quando definido): `state.json` (quando você tocou em Limpar nas notificações pela última vez, e a temperatura da luz noturna) e `game-mode.json` enquanto o Modo jogo está ligado.
- A resposta ao alternador de fundo do Omarchy, nos dois arquivos de resposta que esse script cria e espera (veja Teclas de tema e de papel de parede).
- O que um widget do Omarchy na cápsula do hover grava para si mesmo. A Ilha repassa as chamadas dele ao host (`updateEntryInline`, `mutateShellConfig`), como a barra padrão faz.

Se a barra estiver escondida, mostre de novo com `omarchy toggle bar`.

## Atualizar

```bash
omarchy plugin update esegnorelli.ilha
```

Sem id, `omarchy plugin update` atualiza todo plugin instalado por git. Ele mostra o diff e não avança por cima de edições locais. Depois, o Omarchy relê os plugins.

O Omarchy não limpa o cache de QML. A Ilha compara a versão do `manifest.json` com a versão do código que o shell carregou. Quando elas não batem, a pílula mostra "Reinicie o shell para concluir a atualização da Ilha" por 8 segundos, uma vez por sessão, uns 2 segundos depois de a Ilha carregar. Ela espera, por até cerca de um minuto, enquanto houver uma tela, um nível de hover ou outro OSD na pílula. O toque roda `omarchy-restart-shell`. `omarchy restart shell` faz o mesmo. Com a barra escondida, o aviso aparece no OSD do Omarchy.

Vindo da 1.x:

- O código da 2.0 fica em `ui/`, uma pasta que a 1.x nunca teve, e a barra agora começa por `ui/Ilha.qml`. Os arquivos QML da 1.x na raiz saíram. Como todos os arquivos são novos, o shell carrega a 2.0 na hora, sem reiniciar.
- `focusedOnly` e `livePeek` em `bar.ilha` mantêm os valores. O `level2Dwell` saiu. A Ilha ignora a chave antiga e a apaga na próxima vez que gravar um ajuste.
- Os painéis Tempo, Captura, Estilo, Ferramentas e Plugins saíram e, com o Estilo, os controles de cantos, transparência e fonte.

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

A pasta de estado da Ilha, `~/.local/state/esegnorelli.ilha/`, fica. Apague à mão se quiser.

Se a Ilha não carregar, o Omarchy volta sozinho para `omarchy.bar`.

## O que aparece

Uma ilha por monitor, centrada no alto. Ela flutua por cima das janelas: nada fica reservado no alto, então as janelas usam a tela inteira e a pílula fica por cima delas. Ligue `reserveTop` (veja Ajustes) para reservar 48 px, como uma barra comum, e as janelas começarem abaixo dela. Nos dois casos a pílula cresce por cima das janelas; elas não se mexem. As notificações e os popups do Omarchy continuam deixando 48 px livres no alto. A ilha fica na camada top. Uma tela aberta por cima de uma janela em tela cheia passa para a camada overlay, para aparecer por cima dela.

Com a barra escondida (`omarchy toggle bar`), a pílula (e os 48 px, com `reserveTop`) some. As telas abertas por tecla ou por IPC continuam aparecendo.

| Estado | O que está na pílula |
|---|---|
| Repouso | Só a hora, numa cápsula de 32 px de altura, a 10 px da borda de cima. Durante uma gravação, uma marca vermelha e o tempo gravado ficam ao lado. |
| Ícones | O ponteiro está na pílula. Uma cápsula de 42 px de altura, tão larga quanto o conteúdo: os workspaces, o relógio e as sete telas como ícones. |
| Nível 2 | Um toque na marca de gravação, um toque no aviso ao vivo de uma gravação, um lembrete ou uma atualização, um clique no relógio ou num vão dos ícones, ou `ilha hover 2`. A faixa de cima cabe no conteúdo (contexto, relógio e estado, e a fileira dos módulos quando há): o app em foco sobre os workspaces, um relógio grande com a data e a linha de estado. Com módulos do Omarchy, a pílula cresce 40 px e eles ficam numa fileira embaixo. |
| Aviso ao vivo | Algo acabou de ligar. Uma linha curta, de 40 px de altura. |
| OSD | `ilha osd`, a pergunta da resolução ou o aviso de reinício. 40 px de altura. |
| Tela | Uma das telas, na mesma forma. |

### Repouso

Só a hora: `HH:mm` nos algarismos do idioma. Fica em 12 horas (`h:mm`, sem AM/PM) quando a entrada `omarchy.clock` do layout da barra no `shell.json` tem um `format` com `AP`.

A única exceção é a gravação, por privacidade: uma marca vermelha e o tempo gravado (`0:42`) ficam ao lado do relógio (à esquerda; à direita nos idiomas da direita para a esquerda). Com o ponteiro em cima da marca, a pílula fica em repouso para o toque cair nela; o toque abre o nível 2 fixado na gravação, onde um clique para a gravação. Os outros estados (Não perturbe, luz noturna, manter acordado, lembretes, atualizações) aparecem como aviso ao vivo quando ligam, e no nível 2.

### Ícones

O ponteiro na pílula, no vão acima dela ou na faixa de cima transforma o relógio numa cápsula com três grupos, separados por fios finos:

- Os workspaces numerados do monitor: no mínimo cinco, até o maior que existe no bloco do monitor. O ativo fica preenchido na cor de destaque, um ocupado fica tingido, um vazio fica apagado e um urgente fica na cor de urgência. Um clique foca o workspace. O workspace sob o ponteiro clareia.
- O relógio no meio. Um clique nele, ou num vão, sobe ao nível 2. Os ícones das telas são os do menu do Omarchy, na fonte do shell, então uma atualização do menu não deixa a Ilha com glifo faltando.
- Os ícones das sete telas da Ilha, na ordem do Alt+1–7: Apps, Calendário, Temas (com os papéis de parede), Captura, Omarchy, Central de controle, Energia. Um toque num ícone abre a tela dele.

Um clique no relógio do repouso (uma tela de toque não tem hover), o botão direito ou um toque longo (0,5 s) também mostram os ícones. Abertos assim, eles fecham sozinhos 2,6 s depois se o ponteiro nunca chegar neles, ou 0,7 s depois que o ponteiro sai. Eles não abrem com uma tela aberta nem com a barra escondida.

### Nível 2

Um toque na marca de gravação, ou no aviso ao vivo de uma gravação, um lembrete ou uma atualização, abre o nível 2 com essa linha de estado fixada. Um clique no relógio ou num vão dos ícones também abre. O `ilha hover 2` segura o nível 2 no monitor focado até um `ilha hover 0`. Fora isso, ele fica enquanto o ponteiro estiver em cima, parado num módulo ou com um painel de módulo aberto, e fecha 2,5 s depois de o ponteiro sair. O Super+Ctrl+Alt+D não abre mais o nível 2: essa tecla abre o Calendário.

- Esquerda: o ícone e o nome do app da janela em foco, ou "Área de trabalho" quando o workspace não tem janela. Quando a janela em foco é o player de música, o título e o artista. Embaixo, os workspaces, maiores.
- Centro: o relógio, maior, e a data no formato do idioma.
- Direita: a linha de estado, sobre a rede e a bateria próprias. Essas duas somem quando o módulo `omarchy.network` ou `omarchy.power` correspondente está na fileira de baixo.
- Embaixo, quando há módulos do Omarchy: os widgets do `bar.layout`, na ordem da barra padrão (left, centerBegin, center, centerEnd, right), agrupados por seção com um filete. Os widgets do menu, dos workspaces e do relógio ficam de fora: a Ilha desenha esses sozinha. Um widget que se esconde sozinho não ocupa espaço. Os indicadores (Não perturbe, luz noturna, manter acordado e os outros) aparecem todos de uma vez, os ativos acesos e os outros esmaecidos, e um clique liga ou desliga cada um. Os glifos usam a tinta da ilha, para não sumirem num tema claro. Um clique abre o painel do widget logo abaixo do nível 2. O ponteiro no painel, ou parado no módulo, segura o nível 2.

Uma cápsula foca o workspace dela. A linha do app abre os Apps (a Mídia quando mostra o player). O relógio e a data abrem a Central de controle. A linha de estado executa a ação dela. O espaço vazio mostra os ícones.

A linha de estado mostra o primeiro que casar:

| Estado | Texto | Clique |
|---|---|---|
| Sessão remota | "Sessão remota", ou "Sessão remota · " e quem está conectado | Nada |
| Gravação | "Gravando 0:42" | Para a gravação |
| Sudo sem senha | "Sudo sem senha ativo" | Desliga |
| Notificações na tela | "3 notificações" | Central de controle |
| Lembrete | "Lembrete em 15 min" | Roda `omarchy-reminder show` |
| Atualização | "Atualização disponível" | Abre o `omarchy-update` num terminal flutuante |
| Manter acordado | "Mantendo acordado" | Desliga o manter acordado |
| Faixa carregada | "Título · Artista" | Mídia |
| Não perturbe | "Não perturbe" | Desliga |
| Nada | "Tudo em dia" | Central de controle |

### Borda de cima

Uma faixa invisível de 3 px nos 600 px centrais da borda de cima (menos em telas estreitas) mostra os ícones, nunca o nível 2. Em cima da marca de gravação, a pílula fica em repouso, então empurrar o ponteiro para o alto em cima da marca e clicar abre o nível 2.

### Aviso ao vivo

Quando algo liga, a pílula do monitor focado vira uma linha curta e depois volta ao relógio.

| Gatilho | Linha | Toque |
|---|---|---|
| Uma gravação começa | "Gravando 0:42" (segue contando) | Nível 2, fixado na gravação |
| Um lembrete é criado, e mais uma vez quando faltam 5 minutos | "Lembrete em 15 min", ou "Lembrete em 15 min · " e a mensagem dele | Nível 2, fixado no lembrete |
| Uma atualização fica disponível | "Atualização disponível" | Nível 2, fixado na atualização |
| O Não perturbe liga | "Não perturbe ligado" | Central de controle |
| A luz noturna liga | "Luz noturna ligada" | Central de controle |
| O manter acordado liga | "Manter acordado ligado" | Central de controle › Tela, com o cartão Manter acordado em destaque |
| Chega uma notificação urgente | O app e o resumo | Central de controle, com essa notificação em destaque |

- Fica 2,6 s (uma notificação urgente, 4 s) e termina antes se o estado desligar. O ponteiro em cima pausa a contagem; quando o ponteiro sai, fica mais 1 s. O botão direito dispensa.
- Só a mudança conta. Estados que já estavam ligados quando a Ilha começou, ou que mudam nos primeiros 4 segundos dela, não geram aviso. Sessão remota e sudo sem senha nunca geram aviso; eles aparecem no nível 2.
- Com o Não perturbe ligado, só aparecem os avisos de Não perturbe, de gravação e de urgência.
- Nenhum aviso aparece com uma tela ou o seletor aberto, nem com uma janela em tela cheia no monitor focado. Com a pílula focada mostrando os ícones, o nível 2 ou um OSD, o aviso espera até 5 s ela voltar ao repouso.
- Um aviso de prioridade igual ou maior troca o que está na tela (urgente, gravação, lembrete, atualização, Não perturbe, luz noturna, manter acordado). Um OSD no mesmo monitor encerra o aviso.
- Com o Aviso ao vivo desligado nos Ajustes da Ilha, nenhum aviso aparece.

As notificações comuns nunca aparecem na pílula. Os cartões do próprio Omarchy ficam, porque são eles que trazem as ações.

## Telas

Sete telas, numa ordem só: Apps, Calendário, Temas (com os papéis de parede), Captura, Omarchy, Central de controle, Energia. Os ícones, o Alt+1–7, o Ctrl+Tab, a roda e a cápsula de navegação usam essa ordem. A Mídia é uma tela fora dessa ordem (veja Mídia). Uma tela abre na pílula, no monitor focado para teclas e IPC, ou no monitor que você clicou. Telas abertas por tecla, por IPC ou por um takeover começam no modo teclado. Os anéis de foco só aparecem no modo teclado.

### Navegação

Embaixo de toda tela aberta fica uma cápsula pequena, presa à borda de baixo da tela: Voltar e as sete telas na ordem acima, com a aberta marcada na cor de destaque. Um clique num ícone troca para aquela tela. O Voltar vai, nesta ordem: para fora de uma página ou popover da Central de controle (na tela Omarchy: limpa a busca e depois sobe um nível), para a tela em que você estava antes ou, sem para onde voltar, fecha a ilha. Alt+← e o botão "voltar" do mouse fazem o mesmo. Fechar a ilha limpa o histórico. Nos idiomas da direita para a esquerda a cápsula espelha, e o Voltar fica à direita.

### Central de controle

514 × 588. Duas linhas de controles e depois quatro cartões.

| Lugar | Controle | Clique |
|---|---|---|
| Linha 1 | Bloco Wi-Fi (nome da rede, "Não conectado", "Desligado", "Indisponível" ou "Ethernet") | O bloco abre o popover de Wi-Fi. O círculo do ícone liga ou desliga o Wi-Fi |
| Linha 1 | Bloco Foco | Liga ou desliga o Não perturbe |
| Linha 1 | Bloquear (redondo) | Fecha a ilha e roda `omarchy system lock` |
| Linha 2 | Bloco Bluetooth ("Ligado", "Desligado", "2 conectados" ou "Nenhum adaptador Bluetooth") | O bloco abre o popover de Bluetooth. O círculo do ícone liga ou desliga o Bluetooth |
| Linha 2 | Bloco Modo jogo | Ligado, desliga as animações, tira os vãos e deixa as janelas opacas, guardando o que mudou. Desligado, devolve só o que ele mudou |
| Linha 2 | Luz noturna (redondo) | Liga ou desliga a luz noturna, na temperatura escolhida em Tela |
| Cartão | Som | Barra de volume: arraste ou clique. O toque no ícone deixa mudo. A seta abre a página Som |
| Cartão | Tela | Brilho do monitor focado ("Brilho indisponível" quando ele não tem controle). A seta abre a página Tela |
| Cartão | Tocando agora | A capa, o título e o artista (ou o nome do player), depois anterior, tocar/pausar e próxima. Sem player: "Nada tocando". Um toque na capa ou no texto abre a Mídia |
| Cartão | Notificações | Veja abaixo |

**Notificações.** As da tela primeiro, com um ponto na cor de destaque, depois as fechadas nas últimas 24 horas desde o último Limpar, da mais nova para a mais velha, no máximo 30. "Limpar" dispensa todas. O clique na mais nova da tela clica nela, como o cartão do Omarchy faria, e fecha a ilha. O hover numa notificação da tela mostra um botão para dispensá-la. Sem nenhuma: "Nenhuma notificação". O botão de ajustes no canto do cabeçalho abre Ajustes da Ilha. Apps, Temas, Papéis de parede e Energia não se repetem aqui: já estão nos ícones e na navegação.

**Popovers e páginas.** Cada um nasce do controle que o abriu e escurece a grade. O botão de voltar, o Esc ou um toque fora do cartão volta.

- Wi-Fi: uma chave para o rádio, a rede conectada com Desconectar e depois "Redes" com Conectar. Só procura redes enquanto está aberto. Cinco linhas aparecem; o resto rola. Uma rede protegida pede a senha na própria linha ("Senha incorreta" se falhar). Uma rede conhecida mostra um botão para esquecê-la. Uma rede corporativa (802.1X) abre o `nmtui` num terminal.
- Bluetooth: uma chave, os aparelhos "Salvos" com Conectar ou Desconectar e depois os aparelhos "Por perto" com Parear. Só procura aparelhos enquanto está aberto. Conectar um fone passa a saída de áudio para ele.
- Som: os aparelhos de "Saída" e o volume de saída, depois os de "Entrada" e o volume de entrada. Uma linha escolhe o aparelho padrão.
- Tela: um cartão por monitor, com brilho, escala (de 1.0× a 2.0×, as que cabem no monitor) e Resolução (até 6 modos). Uma resolução nova pergunta "Manter esta resolução? Revertendo em 10 s", com Manter e Reverter, e reverte sozinha. Se a Central fechar, a contagem passa para a pílula, e o toque mantém a resolução. Depois vêm a Luz noturna (uma chave e a temperatura, 2500–5800 K) e o Manter acordado ("A tela não escurece, bloqueia nem dorme").
- Ilha: as duas chaves. Veja Ajustes.

**Teclas.** As setas andam pela posição. Tab e Shift+Tab andam na ordem. Home vai ao Wi-Fi; End, às notificações. Enter executa a ação principal. Espaço aperta o círculo do ícone de um bloco, ou deixa mudo na barra de Som. Numa barra, Esquerda e Direita mudam 5 % (Shift: 1 %). M deixa mudo no cartão Som. No cartão Tocando agora, a capa e o texto, anterior, tocar/pausar e próxima são quatro paradas numa linha só. Numa notificação, Delete dispensa uma da tela, e Enter na mais nova da tela clica nela. Nos popovers e nas páginas, Cima e Baixo andam, Enter e Espaço escolhem ou alternam, Espaço liga e desliga o rádio no Wi-Fi e no Bluetooth, Delete esquece uma rede Wi-Fi conhecida, Esquerda e Direita mudam as barras em 5 % (Shift: 1 %), e M deixa muda a seção focada no Som. O Esc fecha o campo de senha ou uma lista aberta, depois o popover ou a página, depois a ilha.

### Apps

514 × 368. A busca de aplicativos: "Buscar…" no alto, seis linhas embaixo.

- Sem nada digitado, todos os apps visíveis, de A a Z. Ao digitar, a ordem segue a busca aproximada. Sem resultado: "Nenhum app encontrado".
- As entradas escondidas seguem as regras do próprio Omarchy.
- O destaque só segue o ponteiro quando o ponteiro anda. A roda rola a lista.
- Apps de terminal abrem pelo `omarchy-launch-tui`; o resto, pelo `uwsm-app -- gtk-launch`. Quando nenhuma janela aparece em 2 s, o OSD do Omarchy diz "Abrindo Firefox…" (com o nome do app) até ela aparecer, por no máximo 15 s.
- Teclas: Cima e Baixo, Tab e Shift+Tab (dão a volta), Page Up e Page Down de 6 em 6. Enter abre o app e fecha. Esc limpa e depois fecha.

### Calendário

514 × 420. O mês, as barras do ano e da vida, outros fusos e os lembretes. O Super+Ctrl+Alt+D (a tecla de calendário do Omarchy) e o `omarchy-shell omarchy.clock open` também abrem.

- Cabeçalho: o mês e o ano, depois "Voltar para hoje" (só com outro dia escolhido), mês anterior e próximo mês.
- Barras: quanto do ano já passou, e a vida. A vida usa `birthYear` e `lifeExpectancy` (90 por padrão) da entrada `omarchy.clock` do `bar.layout`. Sem um `birthYear` válido, a barra da vida some e a do ano ocupa a linha toda. As duas seguem o dia de hoje, não o mês à mostra.
- Grade: sempre seis semanas, com o número da semana ISO numa coluna ao lado. A semana começa no `weekStartDay` dessa entrada, ou no primeiro dia do idioma, ou na segunda-feira. Hoje é um círculo na cor de destaque; o dia escolhido tem um anel. Os dias de outros meses ficam apagados, e o fim de semana, mais fraco. Um ponto marca o dia com lembrete. Um clique escolhe um dia; um dia de outro mês leva até aquele mês. A roda em cima da grade troca o mês.
- Fusos: até quatro cidades da entrada `omarchy.elsewhen` do `bar.layout` (`cities`, ou o antigo `zones`), cada uma com a hora e "+1 dia" ou "-1 dia" quando ela já está em outra data. A cidade do fuso local fica de fora. Sem cidades, a linha some.
- Lembretes, do `omarchy-reminder show --json`: os do dia escolhido, com a data no título; sem nenhum nesse dia, "Próximos lembretes"; sem nenhum, "Nenhum lembrete pendente". Cada linha tem a hora, a mensagem e quanto falta. Quando há mais do que cabe, o título ganha a contagem. "Definir lembrete" fecha a ilha e roda `omarchy-reminder -i`.
- Teclas: as setas movem o dia (Esquerda e Direita seguem a direção da tela). Page Up e Page Down trocam o mês (Shift: o ano). Home volta para hoje; End vai ao último dia do mês. Tab e Shift+Tab passam pela grade, por "Voltar para hoje", pelos dois botões de mês e por "Definir lembrete". Enter e Espaço apertam o botão focado. Esc fecha.

### Temas e papéis de parede

Uma tela, duas fileiras, tão larga quanto couberem de 2 a 5 miniaturas de papel de parede na tela (32 + 196 px cada), 412 de altura. ↑ e ↓ trocam de fileira; o ponteiro em cima de uma fileira a deixa ativa. Só a fileira ativa mostra a borda na cor de destaque. `ilha open wallpapers` (e os apelidos `wallpaper` e `background`) abrem a mesma tela na fileira de baixo.

Fileira de cima, os temas:

- Um campo de busca ("Buscar temas…") e um contador (`3/18`). Sem resultado: "Nenhum tema encontrado". O campo fica com o teclado, então digitar sempre filtra os temas.
- Cada cartão mostra a imagem de prévia do próprio tema, as seis cores da paleta e o nome na cor de texto dele, sobre uma faixa no fundo do tema. Um tema sem prévia mostra o fundo com pontos maiores. O cartão do centro é o escolhido: ele sobe e, na fileira ativa, ganha uma borda na cor de destaque. Um pontinho marca o tema em uso.
- O Enter roda `omarchy-theme-set`. O pontinho muda na hora. A tela continua aberta e passa para a fileira de baixo, que então mostra os papéis de parede do tema novo. As cores da ilha trocam com um fade de 150 ms quando a paleta nova chega.
- Os temas vêm de `~/.config/omarchy/themes` e dos temas do próprio Omarchy. O seu vence quando o nome é o mesmo. A prévia é o `preview.png` do tema (ou `.jpg`, `.jpeg`, `.webp`), o mesmo arquivo que o seletor de temas do Omarchy usa.

Fileira de baixo, os papéis de parede do tema em uso:

- "Papel de parede" e o nome do tema no alto. A miniatura escolhida fica no centro. Um pontinho marca o papel em uso. Embaixo da faixa: o nome do arquivo, o contador e "Enter para aplicar".
- Os fundos do tema atual mais `~/.config/omarchy/backgrounds/<tema>`. O Enter roda `omarchy-theme-bg-set`; a tela continua aberta, para você experimentar outro. Sem nenhum: "Nenhum papel de parede para este tema".
- Aberta pelas teclas de fundo do Omarchy: veja Teclas de tema e de papel de parede. Esse pedido fecha a tela quando você escolhe.
- Papéis de parede em vídeo usam a miniatura guardada.

Mouse: o clique centraliza um cartão ou miniatura. O clique no do centro, ou um clique duplo, aplica. A roda anda um por volta. Teclas na fileira ativa: Esquerda e Direita (seguem a direção da tela), Tab e Shift+Tab, Page Up e Page Down, Home, End, Enter aplica. Esc limpa a busca e depois fecha.

### Captura

514 × 236. O menu Captura do Omarchy na pílula. No alto, cinco botões na ordem do menu do Omarchy: Captura de tela, Gravar tela, Texto, Código QR, Cor. Embaixo, as opções do botão escolhido. Toda ação fecha a ilha antes e roda 180 ms depois, para a ilha ficar fora da captura.

- Captura de tela: o botão roda `omarchy-capture-screenshot`. As opções são Região, Janela e Tela inteira (`omarchy-capture-screenshot region`, `windows`, `fullscreen`).
- Gravar tela: o botão não grava; ele desce para os modos. Sem áudio (`omarchy-capture-screenrecording`), Com áudio da área de trabalho (`--with-desktop-audio`), Com áudio da área de trabalho + microfone (`--with-desktop-audio --with-microphone-audio`) e Com áudio da área de trabalho + microfone + webcam (`omarchy-capture-screenrecording-with-webcam`, apagado quando o `omarchy-hw-webcam` não acha webcam).
- Durante uma gravação, o segundo botão vira "Parar gravação", com o tempo gravado. A tela abre nele, então o Enter para a gravação (`omarchy-capture-screenrecording --stop-recording`).
- Texto (`omarchy-capture-text`), Código QR (`omarchy-capture-qr`) e Cor (`hyprpicker -a`; um hyprpicker já aberto fecha) não têm modos. Embaixo deles: Compartilhar a área de transferência, um arquivo ou uma pasta (`omarchy-menu-share clipboard`, `file`, `folder`), e o Histórico da área de transferência (`omarchy-shell shell summon omarchy.clipboard`).
- Os rótulos vêm do catálogo do próprio menu do Omarchy, no idioma do Omarchy. Região, Janela e Tela inteira são da Ilha.
- Mouse: o hover escolhe, o clique executa. Teclas: Esquerda e Direita (seguem a direção da tela), Baixo entra nas opções, Cima volta, Tab e Shift+Tab dentro da fileira, Home, End, 1 a 5 executam um botão, Enter e Espaço executam. Esc fecha.

### Omarchy

514 × 460. O menu inteiro do Omarchy na pílula, um nível por vez.

- A tela lê os mesmos arquivos que o menu do Omarchy: `$OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc`, com a sua extensão `~/.config/omarchy/extensions/omarchy-menu.jsonc` por cima, campo a campo. Os rótulos usam as traduções do Omarchy (`default/i18n/<idioma>/menu.json`). Mudanças no disco aparecem com a tela aberta.
- `when`, `checked` e `disabled` rodam como comandos de shell, como no Omarchy. Um `when` falso esconde a linha. `checked` e `disabled` mostram um ✓; o `disabled` também apaga a linha, e a seleção pula por cima dela. Um › marca um submenu.
- Providers: fontes, perfis de energia, kernels e idiomas rodam os mesmos scripts do menu do Omarchy, e um ✓ marca o valor atual. Aplicativos abre a tela de Apps da Ilha. Um provider que a Ilha não conhece abre o menu do próprio Omarchy naquele ponto.
- Busca: o campo no alto procura em tudo abaixo do nível aberto (na raiz, o menu inteiro), primeiro os filhos diretos. Cada resultado mostra o caminho embaixo. Os apps também aparecem na busca e abrem direto. As linhas apagadas ficam de fora.
- Caminho: embaixo da busca, por exemplo "Omarchy › Acionar › Captura". Um clique num nível de cima vai até ele. Fora da raiz, o caminho começa com um botão Voltar.
- Uma ação fecha a ilha e roda o comando dela como o Omarchy rodaria, 180 ms depois.
- Teclas: Cima e Baixo, Tab e Shift+Tab (dão a volta), Page Up e Page Down de 6 em 6. Enter entra ou executa. Com a busca vazia, Direita entra ou executa, Esquerda e Backspace sobem um nível, e Home e End vão à primeira e à última linha. Esquerda e Direita seguem a direção da leitura. Esc limpa a busca e depois fecha. O mouse: o clique entra ou executa; a roda rola.

### Mídia

514 × 218. O player MPRIS ativo, pelo serviço de mídia do Omarchy.

- A capa, o título, o artista e o nome do player. Com mais de um player, o nome é um botão que troca de player.
- A barra de progresso, com o tempo decorrido e o que falta. Clique ou arraste nela quando o player deixa.
- Aleatório, anterior, tocar/pausar, próxima, repetir (desligado, lista, faixa). Aleatório e repetir funcionam quando o player suporta.
- Sem player: "Nada tocando" e "Toque algo em qualquer player", no mesmo tamanho.
- Teclas: Espaço ou Enter tocar/pausar, Esquerda e Direita voltam ou avançam 5 s, Shift+Esquerda e Shift+Direita anterior e próxima, S aleatório, R repetir, P próximo player.

Ela não está entre os ícones. Ela abre pelo cartão Tocando agora da Central de controle, pelas linhas do app e de estado do nível 2, por um OSD de mídia e pelo `ilha open media`.

## Mouse e teclado

- A roda só troca de tela com uma tela aberta, na faixa que cobre a largura da tela nos 24 px de cima do monitor: o vão acima da tela e o respiro de cima dela. Cada volta (120 unidades) anda uma tela, na ordem acima. Para baixo avança, para cima volta. Uma volta incompleta zera depois de 200 ms sem eventos da roda, ou quando o sentido vira, então um deslize lento do trackpad nunca troca de tela. Os idiomas da direita para a esquerda não invertem a roda. No repouso, com os ícones, no nível 2, num aviso ou num OSD, a roda não troca de tela. Listas, carrosséis e controles deslizantes guardam a própria roda.
- O ponteiro na pílula mostra os ícones. Um clique no relógio do repouso, o botão direito ou um toque longo (0,5 s) também mostram. Nos ícones, um clique no relógio ou num vão sobe ao nível 2; o botão direito fecha. Num aviso ao vivo, dispensa.
- Um clique fora de uma tela aberta fecha a tela.
- As teclas só valem com uma tela aberta. Os ícones, o nível 2 e os avisos nunca pegam o teclado.
- Ctrl+Tab e Ctrl+Shift+Tab andam pelas telas. Alt+1–7 abrem direto: Apps, Calendário, Temas (com os papéis de parede), Captura, Omarchy, Central de controle, Energia.
- Alt+← e o botão "voltar" do mouse voltam (veja Navegação).
- O Esc vai primeiro para a tela (limpa uma busca, fecha um popover ou uma página, cancela uma confirmação) e depois fecha a ilha.
- Qualquer tecla liga o modo teclado. Andar o ponteiro mais de 8 px desliga.

### Teclas do Omarchy

Uma tecla de painel abre o painel do próprio Omarchy para aquele widget, embaixo do nível 2, quando o widget está no `bar.layout`; o nível 2 abre no monitor focado e a fileira é a âncora. Sem o widget, a tecla abre a tela da Ilha. O `omarchy.clock` e o `omarchy.media` sempre abrem o Calendário e a Mídia da Ilha. A mesma tecla de novo fecha o que ela abriu.

| Tecla | Nome no Omarchy | Na Ilha |
|---|---|---|
| Super+Ctrl+A | Áudio | O painel de áudio do Omarchy, com o mixer. Sem o widget: Central de controle › Som |
| Super+Ctrl+B | Bluetooth | O painel de Bluetooth do Omarchy. Sem o widget: Central de controle › Bluetooth |
| Super+Ctrl+N | Rede | O painel de rede do Omarchy. Sem o widget: Central de controle › Wi-Fi |
| Super+Ctrl+D | Tela | O painel de tela do Omarchy. Sem o widget: Central de controle › Tela |
| Super+Ctrl+P | Energia | O painel de energia e bateria do Omarchy. Sem o widget: Energia |
| Super+Ctrl+Alt+D | Calendário | Calendário |
| Super+Ctrl+Alt+E | Relógio mundial | O painel Elsewhen do Omarchy. Sem o widget: Central de controle |
| Super+Ctrl+1 a 9 | Painel da barra 1–9 | Os mesmos painéis da barra padrão: os painéis visíveis da seção `right`, na ordem do `bar.layout`, sem a bandeja. Um número depois do último não faz nada |
| Super+Ctrl+T, Super+Shift+Ctrl+Space | Menu de temas | Temas |
| Super+Ctrl+W, Super+Ctrl+Space | Alternador de fundo | Papéis de parede |

### Teclas de tema e de papel de parede

A Ilha assume os dois seletores de imagem do Omarchy. Nenhuma tecla e nenhuma entrada de menu é trocada: as mesmas teclas e entradas abrem as telas da Ilha.

- **Papéis de parede.** Super+Ctrl+W, Super+Ctrl+Space e Menu › Aparência › Plano de fundo rodam o alternador de fundo do Omarchy, que pede um seletor ao alvo `image-selector` do shell. A Ilha atende esse alvo antes do seletor do Omarchy. Quando todas as imagens do pedido estão nos fundos do tema (`~/.local/state/omarchy/current/theme/backgrounds/`) ou em `~/.config/omarchy/backgrounds/`, a tela de Temas e papéis de parede abre na fileira dos papéis, com as imagens do pedido. O Enter grava a escolha no arquivo de resposta que o script espera, e o script do Omarchy aplica. Esc, um clique fora ou outra tela devolvem uma escolha vazia, então o script nunca fica esperando para sempre.
- **Temas.** Super+Ctrl+T, Super+Shift+Ctrl+Space e Menu › Aparência › Tema abrem o seletor de temas do Omarchy. Quando esse seletor abre sem um pedido que a Ilha repassou, a Ilha o esconde e abre a tela de Temas e papéis de parede na fileira dos temas. O seletor do Omarchy abre transparente, então some antes de mostrar um quadro.
- Qualquer outro pedido, como imagens de outra pasta, vai para o seletor do próprio Omarchy sem mudança.
- Os dois takeovers acabam quando você volta para a barra padrão.

### Atalhos opcionais

Ponha em `~/.config/hypr/bindings.lua`. Antes, confira o que já está ocupado com `omarchy menu keybindings --print`.

`Super+Z` está livre nos atalhos padrão do Omarchy. `Super+Ctrl+Z` é o zoom, então esse fica quieto.

```lua
o.bind("SUPER + Z", "Ilha", "omarchy-shell ilha toggle last")
```

Este troca a grade de Apps do próprio Omarchy (a da dock) pelos Apps da Ilha:

```lua
o.rebind("SUPER + ALT + SPACE", "Apps", "omarchy-shell ilha toggle launcher")
```

## OSD

O host não entrega o OSD dele para plugins de terceiros. As teclas do sistema (volume, brilho, mídia) continuam mostrando o OSD do próprio Omarchy.

A pílula mostra:

- `ilha osd '<json>'`, com os mesmos campos do `omarchy-shell osd show`: `icon`, `message`, `value`, `max`, `progressText` e `duration` em ms (padrão 1200; `0` ou `sticky` passam para o OSD do Omarchy, porque a pílula só guarda os próprios avisos fixos). Um valor sem mensagem desenha um ícone, uma barra e o valor. Uma mensagem desenha uma linha. Um ícone `media` ou `player` desenha a capa com o título e o artista.
- "Manter esta resolução? Revertendo em 10 s", enquanto a página Tela não está à vista. O toque mantém a resolução.
- O aviso de reinício (veja Atualizar).

Quando a pílula não pode desenhar (barra escondida, uma janela em tela cheia no monitor focado, ou uma tela que não seja a Central de controle aberta), o `ilha osd` vai para o OSD do Omarchy. Com a Central de controle aberta, um OSD de volume ou de brilho não é desenhado enquanto o controle deslizante dele está à vista; o resto vai para o OSD do Omarchy.

O OSD aparece no monitor focado. O toque num OSD de volume abre Central de controle › Som; num de brilho, Central de controle › Tela; num de mídia, a Mídia. Qualquer outro toque dispensa.

## Aparência

- **Cores.** A Ilha lê as cores de fundo, texto, destaque e urgência do tema do Omarchy. A ilha é sempre escura: a superfície é a mais escura entre fundo e texto, a 10 % sobre o preto. Cartões e linhas são degraus mais claros na cor do texto. A cor de destaque vai na direção da cor do texto até ser legível sobre a superfície (3:1 nos preenchimentos, 4,5:1 no texto), e a de urgência também. Uma troca de tema muda as cores com um fade de 150 ms. A Ilha não grava paleta nenhuma. Os glifos dos widgets na fileira do nível 2 usam a tinta da ilha; o texto dos painéis deles continua com as cores da barra do Omarchy.
- **Forma.** Uma cápsula com um fio de borda de 1 px e uma sombra suave. Com as chaves de vidro do Omarchy ligadas (`~/.local/state/omarchy/toggles/hypr/bar-glassy.lua` ou `window-glassy.lua`), a sombra fica mais leve. A ilha continua opaca.
- **Posição.** Sempre no alto. Os ajustes de posição e de fundo da barra do Omarchy não valem para a Ilha.
- **Fontes.** O texto usa o recorte da Inter que vem junto; outras escritas caem nas fontes do sistema. Os ícones usam o recorte da Material Symbols Rounded que vem junto. A tela Omarchy desenha os glifos do próprio menu na fonte do shell.
- **Movimento.** A forma anda em molas e o conteúdo aparece com fade já no layout final. Com as animações do Hyprland desligadas (`omarchy toggle animations`, ou o Modo jogo), tudo muda na hora.

## Ajustes

Duas chaves, em Central de controle › Ajustes da Ilha (o botão de ajustes no cabeçalho do cartão de notificações), ou com `omarchy-shell ilha open settings`:

- **Só no monitor focado** (`focusedOnly`, desligada por padrão): "Os outros monitores ficam sem a pílula". Só o monitor focado do Hyprland desenha a pílula em repouso. Os outros monitores não desenham nada e não recebem entrada até o foco ir para eles. Com `reserveTop`, todo monitor mantém os seus 48 px, então as janelas não se mexem quando o foco muda.
- **Aviso ao vivo** (`livePeek`, ligada por padrão): "Uma frase curta quando algo liga". Desligada, nenhum aviso ao vivo aparece.

Uma chave a mais não tem botão: **`reserveTop`** (desligada por padrão). Ligada, a Ilha reserva 48 px no alto de cada monitor e as janelas começam abaixo dela. Desligada, a ilha flutua por cima das janelas. Ligue com `omarchy-shell ilha setting reserveTop true`; vale na hora.

A página também mostra a versão.

A Ilha guarda as chaves em `~/.config/omarchy/shell.json`, sob `bar.ilha`, pela API de plugins do host (`mutateShellConfig`), que grava o arquivo de forma atômica. Ela só muda a chave que você virou, e só quando você vira uma chave ou roda `ilha setting`. Nada é gravado na instalação nem na partida. A pílula lê as chaves ao vivo, então uma edição à mão do `shell.json` também vale. Sem a API do host, a escolha só dura até o shell reiniciar, e a página diz "Vale até o shell reiniciar".

```json
"bar": { "ilha": { "focusedOnly": false, "livePeek": true, "reserveTop": false } }
```

```bash
omarchy-shell ilha setting livePeek false
omarchy-shell ilha setting focusedOnly toggle
```

## IPC

```bash
omarchy-shell ilha open <tela>             # abre uma tela, no modo teclado
omarchy-shell ilha toggle <tela>           # abre, ou fecha quando essa mesma tela está aberta
omarchy-shell ilha close                   # fecha a tela aberta e o seletor
omarchy-shell ilha back                    # volta: uma página da Central, a tela anterior ou fecha
omarchy-shell ilha run <tela> <tecla>      # abre no modo teclado e manda uma tecla, ex.: run themes right
omarchy-shell ilha picker                  # alterna os ícones (o seletor) no monitor focado
omarchy-shell ilha hover <0|1|2>           # segura os ícones (1) ou o nível 2 (2) no monitor focado; 0 solta
omarchy-shell ilha peek <chave>            # mostra um aviso ao vivo agora
omarchy-shell ilha osd '<json>'            # mostra um OSD na pílula
omarchy-shell ilha closeOsd                # esconde o OSD da pílula
omarchy-shell ilha setting <chave> <valor> # focusedOnly | livePeek | reserveTop; true | false | toggle
omarchy-shell ilha state                   # imprime o estado em JSON
```

- Telas: `launcher`, `calendar`, `themes`, `capture`, `menu`, `control`, `power`, `media`; `wallpapers` abre `themes` na fileira dos papéis de parede. Partes da Central de controle: `sound`, `display`, `wifi`, `bluetooth`, `settings`. Apelidos: `apps` (launcher), `clock` e `time` (calendar), `theme` e `look` (themes), `screenshot` e `record` (capture), `omarchy` (menu), `cc` e `controls` (control), `wallpaper`, `background` e `backgrounds` (a fileira dos papéis de parede), `last` (a última tela aberta).
- Teclas do `run`: uma letra ou um algarismo, `enter`, `space`, `esc`, `tab`, `up`, `down`, `left`, `right`, `pgup`, `pgdn`, `home`, `end`, `delete`, com um `shift+`, `ctrl+` ou `alt+` opcional na frente. A tecla vai quando a tela fica pronta (no máximo 3 s).
- Chaves do `peek`: `recording`, `reminder`, `update`, `dnd`, `nightlight`, `stayAwake`, `urgent`. Ele mostra mesmo com aquele estado desligado, mas não com o Aviso ao vivo desligado. `urgent` usa a notificação mais nova da tela.
- Respostas: `open` e `toggle` imprimem `ok` ou `unknown`; `run` imprime `ok`, `unknown` ou `invalid-key`; `picker` imprime `open`, `closed` ou `busy`; `peek` imprime `shown`, `queued`, `off`, `busy`, `quiet`, `unknown` ou `empty`; `osd` imprime `ok`, `invalid` ou `off`; `setting` imprime `ok`, `unknown` ou `invalid`.
- O `state` traz a tela aberta, a face de cada monitor, o OSD, o aviso ao vivo, o seletor, os ajustes (com `canPersist`), os takeovers, os widgets do Omarchy hospedados e as duas versões.

A Ilha também atende os alvos que a barra padrão registrava, para os scripts do próprio Omarchy continuarem funcionando:

```bash
omarchy-shell omarchy.clock <open|show|close|hide|toggle|refresh>   # open e show: o Calendário; close e hide: fecham
omarchy-shell omarchy.bar syncHidden
omarchy-shell omarchy.indicators refresh
omarchy-shell omarchy.system-update <refresh|clear>
omarchy-shell omarchy.workspaces refresh
```

O alvo `osd` continua sendo do Omarchy.

## Idiomas

A Ilha traz um catálogo em `i18n/` para cada um dos 50 idiomas que o Omarchy oferece. Ela segue Configuração › Idioma ao vivo, sem reiniciar o shell. Os números usam os algarismos do idioma: o relógio, os workspaces, o tempo da gravação, o calendário e as porcentagens. A data do nível 2 usa o formato de cada idioma e os nomes de dia e de mês dele, e o Calendário também. As telas Calendário, Captura e Omarchy também usam as traduções do próprio Omarchy para o texto que o Omarchy já tem. O que faltar cai no inglês.

Os idiomas da direita para a esquerda (árabe, persa, hebraico, urdu) espelham a ilha inteira. A marca fica à direita do relógio, a cápsula dos ícones começa com os workspaces à direita e o relógio no meio, e o ícone do aviso fica à direita. Esquerda e Direita seguem a direção da tela. O relógio, o tempo da gravação, as barras da rede, a bateria e a barra de progresso, os tempos e os botões de transporte da Mídia ficam da esquerda para a direita de propósito.

## Dependências

O Omarchy, com o shell dele. Nenhum pacote extra. As fontes vêm em `fonts/`. Os botões chamam os comandos e serviços do Omarchy que o nome diz (`omarchy-theme-set`, `omarchy-theme-bg-set`, `omarchy-system`, `omarchy-brightness-display`, `omarchy-bluetooth-power`, `omarchy-audio-output-set-default`, `omarchy-capture-screenshot`, `omarchy-reminder` e assim por diante). A Ilha roda a checagem de atualização do próprio Omarchy (`omarchy-update-available`) 5 s depois de começar, a cada 6 horas e quando o Omarchy pede.

A fileira do nível 2 hospeda os widgets do `bar.layout`, bandeja incluída, com os componentes que o host entrega a uma barra. Os widgets do menu, dos workspaces e do relógio não são hospedados: a Ilha desenha os dela. Uma tecla de um painel que não é de um widget hospedado nem de uma tela da Ilha não faz nada. Volte com `omarchy bar use omarchy.bar` quando precisar da barra padrão.

## Arquivos

| Caminho | Papel |
|---|---|
| `manifest.json` | Id, versão 2.4.0 e a entrada `bar` `ui/Ilha.qml` |
| `ui/Ilha.qml` | Entrada: contrato com o host, navegação, serviços, ajustes, IPC, os widgets hospedados e os painéis deles |
| `ui/IslandWindow.qml` | Uma janela por monitor: a forma, as faces, a máscara de entrada, as teclas |
| `ui/HoverBar.qml`, `RestMark.qml`, `ScreenPicker.qml`, `ScreenNav.qml`, `HeroClock.qml`, `Workspaces.qml` | Nível 2, a marca do repouso, o seletor, a navegação embaixo da tela, o relógio, os workspaces |
| `ui/OmarchyWidgets.qml`, `BarFacade.qml` | Os widgets da barra do Omarchy na fileira do nível 2, e o objeto `bar` que cada um recebe |
| `ui/PeekBridge.qml`, `PeekFace.qml` | Aviso ao vivo |
| `ui/OsdBridge.qml`, `OsdFace.qml` | OSD na pílula, pergunta da resolução, aviso de reinício |
| `ui/PickerBridge.qml` | Takeovers dos seletores de tema e de papel de parede |
| `ui/ScreenStack.qml` | Carrega e troca as telas |
| `ui/ControlCenter.qml`, `WifiCard.qml`, `BluetoothCard.qml`, `SoundPage.qml`, `DisplayPage.qml`, `IlhaPage.qml`, `MediaCard.qml`, `NotificationsCard.qml` | Central de controle |
| `ui/CalendarScreen.qml`, `CalendarSvc.qml` | Calendário, com os lembretes, os fusos e os ajustes do relógio que ele lê |
| `ui/CaptureScreen.qml`, `CaptureSvc.qml` | Captura, com os rótulos do Omarchy, a checagem da webcam e os comandos |
| `ui/MenuScreen.qml`, `MenuSvc.qml`, `OmarchyMenu.js` | A tela Omarchy e o menu como dados. O `OmarchyMenu.js` é um porte, sob MIT, do `MenuModel.js` do Omarchy |
| `ui/LauncherScreen.qml`, `MediaScreen.qml`, `LookScreen.qml` (com as fileiras `ThemeScreen.qml` e `WallpaperScreen.qml`), `PowerScreen.qml` | As outras telas |
| Os outros `ui/*Svc.qml`, `StateStore.qml`, `AppSearch.js` | Estado do sistema, áudio, rede, monitores, mídia, apps, temas, ajustes (`PrefsSvc.qml`), estado próprio |
| `ui/Theme.qml`, `Motion.js`, `Morph.qml`, `SpringValue.qml` | Cores, medidas, geometria de cada face, molas, tempos |
| O resto de `ui/` | Controles: `IlhaSwitch`, `IlhaSlider`, `IlhaRoundButton`, `ToggleTile`, `Carousel`, `CircleButton` e outros |
| `fonts/` | `InterIlha2.ttf` (recorte da Inter, OFL, `LICENSE-Inter.txt`) e `MaterialSymbolsRoundedIlha2.ttf` (recorte da Material Symbols Rounded, Apache 2.0, `LICENSE-MaterialSymbols.txt`) |
| `i18n/` | Um catálogo por idioma do Omarchy |
| `dev/` | Só para desenvolvimento; o Omarchy nunca carrega. O `harness.sh` roda uma instância à parte do Quickshell que nunca toca no shell em uso; os scripts em Python conferem catálogos, ícones, nomes e contraste, e geram os recortes das fontes |
| `uninstall.sh` | Volta para a barra padrão. O Omarchy não o executa |

Uma tela recebe `island`, `theme`, `strings`, `morph`, `payload`, `current` e `keyboardMode`, e informa o tamanho com `implicitWidth` e `implicitHeight`. Ela implementa `opened(payload)`, `closed()`, `handleKey(event)` e `handleEscape()`, e pode emitir `navigate(id, payload)` e `closeRequested()`. Nada numa tela roda antes de `opened()` nem depois de `closed()`.

## Quando algo falha

- A cópia nova não virou a barra. Rode `omarchy restart shell` e depois `omarchy plugin enable esegnorelli.ilha`.
- O shell registrou `bar option esegnorelli.ilha failed to load, falling back to omarchy.bar`. Rode `omarchy plugin validate ~/.config/omarchy/plugins/esegnorelli.ilha` e leia `journalctl -t omarchy-shell`.
- A pílula diz "Reinicie o shell para concluir a atualização da Ilha". O shell ainda roda o código antigo da Ilha. Toque no aviso ou rode `omarchy restart shell`.
- As teclas de volume e brilho mostram o OSD do Omarchy, não a pílula. É o esperado: o host não entrega o OSD dele para plugins de terceiros.
- Um widget da barra sumiu da fileira do nível 2. A Ilha só mostra os widgets do `bar.layout` do `~/.config/omarchy/shell.json`, menos o menu, os workspaces e o relógio. Um widget que se esconde sozinho (como o de atualização ou o de layout de teclado) não ocupa espaço.
- O `omarchy plugin update` recusa o pull. A cópia tem edições locais. Faça commit ou stash em `~/.config/omarchy/plugins/esegnorelli.ilha`.

## Licença

[MIT](LICENSE). Copyright 2026 Evandro Segnorelli.
