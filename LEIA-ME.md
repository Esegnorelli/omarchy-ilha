# Ilha

Barra flutuante para o [Omarchy](https://omarchy.org). Em repouso é o relógio. Com o ponteiro, vira a linha dos workspaces, e um clique abre a linha completa. Seis telas abrem dentro da mesma pílula: Central de controle, Apps, Mídia, Temas, Papéis de parede e Energia.

English documentation: [README.md](README.md).

A Ilha substitui a barra (`kinds: ["bar"]`, id `esegnorelli.ilha`, versão 2.0.0). Não é um widget dentro da barra padrão. As cores seguem o tema do Omarchy, e o texto segue o idioma do Omarchy.

> Depois de atualizar, se a pílula disser "Reinicie o shell para concluir a atualização da Ilha", toque nela ou rode `omarchy restart shell`.

## Instalar

```bash
omarchy plugin add https://github.com/Esegnorelli/omarchy-ilha.git --enable
```

O `omarchy plugin add` clona o repositório e valida o `manifest.json`. O `--enable` então troca a barra para a Ilha. O Omarchy pede confirmação antes, porque um plugin roda como código sem isolamento dentro do shell que fica aberto (`--yes` pula as perguntas). Não há pacote extra, nem sudo, nem passo de instalação. A Ilha não roda script de instalação e não grava nada quando começa.

Fora da própria pasta, a Ilha só grava isto:

- As duas chaves de ajuste, no `~/.config/omarchy/shell.json` do próprio Omarchy, sob `bar.ilha`, pela API de plugins do host (`mutateShellConfig`). Só quando você vira uma chave ou roda `ilha setting` (veja Ajustes).
- O próprio estado, em `~/.local/state/esegnorelli.ilha/` (`$XDG_STATE_HOME`, quando definido): `state.json` (quando você tocou em Limpar nas notificações pela última vez, e a temperatura da luz noturna) e `game-mode.json` enquanto o Modo jogo está ligado.
- A resposta ao alternador de fundo do Omarchy, nos dois arquivos de resposta que esse script cria e espera (veja Teclas de tema e de papel de parede).

Se a barra estiver escondida, mostre de novo com `omarchy toggle bar`.

## Atualizar

```bash
omarchy plugin update esegnorelli.ilha
```

Sem id, `omarchy plugin update` atualiza todo plugin instalado por git. Ele mostra o diff e não avança por cima de edições locais. Depois, o Omarchy relê os plugins.

O Omarchy não limpa o cache de QML. A Ilha compara a versão do `manifest.json` com a versão do código que o shell carregou. Quando elas não batem, a pílula mostra "Reinicie o shell para concluir a atualização da Ilha" por 8 segundos, uma vez por sessão, uns 2 segundos depois de a Ilha carregar. Ela espera, por até cerca de um minuto, enquanto houver uma tela, um nível de hover ou outro OSD na pílula. O toque roda `omarchy-restart-shell`. `omarchy restart shell` faz o mesmo. Com a barra escondida, o aviso aparece no OSD do Omarchy.

Vindo da 1.x:

- O código da 2.0 fica em `ui/`, uma pasta que a 1.x nunca teve, e a barra agora começa por `ui/Ilha.qml`. Os arquivos QML da 1.x na raiz saíram. Como todos os arquivos são novos, o shell carrega a 2.0 na hora, sem reiniciar.
- `focusedOnly` e `livePeek` em `bar.ilha` mantêm os valores. O `level2Dwell` saiu: o nível 2 abre no clique. A Ilha ignora a chave antiga e a apaga na próxima vez que gravar um ajuste.
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

Uma ilha por monitor, centrada no alto. Ela reserva 48 px no alto de cada monitor (`barSize` 48), então as janelas começam abaixo dela. A pílula cresce por cima das janelas; elas não se mexem. A ilha fica na camada top. Uma tela aberta por cima de uma janela em tela cheia passa para a camada overlay, para aparecer por cima dela.

Com a barra escondida (`omarchy toggle bar`), a pílula e os 48 px dela somem. As telas abertas por tecla ou por IPC continuam aparecendo.

| Estado | O que está na pílula |
|---|---|
| Repouso | O relógio, numa cápsula de 32 px de altura, a 10 px da borda de cima. Com algo ligado, uma marca fica ao lado do relógio. |
| Nível 1 | O ponteiro está na pílula. Uma linha de 42 px de altura, a 22 px do alto: os workspaces deste monitor em cápsulas numeradas, o relógio e o grupo de estado. |
| Nível 2 | Um clique no nível 1. Uma pílula de 718 × 75: o app em foco sobre os workspaces, um relógio grande com a data e a linha de estado sobre rede e bateria. |
| Seletor de telas | Botão direito ou toque longo. Seis ícones numa cápsula de 236 × 42. |
| Aviso ao vivo | Algo acabou de ligar. Uma linha curta, de 40 px de altura. |
| OSD | `ilha osd`, a pergunta da resolução ou o aviso de reinício. 40 px de altura. |
| Tela | Uma das seis telas, na mesma forma. |

### Repouso

O relógio mostra `HH:mm` com os algarismos do idioma. Ele fica em 12 horas (`h:mm`, sem AM/PM) quando a entrada `omarchy.clock` do layout da barra no `shell.json` tem um `format` com `AP`.

Com algo ligado, a cápsula alarga e uma marca fica ao lado do relógio (à esquerda dele; à direita nos idiomas da direita para a esquerda):

- O ícone do primeiro estado ligado, na cor dele, nesta ordem: sessão remota, sudo sem senha, gravação, lembrete, atualização, Não perturbe, luz noturna, manter acordado.
- Gravando, o tempo da gravação vem depois do ícone (`0:42`). O relógio em si fica em minutos.
- Com música tocando, três barrinhas na cor de destaque ficam encostadas no relógio. Elas não se mexem. Um player pausado não mostra nenhuma. Só com música ligada, as barrinhas são a marca inteira.

As notificações não fazem parte da marca.

Com o ponteiro em cima da marca, a pílula fica em repouso e a marca se destaca, para o toque cair nela. Em qualquer outro lugar, o ponteiro abre o nível 1 na hora.

- O toque na marca abre o dono dela. Sessão remota, sudo sem senha, gravação, lembrete e atualização abrem o nível 2 com esse estado fixado na linha de estado. Não perturbe e luz noturna abrem a Central de controle. Manter acordado abre Central de controle › Tela com o cartão Manter acordado em destaque.
- O toque nas barrinhas da música abre a Mídia.
- Um estado fixado fica na linha de estado enquanto estiver ligado. Depois do clique que o desliga (parar a gravação, por exemplo), a linha volta à ordem de sempre.

### Nível 1

O ponteiro na pílula, no vão acima dela ou na faixa da borda de cima abre o nível 1 na hora. Ao sair por 60 ms, volta o repouso.

- Workspaces: o bloco deste monitor (1–10, 11–20, …), os cinco primeiros e mais os de número maior que já existirem. O algarismo fica dentro de cada cápsula; o workspace 10 aparece como `10`. O ativo é maior, na cor de destaque, com um brilho. Os ocupados levam um tom da cor de destaque. Os vazios são apagados. Os urgentes usam a cor de urgência.
- Grupo de estado, nesta ordem: as barrinhas da música (com uma faixa carregada; mexem enquanto toca e ficam apagadas na pausa), o ponto de privacidade (gravação, sessão remota ou sudo sem senha; pulsa enquanto grava), a rede (barras do Wi-Fi, um ícone de cabo ou sem conexão) e a bateria (só em notebooks; um raio na tomada; a cor de urgência com 15 % ou menos na bateria).
- O clique numa cápsula foca esse workspace. O clique nas barrinhas da música abre a Mídia. O clique em qualquer outro lugar abre o nível 2.

### Nível 2

Um clique no nível 1 abre. Ele fica enquanto o ponteiro estiver em cima e fecha 2,5 s depois de o ponteiro sair. Super+Ctrl+Alt+D alterna o nível 2 no monitor focado.

- Esquerda: o ícone e o nome do app da janela em foco, ou "Área de trabalho" quando o workspace não tem janela. Quando a janela em foco é o player de música, o título e o artista. Embaixo, os workspaces, maiores.
- Centro: o relógio, maior, e a data no formato do idioma.
- Direita: a linha de estado, sobre rede e bateria.

Uma cápsula foca o workspace dela. A linha do app abre os Apps (a Mídia quando mostra o player). O relógio e a data abrem a Central de controle. A linha de estado executa a ação dela. O espaço vazio volta ao nível 1.

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

### Seletor de telas

O botão direito, ou um toque longo (0,5 s), na pílula em repouso, no nível 1 ou no nível 2 mostra seis ícones: Apps, Central de controle, Mídia, Temas, Papéis de parede, Energia. É a mesma ordem do Alt+1–6. Os ícones não têm rótulo.

- O toque num ícone abre aquela tela. A Mídia está sempre lá; sem player, abre "Nada tocando".
- O toque entre os ícones, ou outro clique direito, fecha o seletor.
- Ele fecha sozinho 2,6 s depois de abrir se o ponteiro não chegar nele, ou 0,7 s depois de o ponteiro sair dele.
- Ele não abre com uma tela aberta nem com a barra escondida.
- O toque longo numa cápsula de workspace não foca o workspace.

### Dica da linha

Na primeira vez que o nível 1 abre numa sessão, uma etiqueta pequena aparece embaixo dele por 3 s: "Clique: mais · Botão direito ou segurar: telas · Alt+1–6: trocar". Ela some quando a linha fecha. Não aparece com a barra escondida nem com o aviso de reinício na tela. Não é gravada, então a próxima sessão mostra de novo.

### Borda de cima

Uma faixa invisível de 3 px nos 600 px do centro da borda de cima (menos em telas estreitas) abre o nível 1, nunca o nível 2. Em cima da marca, a pílula fica em repouso, então levar o ponteiro até o alto sobre a marca e clicar abre o dono da marca.

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
- Só a mudança conta. Estados que já estavam ligados quando a Ilha começou, ou que mudam nos primeiros 4 segundos dela, não geram aviso. Sessão remota e sudo sem senha nunca geram aviso; eles aparecem na marca e no nível 2.
- Com o Não perturbe ligado, só aparecem os avisos de Não perturbe, de gravação e de urgência.
- Nenhum aviso aparece com uma tela ou o seletor aberto, nem com uma janela em tela cheia no monitor focado. Com a pílula focada no nível 1, no nível 2 ou mostrando um OSD, o aviso espera até 5 s ela voltar ao repouso.
- Um aviso de prioridade igual ou maior troca o que está na tela (urgente, gravação, lembrete, atualização, Não perturbe, luz noturna, manter acordado). Um OSD no mesmo monitor encerra o aviso.
- Com o Aviso ao vivo desligado nos Ajustes da Ilha, nenhum aviso aparece.

As notificações comuns nunca aparecem na pílula. Os cartões do próprio Omarchy ficam, porque são eles que trazem as ações.

## Telas

Seis telas, numa ordem só: Apps, Central de controle, Mídia, Temas, Papéis de parede, Energia. O seletor, o Alt+1–6, o Ctrl+Tab e a roda usam essa ordem. O Ctrl+Tab e a roda pulam a Mídia quando não há player. Uma tela abre na pílula, no monitor focado para teclas e IPC, ou no monitor que você clicou. Telas abertas por tecla, por IPC ou por um takeover começam no modo teclado. Os anéis de foco só aparecem no modo teclado.

### Central de controle

514 × 513. Duas linhas de controles e depois três cartões.

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
| Cartão | Notificações | Veja abaixo |

**Notificações.** As da tela primeiro, com um ponto na cor de destaque, depois as fechadas nas últimas 24 horas desde o último Limpar, da mais nova para a mais velha, no máximo 30. "Limpar" dispensa todas. O clique na mais nova da tela clica nela, como o cartão do Omarchy faria, e fecha a ilha. O hover numa notificação da tela mostra um botão para dispensá-la. Sem nenhuma: "Nenhuma notificação". Com o ponteiro no cartão, ou no modo teclado, uma fileira de atalhos aparece no cabeçalho dele: Ajustes da Ilha, Apps, Temas, Papéis de parede, Energia.

**Popovers e páginas.** Cada um nasce do controle que o abriu e escurece a grade. O botão de voltar, o Esc ou um toque fora do cartão volta.

- Wi-Fi: uma chave para o rádio, a rede conectada com Desconectar e depois "Redes" com Conectar. Só procura redes enquanto está aberto. Cinco linhas aparecem; o resto rola. Uma rede protegida pede a senha na própria linha ("Senha incorreta" se falhar). Uma rede conhecida mostra um botão para esquecê-la. Uma rede corporativa (802.1X) abre o `nmtui` num terminal.
- Bluetooth: uma chave, os aparelhos "Salvos" com Conectar ou Desconectar e depois os aparelhos "Por perto" com Parear. Só procura aparelhos enquanto está aberto. Conectar um fone passa a saída de áudio para ele.
- Som: os aparelhos de "Saída" e o volume de saída, depois os de "Entrada" e o volume de entrada. Uma linha escolhe o aparelho padrão.
- Tela: um cartão por monitor, com brilho, escala (de 1.0× a 2.0×, as que cabem no monitor) e Resolução (até 6 modos). Uma resolução nova pergunta "Manter esta resolução? Revertendo em 10 s", com Manter e Reverter, e reverte sozinha. Se a Central fechar, a contagem passa para a pílula, e o toque mantém a resolução. Depois vêm a Luz noturna (uma chave e a temperatura, 2500–5800 K) e o Manter acordado ("A tela não escurece, bloqueia nem dorme").
- Ilha: as duas chaves. Veja Ajustes.

**Teclas.** As setas andam pela posição. Tab e Shift+Tab andam na ordem. Home vai ao Wi-Fi; End, às notificações. Enter executa a ação principal. Espaço aperta o círculo do ícone de um bloco, ou deixa mudo na barra de Som. Numa barra, Esquerda e Direita mudam 5 % (Shift: 1 %). M deixa mudo no cartão Som. Numa notificação, Delete dispensa uma da tela, e Enter na mais nova da tela clica nela. Nos popovers e nas páginas, Cima e Baixo andam, Enter e Espaço escolhem ou alternam, Espaço liga e desliga o rádio no Wi-Fi e no Bluetooth, Delete esquece uma rede Wi-Fi conhecida, Esquerda e Direita mudam as barras em 5 % (Shift: 1 %), e M deixa muda a seção focada no Som. O Esc fecha o campo de senha ou uma lista aberta, depois o popover ou a página, depois a ilha.

### Apps

514 × 368. A busca de aplicativos: "Buscar…" no alto, seis linhas embaixo.

- Sem nada digitado, todos os apps visíveis, de A a Z. Ao digitar, a ordem segue a busca aproximada. Sem resultado: "Nenhum app encontrado".
- As entradas escondidas seguem as regras do próprio Omarchy.
- O destaque só segue o ponteiro quando o ponteiro anda. A roda rola a lista.
- Apps de terminal abrem pelo `omarchy-launch-tui`; o resto, pelo `uwsm-app -- gtk-launch`. Quando nenhuma janela aparece em 2 s, o OSD do Omarchy diz "Abrindo Firefox…" (com o nome do app) até ela aparecer, por no máximo 15 s.
- Teclas: Cima e Baixo, Tab e Shift+Tab (dão a volta), Page Up e Page Down de 6 em 6. Enter abre o app e fecha. Esc limpa e depois fecha.

### Mídia

514 × 218. O player MPRIS ativo, pelo serviço de mídia do Omarchy.

- A capa, o título, o artista e o nome do player. Com mais de um player, o nome é um botão que troca de player.
- A barra de progresso, com o tempo decorrido e o que falta. Clique ou arraste nela quando o player deixa.
- Aleatório, anterior, tocar/pausar, próxima, repetir (desligado, lista, faixa). Aleatório e repetir funcionam quando o player suporta.
- Sem player: "Nada tocando" e "Toque algo em qualquer player", no mesmo tamanho.
- Teclas: Espaço ou Enter tocar/pausar, Esquerda e Direita voltam ou avançam 5 s, Shift+Esquerda e Shift+Direita anterior e próxima, S aleatório, R repetir, P próximo player.

Ela também abre pelas barrinhas da música, pelas linhas do app e de estado do nível 2, por um OSD de mídia e pelo Super+Ctrl+4.

### Temas

Tão larga quanto couberem de 2 a 4 cartões na tela (30 + 194 px por cartão), 222 de altura.

- Um campo de busca ("Buscar temas…") e um contador (`3/18`). Sem resultado: "Nenhum tema encontrado".
- Cada cartão mostra o fundo do tema, seis pontos da paleta dele e o nome na cor de texto dele. O cartão do centro é o escolhido: ele sobe e ganha uma borda na cor de destaque. Um pontinho marca o tema em uso.
- "Enter para aplicar". O Enter roda `omarchy-theme-set`. O pontinho muda na hora. A tela fecha quando o tema entra em uso, ou 1,5 s depois. Não há prévia ao vivo. As cores da ilha trocam com um fade de 150 ms quando a paleta nova chega.
- Mouse: o clique centraliza um cartão. O clique no cartão do centro, ou um clique duplo, aplica. A roda anda um cartão por volta.
- Teclas: as setas (Esquerda e Direita seguem a direção da tela), Tab e Shift+Tab, Page Up e Page Down de 4 em 4, Home, End, Enter aplica. Esc limpa a busca e depois fecha.
- Os temas vêm de `~/.config/omarchy/themes` e dos temas do próprio Omarchy. O seu vence quando o nome é o mesmo.

### Papéis de parede

Tão larga quanto couberem de 2 a 5 miniaturas na tela (32 + 196 px por miniatura), 232 de altura.

- "Papel de parede" e o nome do tema no alto. A miniatura escolhida fica no centro com uma borda na cor de destaque. Um pontinho marca o papel em uso. Embaixo da faixa: o nome do arquivo, o contador e "Enter para aplicar".
- Aberta pela Ilha (seletor, Alt+5, Ctrl+Tab, `ilha open wallpapers`): os fundos do tema atual mais `~/.config/omarchy/backgrounds/<tema>`. O Enter roda `omarchy-theme-bg-set` e fecha quando ele termina (no máximo 1,2 s). Sem nenhum: "Nenhum papel de parede para este tema".
- Aberta pelas teclas de fundo do Omarchy: veja Teclas de tema e de papel de parede.
- Papéis de parede em vídeo usam a miniatura guardada.
- Mouse como em Temas. Teclas: as setas, Tab e Shift+Tab, Page Up e Page Down de uma tela inteira, Home, End, Enter aplica, Esc fecha.

### Energia

514 × 112. Cinco botões: Bloquear, Suspender, Sair, Reiniciar, Desligar.

- Bloquear vem escolhido quando abre. O ponteiro escolhe, o clique aperta.
- Sair, Reiniciar e Desligar pedem um segundo toque em até 3 s: o rótulo diz "Toque de novo". Um segundo toque antes de 350 ms é ignorado.
- Suspender fica apagado quando o sono está desligado no Omarchy.
- Teclas: Esquerda e Direita (seguem a direção da tela), Tab e Shift+Tab, Home, End, 1–5 escolhem e apertam, Enter ou Espaço apertam. Esc cancela uma confirmação pendente e depois fecha.
- O comando roda 180 ms depois de a ilha fechar: `omarchy-system-lock`, `systemctl suspend`, `omarchy-system logout`, `omarchy-system reboot` ou `omarchy-system shutdown`.

## Mouse e teclado

- A roda só troca de tela com uma tela aberta, na faixa que cobre a largura da tela nos 24 px de cima do monitor: o vão acima da tela e o respiro de cima dela. Cada volta (120 unidades) anda uma tela, na ordem acima. Para baixo avança, para cima volta. Uma volta incompleta zera depois de 200 ms sem eventos da roda, ou quando o sentido vira, então um deslize lento do trackpad nunca troca de tela. Os idiomas da direita para a esquerda não invertem a roda. No repouso, nos níveis 1 e 2, no seletor, num aviso ou num OSD, a roda não faz nada. Listas, carrosséis e controles deslizantes guardam a própria roda.
- O botão direito ou um toque longo (0,5 s) na pílula em repouso, no nível 1 ou no nível 2 mostra o seletor. No seletor, fecha. Num aviso ao vivo, dispensa.
- Um clique fora de uma tela aberta fecha a tela.
- As teclas só valem com uma tela aberta. Os níveis de hover, o seletor e os avisos nunca pegam o teclado.
- Ctrl+Tab e Ctrl+Shift+Tab andam pelas telas. Alt+1–6 abrem direto: Apps, Central de controle, Mídia, Temas, Papéis de parede, Energia.
- O Esc vai primeiro para a tela (limpa uma busca, fecha um popover ou uma página, cancela uma confirmação) e depois fecha a ilha.
- Qualquer tecla liga o modo teclado. Andar o ponteiro mais de 8 px desliga.

### Teclas do Omarchy

As teclas de painel do próprio Omarchy caem nas telas da Ilha. A mesma tecla de novo fecha o que ela abriu.

| Tecla | Nome no Omarchy | Na Ilha |
|---|---|---|
| Super+Ctrl+A | Áudio | Central de controle › Som |
| Super+Ctrl+B | Bluetooth | Central de controle › Bluetooth |
| Super+Ctrl+N | Rede | Central de controle › Wi-Fi |
| Super+Ctrl+D | Tela | Central de controle › Tela |
| Super+Ctrl+P | Energia | Energia |
| Super+Ctrl+Alt+D | Calendário | Nível 2, no monitor focado |
| Super+Ctrl+Alt+E | Relógio mundial | Central de controle |
| Super+Ctrl+1, 2, 3, 4 | Painel da barra 1–4 | Central de controle › Som, Central de controle › Wi-Fi, Energia, Mídia |
| Super+Ctrl+5 a 9 | Painel da barra 5–9 | Nada |
| Super+Ctrl+T, Super+Shift+Ctrl+Space | Menu de temas | Temas |
| Super+Ctrl+W, Super+Ctrl+Space | Alternador de fundo | Papéis de parede |

### Teclas de tema e de papel de parede

A Ilha assume os dois seletores de imagem do Omarchy. Nenhuma tecla e nenhuma entrada de menu é trocada: as mesmas teclas e entradas abrem as telas da Ilha.

- **Papéis de parede.** Super+Ctrl+W, Super+Ctrl+Space e Menu › Aparência › Plano de fundo rodam o alternador de fundo do Omarchy, que pede um seletor ao alvo `image-selector` do shell. A Ilha atende esse alvo antes do seletor do Omarchy. Quando todas as imagens do pedido estão nos fundos do tema (`~/.local/state/omarchy/current/theme/backgrounds/`) ou em `~/.config/omarchy/backgrounds/`, a tela de Papéis de parede abre com as imagens do pedido. O Enter grava a escolha no arquivo de resposta que o script espera, e o script do Omarchy aplica. Esc, um clique fora ou outra tela devolvem uma escolha vazia, então o script nunca fica esperando para sempre.
- **Temas.** Super+Ctrl+T, Super+Shift+Ctrl+Space e Menu › Aparência › Tema abrem o seletor de temas do Omarchy. Quando esse seletor abre sem um pedido que a Ilha repassou, a Ilha o esconde e abre a tela de Temas. O seletor do Omarchy abre transparente, então some antes de mostrar um quadro.
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

- `ilha osd '<json>'`, com os mesmos campos do `omarchy-shell osd show`: `icon`, `message`, `value`, `max`, `progressText` e `duration` em ms (padrão 1200; `0` deixa na tela até um toque ou `ilha closeOsd`). Um valor sem mensagem desenha um ícone, uma barra e o valor. Uma mensagem desenha uma linha. Um ícone `media` ou `player` desenha a capa com o título e o artista.
- "Manter esta resolução? Revertendo em 10 s", enquanto a página Tela não está à vista. O toque mantém a resolução.
- O aviso de reinício (veja Atualizar).

Quando a pílula não pode desenhar (barra escondida, uma janela em tela cheia no monitor focado, ou uma tela que não seja a Central de controle aberta), o `ilha osd` vai para o OSD do Omarchy. Com a Central de controle aberta, um OSD de volume ou de brilho não é desenhado enquanto o controle deslizante dele está à vista; o resto vai para o OSD do Omarchy.

O OSD aparece no monitor focado. O toque num OSD de volume abre Central de controle › Som; num de brilho, Central de controle › Tela; num de mídia, a Mídia. Qualquer outro toque dispensa.

## Aparência

- **Cores.** A Ilha lê as cores de fundo, texto, destaque e urgência do tema do Omarchy. A ilha é sempre escura: a superfície é a mais escura entre fundo e texto, a 10 % sobre o preto. Cartões e linhas são degraus mais claros na cor do texto. A cor de destaque vai na direção da cor do texto até ser legível sobre a superfície (3:1 nos preenchimentos, 4,5:1 no texto), e a de urgência também. Uma troca de tema muda as cores com um fade de 150 ms. A Ilha não grava paleta nenhuma.
- **Forma.** Uma cápsula com um fio de borda de 1 px e uma sombra suave. Com as chaves de vidro do Omarchy ligadas (`~/.local/state/omarchy/toggles/hypr/bar-glassy.lua` ou `window-glassy.lua`), a sombra fica mais leve. A ilha continua opaca.
- **Posição.** Sempre no alto. Os ajustes de posição e de fundo da barra do Omarchy não valem para a Ilha.
- **Fontes.** O texto usa o recorte da Inter que vem junto; outras escritas caem nas fontes do sistema. Os ícones usam o recorte da Material Symbols Rounded que vem junto.
- **Movimento.** A forma anda em molas e o conteúdo aparece com fade já no layout final. Com as animações do Hyprland desligadas (`omarchy toggle animations`, ou o Modo jogo), tudo muda na hora.

## Ajustes

Duas chaves, em Central de controle › Ajustes da Ilha (o primeiro botão da fileira de atalhos do cartão de notificações), ou com `omarchy-shell ilha open settings`:

- **Só no monitor focado** (`focusedOnly`, desligada por padrão): "Os outros monitores ficam sem a pílula". Só o monitor focado do Hyprland desenha a pílula em repouso. Os outros monitores não desenham nada e não recebem entrada até o foco ir para eles. Todo monitor mantém os seus 48 px, então as janelas não se mexem quando o foco muda.
- **Aviso ao vivo** (`livePeek`, ligada por padrão): "Uma frase curta quando algo liga". Desligada, nenhum aviso ao vivo aparece.

A página também mostra a versão.

A Ilha guarda as duas em `~/.config/omarchy/shell.json`, sob `bar.ilha`, pela API de plugins do host (`mutateShellConfig`), que grava o arquivo de forma atômica. Ela só muda a chave que você virou, e só quando você vira uma chave ou roda `ilha setting`. Nada é gravado na instalação nem na partida. A pílula lê as chaves ao vivo, então uma edição à mão do `shell.json` também vale. Sem a API do host, a escolha só dura até o shell reiniciar, e a página diz "Vale até o shell reiniciar".

```json
"bar": { "ilha": { "focusedOnly": false, "livePeek": true } }
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
omarchy-shell ilha run <tela> <tecla>      # abre no modo teclado e manda uma tecla, ex.: run themes right
omarchy-shell ilha picker                  # alterna o seletor de telas no monitor focado
omarchy-shell ilha hover <0|1|2>           # segura o nível 1 ou 2 no monitor focado; 0 solta
omarchy-shell ilha peek <chave>            # mostra um aviso ao vivo agora
omarchy-shell ilha osd '<json>'            # mostra um OSD na pílula
omarchy-shell ilha closeOsd                # esconde o OSD da pílula
omarchy-shell ilha setting <chave> <valor> # focusedOnly | livePeek; true | false | toggle
omarchy-shell ilha state                   # imprime o estado em JSON
```

- Telas: `launcher`, `control`, `media`, `themes`, `wallpapers`, `power`. Partes da Central de controle: `sound`, `display`, `wifi`, `bluetooth`, `settings`. Apelidos: `apps` (launcher), `cc` e `controls` (control), `theme` (themes), `wallpaper` e `background` (wallpapers), `last` (a última tela aberta).
- Teclas do `run`: uma letra ou um algarismo, `enter`, `space`, `esc`, `tab`, `up`, `down`, `left`, `right`, `pgup`, `pgdn`, `home`, `end`, `delete`, com um `shift+`, `ctrl+` ou `alt+` opcional na frente. A tecla vai quando a tela fica pronta (no máximo 3 s).
- Chaves do `peek`: `recording`, `reminder`, `update`, `dnd`, `nightlight`, `stayAwake`, `urgent`. Ele mostra mesmo com aquele estado desligado, mas não com o Aviso ao vivo desligado. `urgent` usa a notificação mais nova da tela.
- Respostas: `open` e `toggle` imprimem `ok` ou `unknown`; `run` imprime `ok`, `unknown` ou `invalid-key`; `picker` imprime `open`, `closed` ou `busy`; `peek` imprime `shown`, `queued`, `off`, `busy`, `quiet`, `unknown` ou `empty`; `osd` imprime `ok`, `invalid` ou `off`; `setting` imprime `ok`, `unknown` ou `invalid`.
- O `state` traz a tela aberta, a face de cada monitor, o OSD, o aviso ao vivo, o seletor, os ajustes (com `canPersist`), os takeovers e as duas versões.

A Ilha também atende os alvos que a barra padrão registrava, para os scripts do próprio Omarchy continuarem funcionando:

```bash
omarchy-shell omarchy.clock <open|show|close|hide|toggle|refresh>   # open e show: nível 2; close e hide: volta
omarchy-shell omarchy.bar syncHidden
omarchy-shell omarchy.indicators refresh
omarchy-shell omarchy.system-update <refresh|clear>
omarchy-shell omarchy.workspaces refresh
```

O alvo `osd` continua sendo do Omarchy.

## Idiomas

A Ilha traz um catálogo em `i18n/` para cada um dos 50 idiomas que o Omarchy oferece. Ela segue Configuração › Idioma ao vivo, sem reiniciar o shell. Os números usam os algarismos do idioma: o relógio, os workspaces, o tempo da gravação e as porcentagens. A data do nível 2 usa o formato de cada idioma e os nomes de dia e de mês dele. O que faltar cai no inglês.

Os idiomas da direita para a esquerda (árabe, persa, hebraico, urdu) espelham a ilha inteira. A marca fica à direita do relógio, o seletor começa com os Apps à direita e o ícone do aviso fica à direita. Esquerda e Direita seguem a direção da tela. O relógio, o tempo da gravação, as barras da rede, a bateria e a barra de progresso, os tempos e os botões de transporte da Mídia ficam da esquerda para a direita de propósito.

## Dependências

O Omarchy, com o shell dele. Nenhum pacote extra. As fontes vêm em `fonts/`. Os botões chamam os comandos e serviços do Omarchy que o nome diz (`omarchy-theme-set`, `omarchy-theme-bg-set`, `omarchy-system`, `omarchy-brightness-display`, `omarchy-bluetooth-power`, `omarchy-audio-output-set-default` e assim por diante). A Ilha roda a checagem de atualização do próprio Omarchy (`omarchy-update-available`) 5 s depois de começar, a cada 6 horas e quando o Omarchy pede.

A Ilha não desenha nenhum outro widget de barra nem a bandeja. Uma tecla de um painel que não tem tela na Ilha não faz nada. Volte com `omarchy bar use omarchy.bar` quando precisar deles.

## Arquivos

| Caminho | Papel |
|---|---|
| `manifest.json` | Id, versão 2.0.0 e a entrada `bar` `ui/Ilha.qml` |
| `ui/Ilha.qml` | Entrada: contrato com o host, navegação, serviços, ajustes, IPC |
| `ui/IslandWindow.qml` | Uma janela por monitor: a forma, as faces, a máscara de entrada, as teclas |
| `ui/HoverBar.qml`, `RestMark.qml`, `ScreenPicker.qml`, `LineHint.qml`, `HeroClock.qml`, `Workspaces.qml` | Níveis 1 e 2, a marca do repouso, o seletor, a dica da linha, o relógio, os workspaces |
| `ui/PeekBridge.qml`, `PeekFace.qml` | Aviso ao vivo |
| `ui/OsdBridge.qml`, `OsdFace.qml` | OSD na pílula, pergunta da resolução, aviso de reinício |
| `ui/PickerBridge.qml` | Takeovers dos seletores de tema e de papel de parede |
| `ui/ScreenStack.qml` | Carrega e troca as telas |
| `ui/ControlCenter.qml`, `WifiCard.qml`, `BluetoothCard.qml`, `SoundPage.qml`, `DisplayPage.qml`, `IlhaPage.qml`, `NotificationsCard.qml` | Central de controle |
| `ui/LauncherScreen.qml`, `MediaScreen.qml`, `ThemeScreen.qml`, `WallpaperScreen.qml`, `PowerScreen.qml` | As outras telas |
| `ui/*Svc.qml`, `StateStore.qml`, `AppSearch.js` | Estado do sistema, áudio, rede, monitores, mídia, apps, temas, ajustes (`PrefsSvc.qml`), estado próprio |
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
- A bandeja, ou outro widget de barra, sumiu. A Ilha não desenha nenhum. Use `omarchy bar use omarchy.bar` quando precisar deles.
- O `omarchy plugin update` recusa o pull. A cópia tem edições locais. Faça commit ou stash em `~/.config/omarchy/plugins/esegnorelli.ilha`.

## Licença

[MIT](LICENSE). Copyright 2026 Evandro Segnorelli.
