# FiveEMS v0.4.7 — Portable LIFEPAK + Persistent Monitor Overlay

FiveEMS é um resource FiveM para EMS, hospitais e Polícia Científica/CSI. A V0.4.5aa mantém a base da V0.4.3 e aplica a nova interface clínica visual aprovada para o atendimento em cena.

## Novidades da V0.4.5aa

- Nova interface clínica em cena com identidade visual baseada nas logos e banner do FiveEMS.
- Shield/logo e wordmark do FiveEMS incorporados na tela de atendimento.
- Paleta visual atualizada para azul + vermelho, seguindo a marca FiveEMS.
- Botões de câmera/zoom refinados e mantidos na barra superior.
- Painel esquerdo de tratamento com rolagem dedicada.
- Painel `STATUS DO ATOR` reorganizado na ordem anatômica solicitada: Cabeça, Pescoço, Braço Esquerdo, Braço Direito, Tórax, Abdome, Pelve, Perna Esquerda, Perna Direita, Pé Esquerdo e Pé Direito.
- Marcadores `+` centralizados e estilos ajustados para melhor leitura.
- HUD padrão e radar/minimapa ficam ocultos durante o atendimento do paciente, reduzindo sobreposição visual com a NUI clínica.

> Este resource é um sistema de gameplay/RP. Os mecanismos clínicos foram inspirados nos materiais fornecidos pelo projeto, mas não substituem protocolos, treinamento, supervisão médica ou orientação profissional real.

> Este resource é um sistema de gameplay/RP. Os mecanismos clínicos foram inspirados nos materiais fornecidos pelo projeto, mas não substituem protocolos, treinamento, supervisão médica ou orientação profissional real.

## Dependências

- OneSync ativo.
- `oxmysql` obrigatório.
- `fivepd_sp_inventory` é o inventário canônico desta versão; o FiveEMS não usa mais `ox_inventory`.
- Nenhum framework de personagem/job é obrigatório: o FiveEMS possui tabela própria de membros, departamentos, cargos e XP.

## Instalação

1. Copie a pasta `FiveEMS` para `resources/[medical]/FiveEMS`.
2. **Não é mais necessário importar `sql/fiveems.sql` manualmente.** Ao iniciar, o FiveEMS lê esse arquivo e cria as tabelas automaticamente usando `CREATE TABLE IF NOT EXISTS`.
3. No `server.cfg`, deixe `oxmysql` iniciar antes do FiveEMS.
4. Adicione a permissão administrativa, por exemplo:

   `add_ace group.admin fiveems.admin allow`

5. Adicione `ensure FiveEMS`.
6. Reinicie o resource/servidor e procure no console:

   `[FiveEMS][DB] Banco pronto. Nao e mais necessario importar o SQL manualmente.`

7. Dentro do jogo rode `/fiveemsdb` e depois `/fiveemstest`.
8. Use `/fiveemsadmin` para criar o primeiro departamento.
9. Ao criar um departamento EMS/Hospital, equipamentos e medicamentos padrão são cadastrados automaticamente. Para CSI, o catálogo pericial é cadastrado automaticamente.
10. Na Mesa da Direção do departamento, atribua seu próprio Server ID ao cargo `Diretor` para testar o fluxo operacional como membro do departamento.

### Configuração do auto banco

Em `config.lua`:

```lua
Config.Database = {
    autoInstall = true,
    autoSeedCatalogOnDepartmentCreate = true,
    startupTimeoutMs = 30000,
}
```

O SQL continua dentro do pacote como fallback e referência, mas a importação manual não é necessária com `autoInstall = true`.

## Comandos atuais

- `/fiveemshelp` — mostra todos os comandos no console F8.
- `/fiveemsdb` — verifica banco/schema/tabelas (admin).
- `/fiveemstest` — diagnóstico de oxmysql, FivePD SP bridge, banco, departamento, cargo e duty (admin).
- `/fiveemsseed <departmentId>` — recarrega o catálogo padrão do departamento (admin; útil para departamentos criados na V0.1.0).
- `/fiveemsadmin` — abre criador/administração (ACE `fiveems.admin`).
- `/fiveems` — abre o FiveEMS OS.
- `/fiveemsexam` — abre atendimento para o player mais próximo.
- `/fiveemspatient <id>` — abre atendimento pelo Server ID.
- `/fiveemsmonitor` — monitor do player mais próximo.
- `/ems911 <texto>` — abre chamado EMS na posição atual.
- `/fiveemsstretcher` — cria/remove maca configurada.
- `/fiveemsstretcherin` — prende a maca no perfil da ambulância.
- `/fiveemsstretcherout` — retira a maca da ambulância.
- `/fiveemspatientstretcher <id>` — posiciona player na maca.
- `/fiveemspatientrelease` — libera player da maca.
- `/fiveemsresetpatient <id>` — reinicia o estado médico do player (admin; muito útil nos testes).

## Ordem de teste recomendada

### 1. Banco e dependências

1. `restart FiveEMS` pelo console do servidor.
2. Dentro do jogo: `/fiveemsdb`.
3. Depois: `/fiveemstest`.
4. Abra o F8 e confirme `Banco: OK` e `oxmysql: started`.

### 2. Departamento

1. `/fiveemsadmin`.
2. Crie um departamento do tipo `ems` ou `hospital`.
3. Confirme que o cargo `Diretor` foi criado automaticamente.
4. Abra a aba Estoque e confirme que o catálogo já apareceu sem apertar botão de seed.
5. Crie os pontos `duty`, `supply`, `garage`, `director`, `computer`, `tablet`, `monitor`, `bed`, `surgery` e `stretcher` conforme necessário.
6. Na Mesa da Direção, atribua seu Server ID ao cargo Diretor.
7. Rode `/fiveemstest` de novo; agora deve aparecer `Membro FiveEMS: SIM`.
8. Vá até o ponto de duty, pressione `E` e confirme que muda para em serviço.

### 3. Atendimento entre dois players

Use dois players próximos.

1. No paciente: `/fiveemsresetpatient <ID_DO_PACIENTE>` para começar limpo.
2. No EMS: `/fiveemsexam` ou `/fiveemspatient <ID_DO_PACIENTE>`.
3. Teste XABCDE, aba de lesões, tratamentos, oxigênio e relatório.
4. `/fiveemsmonitor` para abrir o monitor do player mais próximo.
5. Teste o ePCR e confirme que o relatório é enviado e o XP sobe.

### 4. Dano físico

No paciente, provoque separadamente dano em braço, perna, cabeça, queda, tiro e colisão. Depois abra o atendimento e confira se a região/mecanismo aparecem e se os efeitos funcionais são aplicados quando a gravidade passa do limite configurado.

Entre testes use:

`/fiveemsresetpatient <ID>`

### 5. Maca

Antes, configure `Config.Stretcher.defaultModel` ou um perfil de maca no departamento.

1. `/fiveemsstretcher`
2. `/fiveemspatientstretcher <ID_DO_PACIENTE>`
3. `/fiveemsstretcherin` perto da ambulância
4. `/fiveemsstretcherout`
5. `/fiveemspatientrelease`
6. `/fiveemsstretcher` novamente para remover a maca

### 6. Chamados

Use:

`/ems911 vítima ferida após colisão`

Um EMS em duty deve receber o chamado.

### 7. CSI

Crie também um departamento tipo `csi`. O catálogo de luvas, câmera, embalagens, swab, luz forense, régua, pinça e kit papiloscópico entra automaticamente. Configure `duty`, `supply`, `lab` e `evidence_locker` e teste a coleta/análise de vestígios gerados pelo sistema.

## O que mudou na V0.1.1

