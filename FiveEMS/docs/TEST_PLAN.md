# FiveEMS — Plano de testes V0.4.0 FiveFD Medical Workflow Port

1. `restart fivepd_sp_database`, confirme a base pronta, depois `restart FiveEMS`.
2. `/fiveemsframework`: todos os resources obrigatorios devem aparecer `started`; Character ID, Fixed ID, Records, RG, tipo sanguineo e Admin devem ser exibidos no F8.
3. `/fiveemstest`: banco e integracao devem estar OK.
4. `/fiveemsadmin`: crie/abra um departamento, atribua seu personagem pelo Server ID e teste duty. O membro deve ficar vinculado a `char:<character_id>`.
5. Estoque: retire um item. Ele deve entrar no `fivepd_sp_inventory` usando item generico + metadata FiveEMS.
6. Dois players: `/fiveemsexam` no paciente. Confirme nome/RG/tipo sanguineo vindo de `fivepd_sp_records`.
7. Cause ferimento e confirme que `fivepd_sp_injuries` e FiveEMS continuam funcionando juntos. Aplique tratamento e verifique melhora fisica.
8. Deixe o paciente em estado `downed`; abra atendimento FiveEMS e confira `fivepd_sp:medicalClaimed=true`. Feche a UI e confirme liberacao.
9. Simule PCR/ritmo chocavel e defibrilacao bem-sucedida; confirme retorno do `fivepd_sp_death` para `alive`.
10. `/fiveemsnpctest` perto de um NPC networked; o F8 deve mostrar Record ID, nome, RG, sexo, idade e tipo sanguineo persistentes.

Se qualquer etapa falhar, envie o console/F8 e o passo exato.

- `/fiveemsadmin`: confirmar que mostra somente configuracoes globais/bridge, sem departamentos, pontos, cargos, frota, estoque, paciente, monitor ou CSI.
- `/fiveemscreator`: confirmar abas Departamento/Pontos/Cargos/Veiculos/Estoque/Maca-Leitos.


## V0.3.2 — testes especificos
1. `/fiveemscreator`: criar departamento pelo modal (Nome + Tipo). Confirmar status Pendente.
2. Clicar Configurar, salvar geral/concluir e confirmar Configurar desativado + Editar ativo.
3. Em hospital, conferir cargos pre-carregados brasileiros.
4. Criar pontos BED, SURGERY e IML e ajustar paciente por 3D Gizmo.
5. Configurar `ambulance`: maca dentro baixa e fora alta/afastada.
6. Na garagem, retirar a `strykerpro`.
7. No ox_target da maca: Conduzir, Soltar, Abaixar/Levantar, Player/NPC, Transferir e Ajustes/Extras.
8. Carregar na ambulancia: deve entrar baixa. Descarregar: deve sair alta no transform externo.
9. Transferir Player e NPC para BED/SURGERY/IML.

## V0.3.2 — Creator / Leitos / ox_target
1. `/fiveemscreator`: confirmar que nao existe mais a barra lateral externa com `Criador de Departamentos`.
2. Confirmar que `Departamentos` esta na coluna esquerda principal.
3. Abrir um departamento e verificar abas separadas `Maca` e `Leitos/Outros`.
4. Em `Leitos/Outros`, cadastrar `Leito 01`, confirmar que o NPC de preview abre automaticamente no 3D Gizmo e salvar.
5. Reabrir o Creator e confirmar que `Leito 01` aparece com o transform salvo.
6. Retirar a `strykerpro` na garagem e abrir ox_target varias vezes; o menu FiveEMS deve continuar aparecendo.
7. Aplicar o patch de framework e confirmar que a maca NAO mostra `Verificar chassi`, `Verificar placa da moto`, `Verificar motor`, portas/vidros ou revista de veiculo.
8. Testar `Transferir > Outro local` com um destino tipo `other` configurado.


