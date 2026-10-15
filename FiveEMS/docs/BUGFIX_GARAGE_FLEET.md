# Garagens: contexto, vagas e gerenciamento da frota

- O retorno do Gizmo preserva o departamento editado no bootstrap, em vez de selecionar novamente o departamento do personagem.
- A retirada usa o departamento do ponto de garagem e consulta suas vagas atuais no banco. Administradores podem testar a garagem sem vinculo ao departamento; membros continuam restritos ao proprio departamento e nivel.
- Sem ponto ou vagas, a retirada informa o problema e nao cria a viatura ao lado do jogador.
- Creator > Veiculos permite editar nome, modelo e nivel, preservando settings, ou remover a entrada da frota com confirmacao NUI.
- Edicao/remocao exigem permissao no servidor e respeitam o departamento. Remover uma entrada nao apaga veiculos ja spawnados nem perfis de maca/equipamentos.
- A maca continua fixa no catalogo operacional. Nenhuma migration SQL e necessaria.

## Validacao automatizada

Em FiveEMS/: `lua tests/garage_server_test.lua` (Lua 5.4). Os testes usam mocks do banco e eventos, sem FiveM.

## Validacao no servidor FiveM

1. Reinicie FiveEMS. Abra /fiveemscreator, selecione um departamento diferente do vinculo do administrador (ou use admin sem vinculo).
2. Crie/edite uma garagem e adicione duas vagas via Gizmo. Confirme que o departamento e as vagas permanecem ao retornar e reabrir o criador.
3. Abra a garagem pelo ponto fisico e retire uma viatura: deve usar a primeira vaga livre. Ocupe-a e retire outra: deve usar a proxima. Com todas ocupadas, deve avisar sem criar viatura.
4. Em Creator > Veiculos, edite nome/modelo/nivel, salve e reabra. Remova uma entrada, verificando cancelar e confirmar. A maca deve continuar disponivel.
5. Repita como membro autorizado e como membro sem garage.manage; valide as restricoes e a persistencia apos reiniciar.

A framework externa nao foi inspecionada: o ZIP enviado ultrapassa o limite de transferencia de 32 MiB. Os testes in-game ainda precisam ser executados com FivePD SP, oxmysql, ox_lib e ox_target.

## Exclusao de vagas e confirmacao NUI

- O botao de excluir vaga usava `window.confirm`, abrindo o dialogo nativo do CEF. Agora o modal e filho do painel FiveEMS, com o mesmo tema e limites da NUI.
- O callback anterior confirmava sucesso apos disparar um evento, sem aguardar o banco. Agora a exclusao consulta o ponto atual no servidor, valida permissao/departamento/indice/coordenadas, grava e retorna o resultado real via ox_lib callback.
- A gravacao usa comparacao com o conteudo anterior para rejeitar alteracoes concorrentes em vez de sobrescreve-las. Erros aparecem no modal; nao ha mensagem falsa de sucesso.
- Salvar dados da garagem preserva a lista de vagas atual do banco, evitando que uma copia antiga do formulario remova ou restaure vagas.
- Nenhuma migration SQL necessaria.

Validacao: 20 testes Lua com mocks de banco/eventos; teste Chromium da NUI para limites do modal, cancelar, falha, nova tentativa e sucesso confirmado. Para reproduzir o teste de interface: `python tests/garage_modal_test.py` (requer Playwright e Chromium). O teste usa servidor HTTP local e mocks do transporte NUI; nao valida o runtime FiveM.

No jogo: reinicie FiveEMS, exclua uma vaga e reabra a garagem para confirmar persistencia; adicione novamente pelo Gizmo, salve os dados gerais e reabra. Retire uma viatura no ponto fisico da garagem e confira o spawn. Se ainda nao reconhecer a vaga, registre a mensagem exata e os logs F8/console do servidor para distinguir ausencia de vagas, vagas ocupadas e falha de spawn.
