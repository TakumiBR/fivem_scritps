# FiveEMS — Contexto atual

Versao atual: **0.5.1 — Hospital Bed Chart + Bed Target Fix**.

O FiveEMS deixou de tratar license/ox_inventory como fundacao e agora usa a framework FivePD SP: `character_id` do core, identidade de `records`, inventario nativo, ferimentos fisicos de `injuries`, death state/medical claim, admin e UI.

A persistencia SQL do FiveEMS foi mantida nesta fase para reduzir risco; `identifier` agora recebe `char:<character_id>`. Vinculos antigos por license sao migrados automaticamente quando possivel.

Pendencias da proxima fase: itens EMS dedicados no catalogo do inventario, bridge hospital/support, PC/DHPP/CSI e fluxo completo de NPC Medical Actor.


## V0.3.2
- Paciente NPC agora é reivindicado/protegido server-side imediatamente ao entrar na maca.
- Continuidade por Network ID durante transição para MLO.
- Watchdog readquire o mesmo NPC caso o handle client desapareça temporariamente.
- `ox_target` da maca voltou ao fluxo FiveFD: `Transferir NPC/Player` direto para o ponto assistencial mais próximo.


## V0.4.8
- `emsprops.zip` integrado ao resource.
- LIFEPAK/YTYP conferidos como identicos aos ja usados na V0.4.7.
- LUCAS 2, LUCAS 3 e CombiCarrier agora possuem fluxo fisico de cena com estoque/ambulancia e ox_target para recolher.
- Modelos Ferno/Stryker adicionais estao streamados para futura calibracao sem substituir a maca operacional atual.
- Bolsa medica segue com prop nativo, pois o pack recebido nao contem modelo de bolsa.


## V0.4.9
- Bolsa medica agora possui estado fisico **carregando nas maos** antes de ser colocada no chao.
- Retirada direta pelo `ox_target` do compartimento EMS da ambulancia.
- Pode ser colocada ao lado de NPC/player via `ox_target` ou manualmente com G + editor de posicionamento.
- Recolher a bolsa no chao devolve para as maos e preserva o conteudo server-side.
- O painel atual da bolsa foi mantido nesta build para priorizar o fluxo fisico; redesign visual fica para uma evolucao posterior.

## V0.4.10
- Corrigido o `ox_target` do compartimento EMS da viatura: o cliente nao depende mais apenas de `C.department` para localizar o perfil salvo.
- Perfis de equipamento habilitados agora sao sincronizados no cache mundial e atualizados imediatamente apos salvar pelo Creator.
- O hotspot valida proximidade do profissional e a regiao realmente mirada pelo `ox_target`, com raio configuravel.
- Admins podem testar um hotspot de qualquer departamento configurado; membros comuns continuam limitados ao proprio departamento no servidor.
- O `departmentId` do hotspot acompanha abertura/retirada/reabastecimento para evitar usar estoque do departamento errado.
- Adicionado `/fiveemscompartmentdebug` para marcar hotspots por 15s e imprimir diagnostico no F8.



## V0.4.11

- Carry da bolsa alterado de duas maos/box carry para uma mao pela alca.
- Bolsa medica virou equipamento fisico montado na ambulancia: visivel quando guardada, some ao retirar e reaparece ao devolver.
- Estado de ocupacao do suporte replica pela state bag da viatura.
- Origem da bolsa acompanha mao -> chao -> mao para permitir devolucao correta.
- Compartimento EMS deixou de usar a mala como referencia e passou para volume 3D relativo ao veiculo.
- Creator agora separa area do compartimento e suporte/posicao visual da bolsa.

## V0.4.12 — Vehicle Bag ox_target Fix
- Corrigida regressao da V0.4.11 em que a bolsa montada na ambulancia ficava visivel, mas o ox_target nao conseguia mirar de forma confiavel no prop local sem colisao.
- `Retirar bolsa medica` voltou a ser uma opcao global da viatura, limitada ao pequeno raio configurado ao redor do suporte fisico da bolsa.
- A bolsa visual continua sem colisao para nao interferir com a ambulancia.
- Compartimento EMS 3D da V0.4.11 foi preservado sem alteracoes.



## V0.5.0 — Physical Treatment Workflow
- Itens retirados da bolsa sao sincronizados server-authoritative como **itens em maos**.
- `ox_target` em Player/NPC ganhou submenu **Tratamentos EMS**.
- Cada tratamento so aparece se o material necessario estiver em maos; compressao direta continua sem item.
- O tratamento seleciona a regiao corporal pelo proprio menu do ox_target.
- Procedimentos possuem duracao e animacao via `ox_lib` progressCircle; podem ser cancelados sem consumir item.
- Consumiveis sao descontados somente no servidor, ao fim do procedimento, depois de nova validacao de distancia, permissao, regiao, lesao e item.
- Equipamentos duraveis (ex.: aspirador) permanecem em maos apos o uso.
- Colar cervical registra precaucao espinhal, tala reduz dor e acesso venoso passa a existir no estado clinico real.
- O painel antigo continua disponivel como fallback/avaliacao detalhada; o novo fluxo fisico nao depende de abrir inventario grande para aplicar o tratamento.

## V0.5.1 — Hospital Bed Chart + Bed Target Fix
- Corrigido: paciente congelado/sem colisão no leito não era selecionável pelo raycast do `ox_target`.
- Agora cada leito registra uma sphere zone do `ox_target` sobre a transformação real do paciente.
- O marker `E` não abre mais `patient` sem target. Ele resolve o ocupante do leito e abre `bed_chart`.
- Player em leito recebe state bag `fiveems:carePointId`; NPC já usava esse state bag. Isso evita confundir o profissional com o paciente.
- Nova ficha/prancheta hospitalar: Resumo, Evolução, Prescrição/Condutas, Exames, Enfermagem e Histórico.
- Tratamentos podem ser iniciados no paciente de leito por `ox_target -> Tratamentos EMS`, mesmo com colisão desativada.
- A Auditoria Clínica completa continua disponível por `Atender paciente no leito`.