## V0.3.2 — Garagens
1. `/fiveemscreator` -> selecione o departamento -> `Garagens`.
2. Confirme que `Garagem` nao aparece mais em `Pontos`.
3. Fique no local do atendimento e crie `Garagem Principal` com Marker; reinicie FiveEMS e confirme persistencia do marker/blip.
4. Crie outra garagem com Ped/NPC e confirme que o ped reaparece apos restart.
5. Clique `Configurar` e adicione uma vaga com veiculo ghost + 3D Gizmo.
6. Salve, volte para a lista e confirme `Configurar` desativado e `Editar` ativado.
7. Abra a garagem em jogo, retire um veiculo e confirme que nasce na vaga configurada.
8. Ocupe a vaga e tente retirar outro veiculo; se nao houver outra vaga livre, deve aparecer aviso.
9. Teste editar e excluir vaga/garagem.
10. Em `Maca`, abra `3D Gizmo · Maca dentro`; a maca deve nascer visivel atras da ambulancia para ser arrastada ao interior.
11. Abra `3D Gizmo · Maca fora`; o preview deve iniciar fora da carroceria quando o transform antigo estiver invalido/interior.


### V0.3.2 — F8 / StateBag / bootstrap
1. `restart FiveEMS`.
2. F8 não deve mostrar `mergeClientTable nil`.
3. F8 não deve floodar `StateBags can't be modified from the client` vindo do FiveEMS.
4. Abra a garagem diretamente, sem abrir Creator antes.
5. Confirme no console `[FiveEMS][Garage] ... vehicles=N`.
6. Viaturas cadastradas devem aparecer junto da maca.
7. Mate um NPC próximo e aguarde alguns segundos: deve ser criada no máximo uma evidência CSI para a entidade, sem flood de StateBag.


### V0.3.2 — Paciente na maca
1. Derrube/lesione um NPC sem matá-lo.
2. `ox_target > Paciente > NPC próximo`.
3. O NPC deve ficar supino, alinhado no colchão, sem ragdoll.
4. `Conduzir` a maca por pelo menos 20 segundos.
5. Parar e voltar a conduzir: a vítima não pode levantar nem ficar torta.
6. Carregar a maca na ambulância e retirar novamente.
7. A vítima deve manter a mesma pose.
8. Soltar/transferir: colisão/ragdoll do ped devem ser restaurados.
9. Repetir com um Player.
10. Se precisar de ajuste milimétrico, usar Creator → Maca → Paciente na maca → 3D Gizmo.


### V0.3.2 — MLO + transferência maca -> leito
1. Ferir um NPC e colocar na maca.
2. Confirmar que o NPC continua visível ao atravessar as portas do MLO.
3. Entrar totalmente no interior do hospital e aguardar 10 segundos.
4. O NPC deve continuar sendo o mesmo ped/NetID, ainda deitado na maca.
5. Parar a maca ao lado de um leito cadastrado.
6. Pressionar `H`.
7. Mirar a maca com `ox_target`.
8. Deve aparecer **Transferir NPC/Player**.
9. Selecionar: o NPC deve ir para o `patient_transform` daquele leito.
10. Repetir com Player.
11. Repetir com cirurgia e IML se cadastrados.

## V0.4.0 — Medical Workflow Port

### A. Pose física
1. Colocar NPC ferido na Stryker.
2. Confirmar pose supina, pernas estendidas e sem ragdoll.
3. Conduzir, parar e conduzir novamente.
4. Entrar/sair do MLO.
5. Transferir para Leito 01.
6. Confirmar que o transform salvo pelo Gizmo permanece exato e sem colisão empurrando o ped.
7. Repetir com Player.

### B. Scene Health Audit
1. `ox_target -> Atender paciente`.
2. Abrir `✚ Auditoria`.
3. Clicar no `+` de uma região lesionada.
4. Antes de avaliar, achados não devem estar revelados.
5. `Avaliar região` deve registrar e mostrar achados.
6. Aplicar um tratamento compatível e confirmar Timeline + consumo da bolsa.

### C. XABCDE
1. Avaliar X/A/B/C/D/E.
2. Cada card deve registrar finding e horário.
3. Completar todos deve gerar XP uma vez.

### D. Vitals
1. Sem aferição, valores no Patient Workspace ficam `--`.
2. FC/FR/GCS podem ser avaliados clinicamente.
3. PA/SpO2/temperatura/ausculta exigem equipamento na bolsa.
4. Reaferição deve atualizar o snapshot observado.