- Instalação automática de todas as tabelas FiveEMS.
- Tabela `fiveems_schema_migrations` para registrar a versão do schema.
- Espera de inicialização do banco antes de consultas do resource.
- Seed automático de equipamento/medicação ao criar EMS/Hospital.
- Seed automático de material pericial ao criar CSI.
- `/fiveemshelp`, `/fiveemsdb`, `/fiveemstest` e `/fiveemsseed`.
- Versão do resource/NUI atualizada para V0.1.1.

## NPC persistente

O sistema de identidade médica persistente para NPC continua deliberadamente fora desta fase, conforme solicitado, para posterior integração com o sistema desenvolvido pelo outro programador.


## Histórico visual anterior (V0.1.x)
- Painel de Admin separado do painel da Mesa do Diretor.
- Medical OS do computador separado do Medical OS do tablet.
- Monitor multiparamétrico separado como aparelho próprio.
- Novo indicador visual de toque no tablet (substitui o dedo antigo).
- Novo ponto de departamento: `monitor`.

### Comandos novos
- `/fiveemscomputer` — abre o Medical OS do computador.
- `/fiveemstablet` — abre o Medical OS do tablet.
- `/fiveemsdirector` — abre a Mesa do Diretor (requer permissão do departamento).


## Histórico visual anterior (V0.1.x)
- Polimento visual do Computer OS e Tablet OS.
- Atalhos no escritorio e na home do tablet.
- Settings com seções (Appearance, Language, Date & Time, Personalization e About).
- Widgets e icones podem ser ligados/desligados nas preferencias.
- Janelas com double-click para maximizar e snap/top maximize.
- Refino visual de dock, chips minimizados, widgets e animações.


## V0.2.1 — FivePD SP Framework Bridge
Esta versao muda a fundacao do FiveEMS para a base FivePD SP do servidor. Execute `/fiveemsframework` e `/fiveemstest` depois do restart. Consulte `docs/FRAMEWORK_BRIDGE.md`.


## V0.2.1 — Separacao de paineis

A interface foi reorganizada para impedir mistura de responsabilidades:

- `/fiveemsadmin` abre **somente** configuracoes globais, integracao e diagnostico.
- `/fiveemscreator` abre o **Criador de Departamentos**: departamento, pontos, cargos, veiculos, estoque e maca/leitos.
- `/fiveemsdirector` continua sendo a **Mesa do Diretor**, separada do Admin e do Creator.
- O Admin nao mostra mais atalhos de Paciente, Monitor, CSI ou EMS OS na barra lateral.
- Admin e Criador aparecem no Launcher somente para administradores reconhecidos pelo bridge.


## V0.2.1 — Department Creator 3D Gizmo
- 3D Gizmo nativo do CFX para posicionamento visual sem dependencia externa de ox_lib/object_gizmo.
- Preview real da maca dentro da ambulancia; usa viatura compativel proxima ou cria preview local temporario.
- Gizmo separado para posicao de retirada da maca.
- Preview de paciente deitado para configurar Player/NPC sobre a maca.
- Leitos e mesas de cirurgia listados de forma organizada no Criador; cada ponto BED/SURGERY recebe um preview de paciente e transform visual.
- O transform salvo no leito respeita heading/local-space e passou a ser aplicado no runtime.
- Paciente na maca usa a animacao deitado `anim@gangops@morgue@table@ / body_search`.
- Controles: T mover, R rotacionar, L local/world, mouse esquerdo no eixo, Enter salvar, Backspace cancelar.

### Teste do 3D Gizmo
1. Abra `/fiveemscreator` e selecione o departamento.
2. Aba **Maca/Leitos**: informe o model da ambulancia e da maca.
3. Clique **3D Gizmo · Maca dentro**. Uma ambulancia real proxima do mesmo model sera usada; sem uma, o FiveEMS cria preview local.
4. Use **T** para mover, **R** para rotacionar, **L** para local/world, mouse esquerdo nos eixos, **ENTER** para salvar e **BACKSPACE** para cancelar.
5. Repita em **Posicao ao retirar** e **Paciente na maca**.
6. Para leitos: crie um ponto `bed` ou `surgery` na aba Pontos. Volte a Maca/Leitos e clique **3D Gizmo · Posicionar paciente** no leito correspondente.
7. Teste runtime: `/fiveemsstretcher`, `/fiveemsstretcherin`, `/fiveemsstretcherout`, `/fiveemspatientstretcher <id>` e, no leito, use o fluxo de atendimento para **Posicionar paciente**.


## V0.3.2 — Stretcher Ops + Department Creator UX

- Maca padrao `strykerpro` retirada pela garagem.
- Integracao obrigatoria com `ox_target` para operacao da maca.
- Menu compacto: Conduzir/Soltar, Levantar/Abaixar, Paciente, Transferir, Carregar/Descarregar e Ajustes.
- Ajustes lista extras reais do model quando a maca e um entity veicular e permite remover a maca.
- Paciente Player e NPC na maca; transferencia para leito, mesa de cirurgia ou IML.
- Perfis separados por ambulancia/aeronave: transform dentro (baixa) e fora (alta/afastada).
- Criador de Departamentos redesenhado: lista lateral, modal de criacao Nome+Tipo, status Pendente/Configurado e acoes Configurar/Editar/Excluir.
- Hospital recebe preset de cargos brasileiros/EMS, do Diretor Geral/Superintendente ao Socorrista.
- Scrollbars refinados e tela do Creator ampliada.
- Novo ponto `iml`.

## V0.3.2 — Creator Care + Target Isolation

### Criador de Departamentos
- Removido o botão lateral isolado `Criador de Departamentos`.
- O painel `Departamentos` agora ocupa diretamente a coluna esquerda do Creator.
- Abas separadas: `Pontos`, `Cargos`, `Veiculos`, `Estoque`, `Maca`, `Leitos/Outros`.
- `Pontos` agora fica apenas com pontos operacionais; leito/cirurgia/IML/outros saem dessa aba.

### Leitos/Outros
- Novo fluxo `Cadastrar leito/outro`.
- Informe nome e tipo: Leito, Mesa de cirurgia, IML ou Outro local.
- A ancora e criada na posicao atual do configurador.
- Em seguida o Creator fecha e abre automaticamente o 3D Gizmo com um NPC de preview.
- O transform salvo e usado igualmente por Player e NPC.
- Leitos/outros existentes podem ser reposicionados pelo Gizmo ou excluidos.

### Maca e ox_target
- O target da maca passou a ser registrado por MODEL (`strykerpro` e models configurados), nao apenas pela entidade criada naquele instante. Isso evita o menu FiveEMS desaparecer quando o ox_target atualiza/recarrega a entidade.
- A maca recebe StateBag replicado `fiveems:stretcher=true`.
- Extras permanecem em `Ajustes`.
- Transferencia ganhou `Outro local`, alem de Leito, Cirurgia e IML.

### Compatibilidade FivePD SP
A pasta `framework_patch/` contem patches minimos para `fivepd_sp_police`, `fivepd_sp_vehicle` e `fivepd_sp_inventory` ignorarem qualquer entidade com StateBag `fiveems:stretcher=true`. Isso impede que a Stryker Pro receba menus de moto, chassi, placa, motor, portas, inventario de veiculo etc.

Leia `framework_patch/README_PATCH.txt` antes de aplicar.


## V0.3.2 — Hotfix de controles do 3D Gizmo
- Remove a tecla T do modo de mover para evitar conflito com o chat do FiveM.
- Modo mover do gizmo agora usa a tecla G.
- Adicionado ajuste fino por teclado: setas movem o objeto/NPC e PgUp/PgDn sobem/descem.
- SHIFT aumenta o passo do ajuste fino.


