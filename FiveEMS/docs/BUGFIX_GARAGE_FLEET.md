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