### E. Medical Bag
1. Ir ao ponto `Medicamentos/equipamentos`.
2. Abrir Patient Workspace -> Bolsa médica -> Reabastecer.
3. Conferir retirada do estoque do departamento.
4. Aplicar consumível e conferir redução da bolsa.

### F. ePCR
1. Fazer avaliação + sinais + tratamentos.
2. Conferir Timeline automática.
3. Enviar ePCR.
4. Confirmar relatório no banco, encounter fechado e XP recebido.


### V0.4.3 — Scene / Monitor / Identity / Pose

1. Reiniciar `FiveEMS` e abrir F8: não deve haver flood/erro novo.
2. Atender NPC/Player -> Scene Health Audit:
   - confirmar `+` sobre cabeça/pescoço/tórax/abdome/pelve/braços/pernas;
   - girar câmera clínica e confirmar que os `+` acompanham o corpo.
3. Confirmar ECG pequeno animando continuamente e cadência compatível com FC.
4. `ox_target -> Conectar monitor multiparametrico`:
   - testar NPC;
   - testar Player;
   - confirmar ECG/Pleth/RESP/CO₂;
   - testar PNI, Congelar/Retomar e Silêncio;
   - desconectar e confirmar retorno a Standby.
5. Identidade:
   - NPC masculino novo -> nome masculino;
   - NPC feminino novo -> nome feminino;
   - ped `*_y_*` -> idade jovem;
   - ped `*_o_*` -> idade alta;
   - consultar o mesmo NPC novamente -> mesma identidade.
6. Stryker:
   - colocar NPC e observar pernas/braços;
   - conduzir/parar/reconduzir;
   - Admin -> Ajustes finos da maca -> testar Auto Phase;
   - se necessário, desligar Auto e ajustar Phase manualmente.
7. Leito:
   - transferir da Stryker para ANCHOR já salvo;
   - confirmar posição/rotação exata;
   - confirmar que o leito não herdou a fase pinada da Stryker.


### V0.4.5aa — Close Recovery

1. Abrir `Atender paciente` via ox_target.
2. Confirmar câmera clínica + NUI.
3. Clicar **Fechar**:
   - NUI deve desaparecer imediatamente;
   - câmera volta ao gameplay;
   - mouse deixa de ficar preso;
   - personagem volta a responder a WASD/mouse;
   - HUD/radar voltam normalmente.
4. Repetir usando `ESC`.
5. Reabrir e fechar pelo menos 5 vezes sem restart do resource.
6. Dar `restart FiveEMS` e confirmar ausência de warnings:
   - `Replacing existing target option 'fiveems_clinical_*'`;
   - `Replacing existing target option 'fiveems_monitor_*'`.
7. Se qualquer outro resource capturar NUI por acidente, testar `/fiveemsclose` como recuperação.


### V0.4.5aa — Vital Monitor

1. Paciente com FC > 0:
   - ECG deve pulsar na velocidade da FC;
   - PLETH deve acompanhar o pulso;
   - beep deve acompanhar a FC.
2. Alterar/usar paciente com FC baixa e alta:
   - quantidade de complexos ECG por tempo deve diminuir/aumentar.
3. Paciente com FC = 0:
   - ECG deve ser linha reta;
   - PLETH deve ser linha reta;
   - não deve haver beep de pulso;
   - deve existir alarme `SEM PULSO`.
4. Paciente com FR = 0:
   - RESP e CO₂ devem ficar em baseline;
   - deve existir alarme `APNEIA`.
5. Conectar monitor via ox_target:
   - cenário deve continuar visível e atualizado atrás do aparelho;
   - não deve existir fundo preto/blur global;
   - HUD/radar do GTA devem permanecer ocultos durante o uso.
6. Testar `Silêncio`: todos os tons do monitor devem parar.
7. Reativar som e testar PNI: deve haver feedback sonoro.
8. Desconectar/fechar e confirmar retorno do HUD/radar e controles.


### V0.4.5a — Monitor Close Regression