## V0.3.2 — StrykerPro Behavior Fix
- Corrigida a orientacao da maca ao usar **Conduzir** com offset/rotacao apropriados para o `strykerpro`.
- **Soltar** reposiciona a maca no chao e recupera orientacao coerente.
- **Altura** nao move mais o veiculo inteiro no eixo Z; agora alterna as geometrias de pernas do modelo via extras 1/2.
- Carregar na ambulancia força estado baixo; descarregar força estado alto.
- `Ajustes > Equipamentos` agora possui Cabeceira, Prancha, Monitor, Bolsa vermelha, Bolsa azul e restauracao Padrao.
- Spawn inicial aplica os extras padrao conhecidos do StrykerPro.


## V0.3.2 — Clean Stretcher Spawn
- A StrykerPro sempre sai da garagem sem prancha, monitor, bolsa vermelha ou bolsa azul.
- O encosto/cabeceira sai abaixado (Extra 12 ligado / Extra 11 desligado, conforme o resource de referência).
- A estrutura da maca continua alta/aberta ao retirar da garagem.
- O preset pode ser alterado em `Config.Stretcher.garagePreset`.
- O menu `Ajustes > Equipamentos` ganhou `Limpar equipamentos` para retornar ao mesmo estado de garagem.


## V0.3.2 — Runtime Persistence Fix
- Blips e pontos configurados sao recarregados automaticamente do banco ao iniciar/reiniciar o FiveEMS.
- O mundo nao depende mais de abrir o Criador de Departamentos para hidratar os pontos.
- Um payload leve de runtime (`worldDepartments`) sincroniza blips e pontos persistidos para todos os clientes.
- Alteracoes em departamento/ponto/leito sao propagadas imediatamente para todos os players.
- Reiniciar somente o resource FiveEMS tambem reenvia o estado para jogadores que ja estavam conectados.


## V0.3.2 — Stretcher Gizmo + Blue/White UI
- Criador da maca reorganizado: Maca dentro, Maca fora e Paciente na maca sao editores claramente separados.
- O Gizmo de Maca dentro/fora move a StrykerPro; somente o botao de paciente cria/move o NPC de preview.
- Toda maca de preview do Gizmo nasce limpa: sem prancha, monitor ou bolsas e com encosto abaixado.
- Preview interno nasce com estrutura baixa; preview externo/paciente nasce alto.
- Paineis administrativos/Creator/Director receberam nova paleta azul, branco e azul-claro.
- Marca visual: Five em branco e EMS em azul-claro no topo.

## V0.3.2 — Garage Creator + Stretcher Staging Fix

### Gizmo da maca
- `3D Gizmo · Maca dentro` agora cria a maca de preview **visivel do lado de fora da traseira** na primeira configuracao, usando as dimensoes reais do modelo da ambulancia/aeronave. Isso evita que a maca nasca escondida dentro da carroceria.
- `3D Gizmo · Maca fora` tambem usa a traseira real do modelo e, se um transform antigo estiver dentro da carroceria, inicia em uma posicao externa segura para ser reajustado.
- As portas validas do veiculo de preview sao abertas durante a configuracao para facilitar a visualizacao do interior.
- A StrykerPro continua limpa no preview: sem prancha, monitor ou bolsas e com cabeceira abaixada.

### Aba Garagens
- Garagem foi removida da aba `Pontos` e ganhou aba propria no Criador de Departamentos.
- `Criar ponto de garagem` salva o ponto de interacao na posicao atual do admin.
- Configuracoes por garagem: nome, tipo (carro/moto/aeronave/barco/caminhao/onibus), blip, cor, escala e interacao por Marker ou Ped/NPC.
- Catalogos iniciais de blips, markers e peds com preview visual e possibilidade de editar depois.
- Fluxo de status `Pendente -> Configurar -> Configurada -> Editar`, igual ao Criador de Departamentos.
- Cada garagem aceita multiplas vagas de spawn.
- Cada vaga usa um veiculo **ghost/transparente, sem colisao** e o 3D Gizmo para salvar posicao e rotacao exatas.
- No uso operacional, a garagem tenta a primeira vaga configurada que estiver livre; se todas estiverem ocupadas, avisa o usuario.
- Blip individual e Ped/Marker da garagem persistem no banco por `fiveems_points.data`.


## V0.3.2 — Garage UX + Stretcher Controls
- Corrigido movimento fino do Gizmo: ↑/↓ = frente/tras e ←/→ = lateral usando os vetores reais da entidade.
- Adicionado giro fino por teclado: Q/E; SHIFT acelera movimento e rotacao.
- Mantidos R para modo de rotacao do DrawGizmo e mouse para arrastar os eixos.
- Ambulancia/aeronave com maca carregada agora ganha `ox_target > Retirar maca` na propria lataria.
- Registro do ox_target da maca ficou idempotente para eliminar warnings de "Replacing existing target option".
- StateBags da maca passam a ser escritos pelo servidor para compatibilidade com `sv_stateBagStrictMode`.
- Garagem operacional redesenhada em lista; cada linha possui Retirar e Guardar no mesmo campo.
- Guardar uma viatura procura o modelo correspondente proximo, reduzindo risco de apagar outro veiculo.


## V0.3.2 — Hotfix de altura da maca
- Corrige a inversao do estado visual da StrykerPro.
- Agora: dentro da ambulancia = baixa/recolhida; fora da ambulancia = alta/aberta.
- Corrigido tambem o preview do 3D Gizmo para Maca Dentro/Maca Fora.


## V0.3.2 — Garage Auto Close
- Ao clicar em `Retirar` em uma viatura, o painel da garagem fecha automaticamente após enviar a solicitação.
- `Retirar maca` também fecha a garagem automaticamente.
- `Guardar` continua mantendo o painel aberto para facilitar guardar mais de um veículo/equipamento.


## V0.3.2 — Stretcher Smooth + Target Isolation
- Catalogo operacional da garagem recebeu tema azul-escuro para reduzir brilho.
- Conducao da StrykerPro agora solicita network control antes do attachment e replica o comportamento validado do Stretcher-1.0.5.
- Gravidade/velocidade da entidade sao neutralizadas durante a conducao para reduzir tremor.
- Pegar/soltar nao muda mais a altura da maca.
- Atalho X do FiveEMS disponivel quando o resource legado Stretcher nao estiver iniciado.
- O FiveEMS avisa no F8 se detectar o resource Stretcher legado rodando junto.
- Atualizado patch da framework para ocultar placa/chassi/motor/revista da StrykerPro por StateBag OU pelo model `strykerpro`.


## V0.3.2 — Stretcher Control Fix
- Remove o atalho `X` do FiveEMS.
- `H` passa a ser a tecla padrão para **soltar** a maca durante a condução.
- A tecla de soltar não pega a maca e não altera a altura.
- A condução começa pelo `ox_target > Conduzir`.
- Corrigido o problema em que a maca tombava/deitava ao soltar.
- O FiveEMS não usa mais `SetVehicleOnGroundProperly` ao soltar ou alterar a altura da StrykerPro.
- `Levantar` e `Abaixar` agora são opções separadas no `ox_target`.
- Levantar/Abaixar alteram somente os Extras 1/2; não reposicionam nem rotacionam a entidade.
- A tecla padrão pode ser alterada em `Config.Stretcher.releaseKey`.


## V0.3.2 — Release Level Fix
- Ao pressionar `H`, a maca agora é simplesmente desacoplada no mesmo transform em que estava sendo conduzida.
- O FiveEMS não calcula mais uma nova posição de soltura na frente do ped.
- Não usa `SetVehicleOnGroundProperly` e não altera Extras 1/2 ao soltar.
- A maca mantém exatamente o estado ALTA/BAIXA escolhido antes da condução.
- Adicionado reforço do transform por 1 frame para evitar o pequeno salto causado pela reativação de colisão/gravity.
- Levantar/Abaixar também preservam posição e rotação durante a troca dos extras.


