# FiveEMS — Roadmap apos integracao da framework

## V0.3.2 — Creator Care + Target Isolation (atual)
- Core/character_id.
- Records Player/NPC.
- Inventory nativo.
- Injuries bridge.
- Death claim/revive bridge.
- Admin/UI nativos.

## V0.2.1 — Inventory & Medical Actions
- Cadastrar itens EMS dedicados no `fivepd_sp_inventory`.
- Consumo real por tratamento, medicacao e equipamento.
- Metadados/lotes/quantidade.

## V0.3.2 — Hospital & Support Bridge
- Recepcao hospitalar deixa de curar instantaneamente quando FiveEMS estiver ativo.
- Admissao/leito/tratamento/alta FiveEMS.
- Ambulancia NPC como fallback quando nao houver EMS player em duty.

## V0.3.2 — CSI / PC / DHPP
- Compartilhar evidencias, cadeia de custodia, cenas medico-legais e autopsia.

## V0.3.2 — NPC Medical Actor
- Atendimento completo a NPC usando `ObterOuCriarNPC()` e OneSync.


- **V0.4.7a** — LIFEPAK 15 físico + overlay persistente + monitor simultâneo à avaliação clínica.


## V0.4.8 — EMS Props Expansion
- Integrar props EMS adicionais.
- LUCAS 2/3 e CombiCarrier como equipamentos fisicos portateis.
- Disponibilizar Ferno/Stryker para calibracao sem regressao da maca atual.

## Proxima evolucao
- Calibrar Ferno/Stryker (normal/baixada/sentada) no sistema operacional de maca.
- Aplicacao do LUCAS diretamente ao paciente + ciclo de compressao/animacao e integracao com PCR.
- Modelo addon dedicado para a bolsa medica quando fornecido.


## V0.4.9 — Medical Bag Carry + ox_target Flow
- Bolsa na mao ao retirar de estoque/ambulancia.
- Drop manual e colocacao ao lado do paciente via ox_target.
- Recolhimento volta para a mao sem perder conteudo.
- Atalho direto no compartimento EMS da viatura para retirar a bolsa.


## V0.4.10 — Vehicle Equipment Hotspot Fix
- Corrigir visibilidade do `Retirar bolsa medica` e `Compartimento EMS` no ox_target.
- Sincronizar perfis de Equip. Viatura independentemente da NUI/departamento ativo no cliente.
- Restringir a interacao ao hotspot configurado usando coordenada de mira + distancia do player.
- Permitir teste administrativo do perfil sem trocar de vinculo de departamento.
- Adicionar comando de diagnostico visual/F8 para hotspots.

## Proximas evolucoes sugeridas
- Calibrar offset/animacao da bolsa com feedback in-game e substituir o prop nativo por addon quando fornecido.
- Redesign compacto do conteudo da bolsa com icones/imagens, sem perder a interacao fisica por ox_target.
- Props/animacoes de itens individuais retirados da bolsa (BVM, colar, estetoscopio etc.) quando houver modelos adequados.
- Aplicacao funcional do LUCAS 2/3 ao paciente e integracao com PCR/LIFEPAK.


## V0.4.11 — Vehicle Medical Bag Mount + Handle Carry

- [x] bolsa pela alca/uma mao
- [x] bolsa visivel na ambulancia
- [x] retirar diretamente no prop com ox_target
- [x] devolver ao suporte vazio
- [x] area do compartimento separada da bolsa
- [x] configuracao de dimensoes + gizmo do suporte
- [x] compatibilidade com perfil antigo
- [x] V0.4.12: corrigir ox_target da bolsa fisica montada na viatura sem alterar o Compartimento EMS.


## V0.5.0 — Physical Treatment Workflow (concluida)
- [x] item da bolsa -> em maos -> ox_target no paciente -> tratamento
- [x] submenu de regioes corporais no ox_target
- [x] progresso/animacao cancelavel com ox_lib
- [x] consumo apenas ao concluir, validado server-side
- [x] equipamentos duraveis nao consumidos
- [x] efeitos clinicos adicionais: tala/dor, colar/precaucao espinhal, IV/estado persistente

## Proxima linha de tratamentos
- Oxigenoterapia fisica: retirar mascara/canula/BVM, aplicar/remover no paciente e controlar fluxo.
- Medicacoes com via, dose, intervalo, contraindicacoes gameplay e timeline/ePCR.
- LUCAS 2/3 funcional no paciente + RCP mecanica + LIFEPAK/PCR.
- Props de itens individuais quando houver modelos confiaveis.

## V0.5.1 — Hospital Bed Chart + Bed Target Fix (atual)
- [x] Resolver ocupante real de leito para NPC/Player.
- [x] Restaurar ox_target em pacientes congelados no leito por zona independente da colisão.
- [x] Marker E do leito abre ficha hospitalar e não o próprio profissional.
- [x] Ficha hospitalar estilo prontuário brasileiro: identificação, evolução, condutas/prescrição, exames, enfermagem e histórico.
- [x] Tratamentos EMS acessíveis no leito pelo ox_target.
- [ ] Próxima etapa: prescrição/administração de medicamentos com dose, via, horário, checagem e efeitos fisiológicos.
- [ ] Evoluir oxigenoterapia física e dispositivos visuais no paciente.
- [ ] LUCAS 2/3 funcional integrado a PCR e LIFEPAK.