1. Conectar o monitor em NPC/Player.
2. Confirmar que não aparece `Maximum call stack size exceeded` no F8.
3. Pressionar ESC:
   - monitor some;
   - mouse/teclado voltam;
   - cenário volta a responder.
4. Abrir novamente e clicar **Desconectar**:
   - monitor fecha completamente;
   - paciente é liberado;
   - NUI focus é removido.
5. Abrir novamente e usar o botão físico ⏻:
   - mesmo resultado.
6. Repetir o ciclo abrir/fechar 10 vezes.


### V0.4.7a — Portable LIFEPAK / Overlay

1. Abrir o estoque do hospital e confirmar **LIFEPAK 15 - Monitor multiparamétrico portátil**.
2. Retirar 1 unidade para o inventário.
3. Pressionar F7 (ou `/fiveemslifepak`):
   - sem item: servidor deve negar;
   - com item: ghost do `lifepak15` deve aparecer para posicionamento.
4. Colocar o prop com ENTER e confirmar sincronização para um segundo player.
5. ox_target no aparelho -> **Conectar paciente**.
6. Testar NPC e Player.
7. Abrir monitor completo e confirmar ondas/beeps.
8. Clicar **Overlay**:
   - arrastar para outro canto;
   - Scale - / Scale +;
   - compacto/expandido;
   - travar/destravar posição;
   - clicar **Continuar jogando** e recuperar gameplay.
9. Com overlay ativo, abrir `Atender paciente` no mesmo paciente:
   - Auditoria Clínica deve abrir;
   - monitor deve continuar atualizando por cima;
   - beep deve continuar funcionando.
10. Fechar a Auditoria Clínica:
   - avaliação deve fechar;
   - overlay deve permanecer.
11. Mover paciente a mais de `maxCableDistance` do prop:
   - associação deve cair;
   - mensagem de eletrodos/cabos desconectados;
   - overlay deve encerrar a sessão.
12. Testar **Reposicionar** e **Guardar equipamento** pelo ox_target.
13. Segundo EMS: abrir o mesmo monitor e confirmar que lê o mesmo paciente.
14. Reiniciar FiveEMS e confirmar ausência de flood/warnings próprios no F8.


### V0.4.7 — Equipamentos de Cena

1. Reiniciar FiveEMS e confirmar `DB schema 0.4.7-field-equipment`.
2. No estoque, confirmar **Bolsa médica de atendimento**.
3. Retirar uma bolsa e usar `/fiveemsbag`.
4. Posicionar no chão e testar ox_target: **Abrir bolsa médica** e **Recolher bolsa**.
5. Na tela da bolsa, testar **Pegar 1** e **Guardar 1**.
6. Atender paciente próximo da bolsa e confirmar que tratamentos reconhecem itens em mãos/bolsa física.
7. LIFEPAK: colocar no chão e testar **Recolher LIFEPAK 15**.
8. Criador -> **Equip. Viatura** -> escolher `ambulance` -> posicionar ponto com 3D Gizmo.
9. Reiniciar FiveEMS; retirar uma ambulance e confirmar que o ponto continua persistido.
10. No ponto configurado, ox_target -> **Compartimento EMS**.
11. Testar `Pegar 1`, `+ Bolsa` e `Reabastecer bolsa`.


### V0.4.8 — EMS Props Expansion

1. Reiniciar FiveEMS e confirmar resource `0.4.8` e DB schema ainda `0.4.7-field-equipment`.
2. Abrir estoque e confirmar LUCAS 2, LUCAS 3 e CombiCarrier II.
3. Retirar LUCAS 2 e usar `/fiveemslucas2`; posicionar com ENTER.
4. Mirar no LUCAS 2 com ox_target e confirmar **Recolher LUCAS 2 - Compressor toracico**.
5. Repetir com `/fiveemslucas3` e `/fiveemscombi`.
6. Sem o item correspondente no inventario, o servidor deve negar o deploy.
7. Tentar colocar duas unidades do mesmo tipo pelo mesmo player; a segunda deve ser negada.
8. Configurar/usar Compartimento EMS na ambulancia e confirmar que os tres novos itens aparecem no estoque e podem ser retirados.
9. Rodar `/fiveemsequiptest` e confirmar no F8 que LUCAS/Combi/Ferno/Stryker aparecem com `CD=true`, `Valid=true`, `Loaded=true`.
10. Nao trocar o modelo da maca operacional ainda; os props Ferno/Stryker desta build sao para calibracao controlada.