## V0.3.2 — StrykerPro Grounding Fix
- Corrige a StrykerPro saindo da garagem com rodas enterradas no piso.
- O spawn agora escolhe os Extras 1/2 primeiro e só depois posiciona a geometria correta sobre o chão.
- `Abaixar`: recolhe as pernas e move a maca inteira para baixo até as rodas continuarem apoiadas.
- `Levantar`: estende as pernas e move a maca inteira para cima mantendo as rodas apoiadas.
- A correção usa `SetVehicleOnGroundProperly` somente para obter o Z correto e restaura X/Y/rotação, evitando tombar a maca.
- Conduzir não muda mais Extras 1/2.
- O offset Z de condução passa a ser calculado pela altura real da maca naquele momento.
- `H` continua somente soltando e preservando o estado ALTA/BAIXA.


## V0.3.2 — StrykerPro Height Calibration
- A causa real era o collision/wheel contact da `strykerpro`: o GTA nao recalcula o piso pela geometria visual dos Extras 1/2.
- O FiveEMS agora usa a geometria baixa (Extra 2) apenas como referencia de piso e aplica um `highLift` calibrado para a geometria alta.
- Valor inicial: `Config.Stretcher.heightCalibration.highLift = 0.345`.
- A maca sai da garagem alta com as rodas visualmente fora do piso.
- `Levantar/Abaixar` reposicionam a entidade inteira mantendo as rodas no solo.
- `Conduzir` volta a usar o offset original do `Stretcher-1.0.5` no estado alto (`z = -0.345`), que e o que alinha corretamente com as maos do ped.
- `H` solta e recalibra somente o Z final, preservando a altura operacional e a rotacao.


## V0.3.2 — High Stretcher Calibration
- Mantém o estado BAIXO exatamente como estava, pois o teste confirmou que ele está correto no chão.
- Aumenta somente a compensação da maca ALTA de `0.345` para `0.465` m.
- A correção afeta: retirada da garagem, `Levantar` e soltura com `H` quando a maca estiver alta.
- Não altera a geometria/posição do estado BAIXO.
- Adicionado comando temporário de calibração `/fiveemsmacalift <metros>`.
  Exemplo: `/fiveemsmacalift 0.48`.
  O valor dura até o restart do resource e serve para acertar os últimos centímetros em jogo.


## V0.3.2 — Admin Stretcher Calibration
- O ajuste fino da StrykerPro saiu do comando temporário e entrou no **Painel Admin**.
- Nova seção `Ajustes finos da maca`.
- Configura e persiste:
  - compensação da maca ALTA;
  - compensação da maca BAIXA;
  - offset X/Y/Z ao conduzir;
  - rotação X/Y/Z ao conduzir.
- `Salvar e aplicar` grava os valores em `fiveems_settings`.
- A alteração é transmitida imediatamente para todos os clients conectados.
- Após restart do FiveEMS, o client solicita automaticamente a configuração persistida.
- Removido o comando temporário `/fiveemsmacalift`.


## V0.3.2 — Command Access Hardening

O FiveEMS passa a tratar comandos apenas como **fallback/debug**. O gameplay normal deve ocorrer por interfaces, pontos físicos, garagem e `ox_target`.

### Acesso público
- `/ems911`
- `/fiveemshelp` (mostra apenas o que o usuário realmente pode acessar)

### EMS em serviço
Exigem vínculo FiveEMS ativo, `on_duty=true` e, quando aplicável, a permissão do cargo:
- `/fiveems`
- `/fiveemscomputer`
- `/fiveemstablet`
- `/fiveemsexam`
- `/fiveemspatient <id>`
- `/fiveemsmonitor`

### Diretor / gestão do departamento
- `/fiveemsdirector` exige `department.manage`.

### Somente administrador
- `/fiveemsadmin`
- `/fiveemscreator`
- `/fiveemsresetpatient`
- `/fiveemsdb`
- `/fiveemstest`
- `/fiveemsframework`
- `/fiveemsseed`
- `/fiveemsnpctest`
- comandos debug da maca/paciente (`fiveemsstretcher*`, `fiveemspatientstretcher`, `fiveemspatientrelease`)

Os antigos comandos client-side de debug da maca/NPC foram removidos. Agora a autorização acontece no **servidor** antes de qualquer evento client ser executado.


## V0.3.2 — NPC Patient Persistence + Command Profiles

### NPC ferido não desaparece facilmente
A análise da framework FivePD SP mostrou que `fivepd_sp_world` remove população ambiente que não esteja protegida/mission entity. O `fivepd_sp_support` já resolve esse problema nos próprios chamados promovendo vítimas para mission entity e marcando `fivepd_sp:protected` / `fivepd_sp:supportPersistent`.

O FiveEMS agora segue o mesmo padrão:
- detecta NPC humano ferido/morto próximo;
- promove o ped localmente para mission entity;
- garante Network ID;
- o servidor aplica orphan mode 2;
- grava `fiveems:patientProtected=true`;
- grava `fivepd_sp:protected=true`, que o world manager da base já respeita;
- resolve a identidade pelo `fivepd_sp_records`;
- mantém a vítima por TTL configurável (20 minutos por padrão);
- não limpa a proteção genérica se Support/QRU/outro sistema da base ainda estiver usando a entidade.

O Admin recebeu uma seção `Persistência de pacientes NPC` com:
- ativar/desativar;
- raio de detecção;
- minutos de persistência;
- limite local.

### Comandos personalizáveis
O Admin recebeu `Comandos e números de emergência`.
Aliases podem ser separados por vírgula. Exemplo:
`192, 193, ems911`

São personalizáveis:
- emergência;
- ajuda;
- launcher;
- atendimento próximo;
- paciente por ID;
- monitor;
- computador;
- tablet;
- mesa do diretor;
- painel Admin;
- Criador de Departamentos.

Os comandos continuam respeitando a matriz de permissões da V0.2.9. Trocar o nome não altera a segurança.

Ferramentas internas de diagnóstico/debug continuam fixas e exclusivas de Admin.


## V0.3.2 — Garage Catalog Hydration Fix

Correção de regressão em que a garagem operacional podia mostrar somente a StrykerPro após restart/update, mesmo com viaturas ainda cadastradas no banco.

### Causa
A lista visual da garagem sempre usa `department.vehicles`. Entre V0.2.7b e V0.3.0 o render da lista de veículos não foi removido e não existe nenhuma query que delete `fiveems_vehicles`.

O ponto frágil estava na hidratação:
- o client abria a garagem sabendo o `pointId`;
- mas `requestBootstrap` enviava apenas `context`;
- o servidor tentava escolher o departamento somente pelo member cache;
- se o bootstrap viesse sem o departamento completo, `department.vehicles` chegava vazio/nil;
- a maca continuava aparecendo porque ela é inserida separadamente/hardcoded no catálogo.

### Correção
- `C.openUi` passa `pointId/departmentId` ao bootstrap;
- o servidor resolve o departamento pelo próprio ponto físico da garagem;
- criada hidratação dedicada `requestGarageCatalog`;
- o servidor consulta `D.getFull(departmentId)` diretamente antes de montar o catálogo;
- a NUI recebe `garageCatalog` e redesenha a garagem;
- log de diagnóstico mostra quantas viaturas foram carregadas.

Se `vehicles=0` aparecer no log, então a tabela realmente não possui viaturas para aquele departamento; caso contrário, elas obrigatoriamente devem aparecer na UI.


## V0.3.2 — F8 Flood + Bootstrap Fix

Corrigidos dois problemas independentes vistos no F8:

1. `attempt to call a nil value (global 'mergeClientTable')`
   - a função era `local` e estava declarada depois do handler `fiveems:client:bootstrap`;
   - em Lua, aquele handler resolvia o nome como global e recebia `nil`;
   - a função agora é declarada antes de qualquer handler;
   - o bootstrap volta a completar normalmente, inclusive NUI, departamento e catálogo da garagem.

2. `StateBags can't be modified from the client`
   - vinha de `client/csi.lua`, que tentava gravar `fiveemsCsiLogged` no client;
   - com `sv_stateBagStrictMode` isso é bloqueado pela framework;
   - a gravação agora acontece exclusivamente no servidor;
   - adicionada deduplicação local + servidor para impedir flood e evidência CSI duplicada.

Também foi reforçado o refresh da garagem:
- `C.uiExtra` preserva `pointId/departmentId`;
- qualquer `requestBootstrap` disparado pela NUI continua enviando o ponto da garagem;
- o catálogo dedicado é solicitado novamente quando necessário.

Não é necessário desativar `sv_stateBagStrictMode`.


## V0.3.2 — Patient Pose Reliability

A estabilização do paciente na Stryker foi refeita usando a solução homologada no FiveFD.

### Mudanças principais
- baseline de paciente novo: `X 0.00 / Y 0.10 / Z 1.12 / RotZ 180`;
- profiles ainda no antigo baseline automático `Z 0.75` são migrados em runtime;
- profiles realmente ajustados pelo usuário no 3D Gizmo são preservados;
- NPC/Player deixam de usar ragdoll enquanto estão na maca;
- colisão do ped é desativada durante o transporte para não brigar com a física da maca;
- ordem correta: `ClearPedTasksImmediately` -> `AttachEntityToEntity` -> animação supina;
- animação: `anim@gangops@morgue@table@ / body_search`;
- watchdog a cada ~700 ms;
- watchdog só refaz o attach se o vínculo realmente se perder;
- se o attach continua correto e apenas a animação parou, reinicia somente a animação;
- não existe reattach constante durante condução, parada ou entrada/saída da ambulância.

Isso evita o bug em que a vítima ficava torta, ragdollava ou "levantava" enquanto a maca era movimentada.


## V0.3.2 — MLO Patient Persistence + FiveFD Transfer Flow

Corrigido o fluxo de paciente NPC entre rua, maca e interior/MLO.

### Persistência ao entrar no hospital
Ao colocar um NPC na maca o FiveEMS agora:
- garante Network ID antes do attach;
- força migração permitida do NetID;
- marca o NPC como mission entity;
- reivindica o paciente no servidor **antes** do transporte;
- aplica `SetEntityOrphanMode(..., 2)` pelo servidor;
- mantém `fiveems:patientProtected=true`;
- mantém `fivepd_sp:protected=true`, respeitado pelo cleanup da FivePD SP;
- grava `fiveems:patientOnStretcher=<netId da maca>`;
- renova a proteção a cada poucos segundos;
- mantém o mesmo NetID durante pequenas perdas de streaming exterior/MLO;
- o watchdog tenta readquirir o mesmo NPC pelo NetID, em vez de considerar o paciente perdido.

### Transferência estilo FiveFD
Fluxo novamente:
1. parar a maca ao lado do leito;
2. `H` para soltar;
3. mirar a maca com `ox_target`;
4. opção direta **Transferir NPC/Player**;
5. o FiveEMS escolhe o leito/cirurgia/IML/outro configurado mais próximo;
6. Player usa transferência server-authoritative;
7. NPC usa o mesmo NetID protegido e é colocado no `patient_transform` salvo pelo 3D Gizmo.

A opção só aparece quando existe um destino configurado dentro do raio definido em `Config.Stretcher.patientTransport.transferRadius`.

---

# V0.4.0 — FiveFD Medical Workflow Port

Esta linha reaproveita **conceitos e comportamento homologados no projeto FiveFD**, reimplementados em Lua/NUI para a arquitetura FivePD SP do FiveEMS. Não é conversão/copiar-e-colar do C# antigo.

## 1. Patient Pose Reliability V2

A pose de transporte/hospital foi alinhada ao último perfil `SUPINE_NEUTRAL` do FiveFD:

- renderer final do FiveFD: `anim@gangops@morgue@table@ / body_search` com fase congelada;
- ragdoll desabilitado em maca/leito;
- colisão do paciente desabilitada com a superfície;
- preview do Creator e runtime usam a mesma pose;
- baseline automático da Stryker recentralizado para `X 0.00 / Y 0.00 / Z 1.12 / RotZ 180`;
- perfis automáticos antigos (`Z 0.75` e `Y 0.10 / Z 1.12`) são migrados em runtime sem sobrescrever calibrações realmente feitas pelo usuário;
- NPC morto/ferido usa **Clinical Transport Proxy**: o estado clínico lógico continua no servidor, enquanto o ped físico é temporariamente normalizado para aceitar a animação;
- ao sair de transporte, o estado físico original do NPC é restaurado quando aplicável.

### Leitos / ANCHOR

- o transform salvo pelo 3D Gizmo é autoritativo;
- paciente permanece sem colisão e congelado no leito;
- após iniciar a animação, o transform é reaplicado em uma pequena sequência para neutralizar root offset do clip;
- Player e NPC seguem a mesma regra visual.

## 2. Scene Health Audit

O Patient Workspace foi reconstruído em torno do fluxo clínico do FiveFD:

- diagrama corporal com pontos `+`;
- Cabeça, Pescoço, Tórax, Abdome, Pelve, braços e pernas;
- clicar em uma região não revela automaticamente a verdade interna;
- o profissional executa **Avaliar região**;
- somente então os achados observáveis daquela região aparecem;
- gravidade visual por cor;
- procedimentos exibidos de forma contextual por região.

## 3. XABCDE

Nova avaliação primária funcional:

- X — hemorragia exsanguinante;
- A — via aérea/coluna;
- B — respiração;
- C — circulação/perfusão;
- D — neurológico;
- E — exposição/ambiente.

Cada etapa grava resultado descritivo e timestamp no Patient State/Timeline. Completar XABCDE concede XP de avaliação uma única vez por estado clínico.

## 4. Sinais vitais aferidos

A fisiologia continua existindo no servidor, mas o Patient Workspace **não mostra os números reais automaticamente**.

O profissional precisa aferir:

- Pulso/FC;
- Frequência respiratória;
- Pressão arterial;
- SpO2;
- Temperatura;
- GCS;
- Ausculta pulmonar.

Equipamentos como esfigmomanômetro, oxímetro, termômetro e estetoscópio precisam estar na Medical Bag.

O monitor multiparamétrico continua sendo um aparelho separado e pode ler a fisiologia quando conectado.

## 5. Medical Bag

Criada bolsa médica persistente por profissional:

- conteúdo salvo em `fiveems_medical_bags`;
- equipamentos de avaliação;
- materiais de hemorragia;
- via aérea;
- imobilização;
- oxigenação;
- acesso venoso;
- manta térmica e queimaduras.

`Reabastecer` só funciona próximo ao ponto `Medicamentos/equipamentos` do próprio departamento e consome o estoque de `fiveems_supplies` server-side.

Tratamentos consumíveis são retirados da bolsa no servidor. Ferramentas duráveis permanecem na bolsa.

## 6. Tratamentos contextuais

O `+` da região passa a ser também a porta de entrada dos tratamentos:

- Compressão direta;
- Empacotamento de ferida;
- Torniquete;
- Curativo compressivo;
- Selo torácico;
- Tala;
- Colar cervical;
- OPA;
- Aspiração;
- Acesso IV;
- Manta térmica;
- Curativo de queimadura.

O servidor valida:

- permissão do cargo;
- procedimentos avançados;
- região compatível;
- item/equipamento na Medical Bag;
- paciente ainda próximo;
- efeito fisiológico e integração com `fivepd_sp_injuries` para players.