## V0.4.9 — Bolsa medica carregavel

1. **Retirada direta da ambulancia**
   - Configurar `Equip. Viatura` para o modelo testado.
   - `ox_target` no ponto -> `Retirar bolsa medica`.
   - Esperado: estoque desconta 1 apenas na primeira aquisicao; prop aparece nas maos; nao cria bolsa duplicada.

2. **Transporte**
   - Caminhar com a bolsa.
   - Esperado: animacao permanece ativa, prop acompanha o ped, tiro/mira/sprint/entrada em veiculo ficam bloqueados durante o transporte.

3. **Drop manual**
   - Pressionar G.
   - Ajustar com setas/PgUp/PgDn/Q/E e confirmar com ENTER.
   - Esperado: prop carregado some das maos e surge no chao, networked, com ox_target. BACKSPACE deve devolver a bolsa para as maos.

4. **Drop ao lado do paciente**
   - Com a bolsa nas maos, usar `ox_target` em NPC/player humano -> `Colocar bolsa medica ao lado`.
   - Esperado: bolsa e posicionada lateralmente e fica utilizavel.

5. **Conteudo**
   - `ox_target` na bolsa -> `Abrir bolsa medica`.
   - Pegar 1 item e aplicar em paciente.
   - Esperado: item passa para `em maos` e a quantidade da bolsa diminui/persiste.

6. **Recolher**
   - `ox_target` na bolsa -> `Recolher bolsa medica`.
   - Esperado: objeto sai do chao, volta para as maos e conserva exatamente o conteudo anterior.

7. **Duplicacao/seguranca**
   - Tentar retirar outra bolsa da ambulancia enquanto ja carrega uma ou enquanto sua bolsa esta no chao.
   - Esperado: operacao bloqueada sem descontar estoque adicional.

8. **Multiplayer**
   - Player A coloca bolsa no chao; Player B abre e retira/devolve item.
   - Player B nao deve receber a opcao de recolher a bolsa; Player A recolhe.
   - Esperado: objeto e conteudo permanecem sincronizados e nenhum outro player recebe notificacao global indevida.

## V0.4.10 — Hotspot do Compartimento EMS

1. Reiniciar o FiveEMS e confirmar `version 0.4.10`; o DB schema continua `0.4.7-field-equipment`.
2. No Creator -> **Equip. Viatura**, escolher o modelo exato e salvar o hotspot com o 3D Gizmo.
3. Fechar o Creator, aproximar-se do hotspot e mirar exatamente na regiao configurada.
   - Esperado: `Retirar bolsa medica` e `Compartimento EMS` aparecem junto das demais opcoes do ox_target.
4. Mirar longe do hotspot, ainda na mesma ambulancia.
   - Esperado: as opcoes FiveEMS desaparecem; a interacao fica presa ao compartimento salvo.
5. Selecionar `Retirar bolsa medica`.
   - Esperado: bolsa aparece nas maos e o estoque correto do departamento e usado.
6. Abrir `Compartimento EMS`, retirar um item, usar `+ Bolsa`, `Reabastecer bolsa` e `Atualizar`.
   - Esperado: todas as operacoes permanecem no mesmo `departmentId` do hotspot.
7. Como admin, testar um departamento configurado mesmo sem estar vinculado a ele.
   - Esperado: hotspot aparece e abre o estoque do departamento selecionado.
8. Se a opcao nao aparecer, rodar `/fiveemscompartmentdebug` ao lado da viatura.
   - Esperado: F8 mostra modelo/hash/perfis e marcadores verdes aparecem por 15 segundos no(s) hotspot(s).



## V0.4.11 — Bolsa montada na viatura + area de compartimento