## 7. Timeline + ePCR

Avaliações, sinais vitais, tratamentos e lesões alimentam automaticamente a Timeline.

O ePCR inclui automaticamente:

- identidade canônica `fivepd_sp_records`;
- XABCDE;
- regiões examinadas;
- lesões;
- sinais vitais realmente aferidos;
- tratamentos;
- timeline;
- SAMPLA/handoff digitado pelo profissional.

Ao enviar, o encounter ativo é fechado e o XP de relatório é aplicado.

## 8. Player e NPC

O mesmo Clinical Runtime aceita referências:

- `player / serverId`;
- `npc / networkId`.

NPC usa identidade persistente de `fivepd_sp_records`; o FiveEMS não cria um segundo cadastro civil concorrente.

## Banco

Novas tabelas são criadas pelo AutoInstall existente:

- `fiveems_medical_bags`;
- `fiveems_encounters`.

Schema stamp: `0.4.0-medical-workflow-port`.


### Pose física consolidada do FiveFD
A V0.4.0 usa a solução final da linha física homologada no FiveFD:

- `body_search` para a Stryker em fase congelada;
- baseline `X 0.00 / Y 0.08 / Z 1.12 / RotZ 180`;
- NPC morto/ferido recebe proxy físico temporário (`ResurrectPed/ReviveInjuredPed`) apenas para aceitar a pose; o estado clínico real continua separado;
- ragdoll, colisão e IA não brigam com a maca/leito durante o transporte;
- leito usa exatamente o ANCHOR world-space salvo no Creator;
- no leito, o paciente permanece sem colisão e congelado;
- o transform do ANCHOR é reaplicado nos primeiros frames depois da animação para neutralizar root-offset do clip/MLO;
- o watchdog da maca só refaz attachment quando o vínculo foi realmente perdido; caso contrário, apenas mantém a fase estática.


# V0.4.3 — Scene Health Audit Restore

Correção de direção visual após comparação direta com a interface homologada do FiveFD.

- `ox_target -> Atender paciente` volta a abrir **Auditoria Clínica em Cena**, sobre o mundo real, em vez do body-map genérico dentro de uma janela.
- câmera clínica scripted acompanha o Player/NPC real sem criar um segundo paciente;
- marcadores `+` são projetados diretamente nos bones de cabeça, pescoço, tórax, abdome, pelve, braços e pernas;
- painel esquerdo restaura Itens de Tratamento, FC e Condição por Região;
- painel direito restaura Achados Atuais e Prioridade Clínica;
- topo central restaura identificação, Preparar Paciente, controles de câmera, Voltar ao Prontuário e Fechar;
- itens da Medical Bag podem ser arrastados até o `+` da região; validação e consumo continuam server-side;
- equipamentos de avaliação (estetoscópio, manguito, oxímetro e termômetro) acionam as aferições do Medical Engine;
- clicar no `+` abre apenas um popover contextual sobre a cena, sem trocar para um grande painel de body-map;
- o prontuário/XABCDE/vitais/Timeline/ePCR continuam existentes e são acessados por **Voltar ao prontuário**;
- nenhum achado oculto é revelado pelo HUD: a lista usa somente regiões já avaliadas.


## V0.4.3 — Scene Markers + Live Vitals + Monitor + Identity/Pose Reliability

### Scene Health Audit
- corrigida a projeção dos `+` para câmera clínica scripted/MLO;
- primeiro usa `GetScreenCoordFromWorldCoord`;
- se a câmera scripted não for respeitada pelo native, usa projeção manual baseada em
  `GetFinalRenderedCamCoord/Rot/Fov`;
- os marcadores continuam presos aos bones reais do NPC/Player.

### Sinais vitais
- o ECG pequeno da auditoria deixou de ser SVG estático;
- waveform é redesenhada em tempo real;
- frequência vem da fisiologia real do paciente;
- ritmo também altera o traçado.

### Monitor multiparamétrico hospitalar
- monitor virou uma interface física independente do Computer/Tablet;
- ECG, pleth, respiração e capnografia animados;
- FC, SpO₂, FR, NIBP SYS/DIA/MAP, Temp 1/2, EtCO₂, ritmo, GCS e O₂;
- beep acompanha frequência cardíaca e muda em condição de alarme;
- alarmes para FC, SpO₂, pressão e temperatura;
- PNI, congelar, silêncio, revisão, evento, menu e desconectar;
- removidos controles de desfibrilação do monitor: desfibrilador continua aparelho separado;
- `ox_target` em NPC/Player: `Conectar monitor multiparametrico`;
- aceita Player e NPC pelo mesmo Clinical Runtime.

### Identidade NPC / FivePD SP
- corrigido envio de sexo visual para `fivepd_sp_records`;
- nome masculino/feminino passa a seguir o sexo real do ped;
- idade nova passa a usar faixa visual plausível baseada no archetype;
- incluído patch opcional para tornar a regra global no Records e corrigir idade legada incompatível.

### Paciente na Stryker / leito
- corrigida regressão da V0.4.1 que aplicava a fase pinada da Stryker também no leito;
- leito volta a usar renderer independente + ANCHOR world-space exato, como no FiveFD homologado;
- Stryker mantém `body_search` pinado;
- `autoPhase` procura automaticamente, por modelo de ped, o frame com membros mais estendidos;
- Admin recebeu Auto/Manual Phase para calibração fina sem editar código.


## Hotfix visual v0.4.5a

Esta revisão corrige a regressão visual observada na v0.4.4:

- removidas completamente as faixas/máscaras pretas laterais que cobriam a visão do cenário;
- atendimento volta a ser um HUD realmente flutuante sobre o jogo;
- layout redimensionado para seguir a imagem de referência aprovada;
- marca FiveEMS ampliada no canto superior esquerdo;
- painéis com azul/ciano luminoso e vermelho somente para ações críticas, seguindo logo e banner;
- barra superior ampliada e reposicionada;
- painel de itens recebe scrollbar interno visível;
- Status do Ator mantém ordem anatômica e termina logo após Pé Direito, sem coluna vazia até o rodapé;
- `+` dos marcadores usa centralização absoluta dentro do quadrado;
- HUD nativa e radar/minimapa são desativados enquanto o contexto de atendimento está aberto e restaurados ao fechar;
- banner FiveEMS passa a ser usado também no Launcher.

Arquivos de marca utilizados pela NUI: `fiveems-banner.png`, `fiveems-wordmark.png` e `fiveems-shield.png`.


## v0.4.5a — Clinical UI Final Layout Fix

- removido `backdrop-filter` dos cards da Auditoria em Cena para evitar retângulos/colunas pretas do compositor CEF do FiveM;
- reforçada transparência absoluta do root/shell/content durante o atendimento;
- os cards laterais continuam opacos individualmente, mas não existe mais fundo de coluna;
- `+` anatômico agora fica exatamente centrado no ponto projetado do bone;
- labels deixaram de deslocar o próprio `+`;
- labels escolhem lado automaticamente e recebem anti-overlap vertical;
- proteção para labels não entrarem nos painéis esquerdo/direito;
- painel de prioridade ligeiramente compactado sem alterar a interface aprovada;
- logo recebeu pequeno ajuste de proporção/respiração visual.


## V0.4.5aa — Close Recovery + F8 Cleanup

- corrigida race condition ao fechar a Auditoria Clínica em Cena;
- NUI agora some imediatamente ao clicar em **Fechar** ou pressionar ESC;
- `C.closeUi()` libera foco NUI antes do restante da limpeza;
- recuperação forçada de scripted camera com `RenderScriptCams(false, ...)` e `ClearFocus()`;
- `SetNuiFocusKeepInput(false)` aplicado como proteção adicional;
- HUD/radar restaurados no fechamento e também no stop do resource;
- callback `close` libera primeiro a tela/input e somente depois envia `clinicalClose` ao servidor;
- comando local de emergência `/fiveemsclose` para recuperar foco caso outro resource/NUI interfira;
- registros `ox_target` de atendimento e monitor ficaram restart-safe: opções antigas do próprio FiveEMS são removidas antes de serem adicionadas;
- cleanup das opções do monitor adicionado em `onResourceStop`.

### Sobre os avisos vistos no F8
Os warnings `Replacing existing target option 'fiveems_*'` eram do FiveEMS e foram tratados nesta build.
As mensagens `script:eupmenu ERROR! SafariLand ... already exists` e os avisos de archetype/streaming
mostrados no print vêm de outros resources, não do FiveEMS.


## V0.4.5aa — Manifest + Version Sync

- corrigido `fx_version`: agora usa `cerulean`, que é uma versão válida do manifest FiveM;
- `version '0.4.5a'` continua sendo a versão do resource e não é mais confundida com `fx_version`;
- removido `lua54 'yes'` do manifest por não ser necessário nos artifacts atuais;
- versão do FiveEMS no console passa a vir automaticamente do `fxmanifest.lua`;
- `/fiveemstest` também mostra automaticamente a versão do manifest;
- bootstrap da NUI recebe `resourceVersion`, eliminando versão hardcoded na tela;
- o `DB schema` continua separado da versão do resource de propósito: ele só deve mudar quando houver mudança real de schema/migração.


## V0.4.5aa — Manifest Lock

Correção preventiva do `fxmanifest.lua`.

- `fx_version` fica travado em `cerulean`.
- somente `version` acompanha a versão do FiveEMS.
- a atualização de versão não faz mais replace global dentro do `fxmanifest.lua`.
- a validação do pacote falha se `fx_version` deixar de ser `cerulean`.

Regra de continuidade:
- `fx_version 'cerulean'` = compatibilidade do manifest FiveM;
- `version 'X.Y.Z'` = versão do resource FiveEMS.


## V0.4.5aa — Priority Panel Height Fix

- ampliado o quadro **Próxima conduta** na coluna da direita;
- aumentado o espaço inferior interno do painel;
- reposicionado o botão **Finalizar avaliação** para não ficar cortado/comido pelo limite do card.


## V0.4.5aa — Priority Panel Extra Height

- ampliado mais um pouco o card **Próxima conduta**;
- liberado overflow visível no card para evitar corte visual;
- aumentado o espaçamento do botão **Finalizar avaliação** para ele não ficar parcialmente escondido.


## V0.4.5aa — Vital Signs + Live Monitor

- corrigido ECG da Auditoria Clínica: **0 bpm agora gera linha reta**, sem pulsos falsos;
- ECG passa a aumentar/reduzir a densidade dos complexos conforme a FC real;
- PLETH segue a frequência de pulso e fica plana quando não há pulso;
- RESP segue a FR e fica plana em 0 irpm;
- capnografia segue a FR/EtCO₂ e fica em baseline quando não há ventilação;
- monitor multiparamétrico passa a mostrar o **cenário do GTA/FiveM ao vivo atrás do aparelho**;
- removido fundo/blur global da NUI no modo Monitor;
- HUD/radar do GTA são ocultados enquanto o monitor está aberto, mantendo apenas o mundo ao vivo;
- áudio do monitor reconstruído com WebAudio:
  - beep de pulso sincronizado com FC;
  - pitch do beep varia com SpO₂;
  - 0 bpm não produz beep de pulso;
  - SEM PULSO/APNEIA e alarmes de parâmetros produzem sequência de alarme separada;
  - botão Silêncio interrompe pulso e alarmes;
  - PNI possui feedback sonoro próprio;
- quando não existe pulso detectável, SpO₂ do monitor mostra `--` e PLETH fica plana;
- alarmes agora incluem `SEM PULSO` e `APNEIA`.


## V0.4.5a — Monitor Close / Stack Fix

- corrigido `Maximum call stack size exceeded` em `web/app.js`;
- `clearMonitorAudioTimers()` não chama mais a si própria recursivamente;
- ESC volta a fechar o monitor e liberar a NUI;
- **Desconectar** agora encerra o workflow do monitor e devolve o controle ao player;
- botão físico de energia do monitor também fecha o aparelho;
- limpeza de beep, alarm timer e alarm timeouts permanece centralizada e segura.

## V0.4.7a — Portable LIFEPAK + Persistent Monitor Overlay

### LIFEPAK 15 físico
- incluído o prop `stream/lifepak15.ydr` enviado para o projeto;
- novo item de estoque `lifepak15_monitor` / **LIFEPAK 15 - Monitor multiparamétrico portátil**;
- departamentos EMS/Hospital existentes recebem o item pelo auto-seed ao iniciar;
- para colocar o aparelho na rua, o servidor confirma que o player possui o item FiveEMS no `fivepd_sp_inventory`;
- tecla padrão **F7** / comando fallback `/fiveemslifepak` abre o posicionamento do aparelho;
- posicionamento: setas, PgUp/PgDn, Q/E, ENTER e BACKSPACE;
- `ox_target` no aparelho: **Conectar paciente**, **Abrir monitor**, **Abrir em overlay**, **Desconectar paciente**, **Reposicionar** e **Guardar equipamento**;
- o objeto é networked/OneSync e a associação ao paciente é statebag server-authoritative;
- outro EMS pode abrir o mesmo LIFEPAK e ler o mesmo paciente;
- se o aparelho/paciente ultrapassar o alcance configurado dos cabos, a conexão cai com aviso de eletrodos desconectados.

### Overlay persistente
- botão **Overlay** no monitor completo;
- overlay pode ser arrastado para qualquer posição da tela;
- escala ajustável entre aproximadamente 38% e 110%;
- modo compacto/expandido;
- trava de posição;
- posição, escala, modo e trava ficam salvos localmente;
- botão **Continuar jogando** libera mouse/teclado sem fechar o monitor;
- ao abrir a Auditoria Clínica depois, o overlay continua mostrando ECG/PLETH/FC/SpO₂/FR/PNI;
- ao fechar a avaliação, o sistema volta para o overlay em vez de matar a sessão do monitor;
- `/fiveemsmonitoroverlay` devolve foco ao overlay para reposicionar/reescalar quando necessário.

### Sessão clínica separada da sessão do monitor
- `monitorRequestState` agora usa um canal NUI próprio (`monitorState`), separado de `clinicalState`;
- isso impede uma avaliação clínica de sobrescrever os dados de um monitor conectado a outro paciente;
- áudio/beeps continuam ativos no overlay;
- atualização periódica do monitor não reinicia o beep a cada refresh se a assinatura fisiológica não mudou.

### Integração com inventário
A framework `fivepd_sp_inventory` expõe leitura do inventário e remoção por **nome base**, mas não um export documentado para remover especificamente um item por metadata/slot. Como os itens FiveEMS atuais usam um item-base genérico com `metadata.fiveems_item`, a V0.4.7a valida a posse exata por metadata e **reserva um único aparelho físico por player enquanto ele está colocado**, sem remover um item-base genérico que poderia apagar outro medicamento por engano. Quando a framework expuser remoção por slot/metadata, podemos transformar essa reserva em retirada física 1:1 sem risco de consumir o item errado.


## V0.4.7 — LIFEPAK Archetype Fix

A análise do `stream.zip` confirmou que o LIFEPAK não é apenas uma peça da maca.

O arquivo `ems_props.ytyp` fornecido registra um archetype próprio chamado `lifepak15`.
O `lifepak15.ydr` também existe como drawable separado de `strykergurney.ydr`.