1. Reiniciar FiveEMS e confirmar `version 0.4.11`; DB schema continua `0.4.7-field-equipment`.
2. Usar uma ambulancia que ja possuia perfil 0.4.10. Confirmar que a bolsa aparece fisicamente no ponto antigo.
3. Abrir Creator > Equip. Viatura. Ajustar **3D Gizmo · Posicao da bolsa** para o suporte/armario desejado.
4. Ajustar **3D Gizmo · Centro da area** e dimensoes X/Y/Z do Compartimento EMS.
5. Mirar diretamente na bolsa com ox_target: deve aparecer **Retirar bolsa medica**.
6. Retirar. Confirmar que a bolsa some da viatura e aparece na mao direita pela alca, ao lado do corpo.
7. Caminhar ate um paciente e usar ox_target > **Colocar bolsa medica ao lado**; abrir a bolsa e retirar um item.
8. Recolher a bolsa do chao. Confirmar que volta para a mao.
9. Voltar a ambulancia, mirar no suporte vazio e usar **Guardar bolsa medica na viatura**. Confirmar que some da mao e reaparece no suporte.
10. Mirar dentro da area configurada, longe da bolsa: deve aparecer **Compartimento EMS** para medicamentos/equipamentos gerais.
11. Rodar `/fiveemscompartmentdebug`: volume verde = compartimento; marcador azul = suporte da bolsa.
12. Repetir com dois players: ao retirar a bolsa por um deles, ela deve desaparecer visualmente para ambos.

### V0.4.12 — Bolsa montada / ox_target
1. Com a bolsa guardada e visivel na ambulancia, mire diretamente nela com ox_target.
2. Confirmar que `Retirar bolsa medica` aparece apenas perto do suporte configurado.
3. Retirar: prop deve sumir da viatura e aparecer na mao.
4. Voltar com a bolsa na mao e mirar no suporte vazio: `Guardar bolsa medica na viatura`.
5. Confirmar que `Compartimento EMS` continua funcionando na area 3D separada.



# V0.5.0 — Physical Treatment Workflow
1. Coloque a bolsa ao lado do paciente e abra com ox_target.
2. Retire `Curativo compressivo`; confirme `Em maos 1`.
3. Mire no paciente -> `Tratamentos EMS` -> `Curativo compressivo` -> escolha a regiao lesionada.
4. Confirme progressCircle/animacao. Cancele uma vez: o item deve continuar em maos e a lesao nao deve ser marcada como tratada.
5. Repita e conclua: o item deve sair das maos, a timeline deve registrar o tratamento e o sangramento deve cair.
6. Tente tratar regiao sem lesao com torniquete/curativo: servidor deve recusar sem consumir o item.
7. Retire aspirador (duravel), aplique em via aerea e confirme que continua em maos.
8. Aplique tala em membro lesionado e confirme reducao de dor no estado clinico.
9. Aplique colar cervical e confirme `spinalPrecautions=true` no estado persistido.
10. Obtenha acesso venoso e confirme `ivAccess` registrado.
11. Teste em Player e NPC; em ambos, afastar-se durante/antes de concluir deve impedir aplicacao server-side.
12. Reinicie FiveEMS e confirme que ox_target `Atender paciente` e `Tratamentos EMS` registram uma unica vez, sem warnings duplicados.

# V0.5.1 — Hospital Bed Chart + Bed Target Fix
1. Transfira um NPC da maca para um leito configurado.
2. Mire no corpo com `ox_target`; devem aparecer **Abrir ficha do leito**, **Atender paciente no leito** e **Tratamentos EMS**.
3. Pressione `E` no marker do pé do mesmo leito; a ficha deve mostrar a identidade do NPC do leito, nunca a do profissional.
4. Feche a ficha e confirme que nenhuma scripted camera ficou ativa.
5. Abra **Atender paciente no leito** e valide que a Auditoria Clínica usa o paciente do leito.
6. Pegue um curativo na bolsa, use `ox_target -> Tratamentos EMS` no leito e conclua um procedimento.
7. Repita com Player transferido para o leito; confirme identificação correta e opções de target.
8. Retire/solte o paciente do leito e confirme que o target deixa de oferecer ficha/tratamento quando o leito estiver vazio.
9. Teste dois leitos ocupados simultaneamente e confirme que cada marker `E` abre o paciente correspondente.