Correções:
- `stream/ems_props.ytyp` incluído no FiveEMS;
- `data_file 'DLC_ITYP_REQUEST' 'stream/ems_props.ytyp'` adicionado ao manifest;
- `lifepak15.ydr` continua sendo o modelo físico independente;
- diagnóstico de model melhorado no F8;
- novo comando `/fiveemslifepaktest`.

O ZIP fornecido não contém `lifepak15.ytd`. O próprio YTYP aponta o texture dictionary do
LIFEPAK para `lifepak15`; portanto primeiro devemos testar com o YDR + YTYP originais.
Se o modelo carregar mas aparecer sem textura, será necessário localizar a textura correspondente
na origem do prop.


## V0.4.7 — Equipamentos de Cena + Compartimento EMS

- LIFEPAK no ox_target agora mostra **Recolher LIFEPAK 15**; a ação remove o aparelho da cena e libera o equipamento para uso novamente.
- Adicionada **Bolsa médica de atendimento** ao catálogo/estoque.
- `/fiveemsbag` posiciona a bolsa física no chão; o modelo padrão usa uma bolsa médica nativa com fallbacks configuráveis.
- ox_target da bolsa: **Abrir bolsa médica** e **Recolher bolsa**.
- A bolsa física possui conteúdo próprio/persistente e permite **Pegar 1** / **Guardar 1** item.
- Itens retirados ficam em **mãos** e passam a ser aceitos pelos procedimentos clínicos.
- Profissionais próximos a uma bolsa física também podem usar diretamente o conteúdo dela durante o atendimento.
- Novo tab **Equip. Viatura** no Criador de Departamentos.
- Cada modelo de ambulância/viatura pode ter um ponto de compartimento configurado com 3D Gizmo.
- ox_target nesse ponto abre **Compartimento EMS**.
- O compartimento permite retirar itens, LIFEPAK e bolsa médica do estoque do departamento e carregar/reabastecer a bolsa.
- Nova tabela `fiveems_vehicle_equipment_profiles`, instalada automaticamente.


## V0.4.8 — EMS Props Expansion

- Integrados os props addon `lucas2`, `lucas3`, `combicarrier2`, Ferno e Stryker enviados pelo usuario.
- LUCAS 2, LUCAS 3 e CombiCarrier agora sao equipamentos portateis server-authoritative: estoque/compartimento EMS -> colocar na cena -> recolher por `ox_target`.
- Novos itens entram automaticamente no estoque dos departamentos via seed do catalogo.
- Props Ferno/Stryker foram adicionados ao stream, mas nao substituem o `strykerpro` atual sem calibracao.
- Nenhuma mudanca estrutural de banco nesta versao; o schema permanece `0.4.7-field-equipment`.
- Consulte `docs/EMS_PROPS_MAP.md`.


## V0.4.9 — Medical Bag Carry + ox_target Flow

- A **Bolsa medica** nao salta mais direto para o chao: ao retirar no compartimento EMS/estoque ela aparece primeiro **nas maos do profissional**.
- Enquanto carrega, o prop fica anexado ao ped com animacao de transporte e bloqueio de arma/sprint/entrada em veiculo para evitar clipping.
- **G** abre o posicionamento no chao; o comando `/fiveemsbag` tambem alterna entre pegar a bolsa e posiciona-la quando ela ja esta em maos.
- `ox_target` em NPC/player humano, enquanto a bolsa esta em maos: **Colocar bolsa medica ao lado**.
- `ox_target` na bolsa no chao continua oferecendo **Abrir bolsa medica** e agora **Recolher bolsa medica** devolve o prop para as maos em vez de simplesmente faze-lo desaparecer.
- `ox_target` no ponto configurado da ambulancia ganhou **Retirar bolsa medica** alem de **Compartimento EMS**.
- Ao retirar a bolsa pelo inventario do compartimento, ela tambem passa automaticamente para as maos.
- Conteudo da bolsa e preservado ao alternar entre **mao -> chao -> mao**; a autoridade do conteudo continua server-side.
- Corrigida a notificacao de recolhimento que podia ser enviada para todos os players ao remover uma bolsa da cena.
- Nenhuma migration nova: o schema permanece `0.4.7-field-equipment`.

### Fluxo de teste rapido
1. Configure um ponto **Equip. Viatura** para a ambulancia e aproxime-se dele.
2. Mire na ambulancia com `ox_target` -> **Retirar bolsa medica**.
3. Confirme que a bolsa aparece nas maos e caminhe ate um NPC/player.
4. Mire no paciente -> **Colocar bolsa medica ao lado**, ou pressione **G** e posicione manualmente.
5. Mire na bolsa -> **Abrir bolsa medica** -> retire um item.
6. Mire novamente na bolsa -> **Recolher bolsa medica** e confirme que ela volta para as maos.

## V0.4.10 — Vehicle Equipment Hotspot Fix

- Corrige o compartimento EMS que podia nao aparecer no `ox_target` mesmo apos salvar o 3D Gizmo.
- O cliente usa cache mundial dos perfis de Equip. Viatura, nao apenas o `C.department` ativo.
- O ponto mirado pelo target precisa estar dentro do raio do hotspot salvo; a distancia do profissional tambem e validada.
- A interacao envia o `departmentId` do perfil ao servidor; admins podem testar departamentos que estao configurando.
- Debug opcional: `/fiveemscompartmentdebug`.



## V0.4.11 — Vehicle Medical Bag Mount + Handle Carry

- Bolsa medica passa a ser carregada por uma mao/pela alca usando `move_weapon@jerrycan@generic` e bone 57005.
- Ambulancias com perfil de Equip. Viatura exibem a bolsa fisicamente presa ao veiculo.
- `ox_target` diretamente na bolsa visivel: **Retirar bolsa medica**.
- Ao retirar, o prop some da viatura e aparece na mao do profissional; ao guardar novamente, reaparece no suporte.
- Bolsa colocada no chao preserva a origem da viatura e pode retornar ao mesmo fluxo depois de recolhida.
- O Compartimento EMS agora usa uma area 3D relativa ao veiculo; a bolsa nao e mais o marcador do compartimento.
- Creator separa **Centro da area do compartimento**, dimensoes X/Y/Z e **Posicao da bolsa medica**.
- Perfis 0.4.10 sao migrados de forma compativel: o ponto antigo vira inicialmente o centro do compartimento e o suporte da bolsa ate serem reposicionados.
- `/fiveemscompartmentdebug`: verde = volume do compartimento; azul = suporte da bolsa.
- Sem migration SQL nova; schema continua `0.4.7-field-equipment`.


## 0.5.0 — Tratamentos fisicos via ox_target
A linha 0.5.0 conecta a bolsa fisica ao atendimento: retire um item da bolsa, mire no paciente e use **Tratamentos EMS**. O menu abre os tratamentos disponiveis para os itens realmente em maos e depois a regiao corporal compativel. O procedimento usa `ox_lib` para progresso/animacao cancelavel; nenhum consumivel e removido antes de a acao terminar e ser validada novamente pelo servidor.

## 0.5.1 — Hospital Bed Chart + Bed Target Fix
- Paciente em leito passa a ser resolvido pelo `fiveems:carePointId`, evitando abrir o próprio profissional.
- Leitos têm uma zona própria de `ox_target` sobre a posição do paciente, independente da colisão do ped congelado.
- `ox_target` no leito: **Abrir ficha do leito**, **Atender paciente no leito** e **Tratamentos EMS**.
- O marker `E` no pé do leito abre uma ficha/prancheta hospitalar, sem iniciar a câmera da Auditoria Clínica.
- Ficha com identificação, sinais já aferidos, evolução, condutas, exames à beira-leito, enfermagem e histórico/ePCR.
- Player e NPC mantêm associação server-authoritative com o leito durante transferência/recolocação.
