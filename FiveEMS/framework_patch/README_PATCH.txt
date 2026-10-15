FiveEMS v0.2.4 - Patch de compatibilidade do ox_target da FivePD SP
===================================================================

A Stryker Pro usa uma entidade de veiculo no GTA/FiveM. Por isso os resources da
framework enxergam a maca como um veiculo comum e adicionam opcoes globais do ox_target.

O FiveEMS marca a maca com o StateBag replicado:
  fiveems:stretcher = true

Este pacote inclui patches MINIMOS em tres resources da base para ignorar entidades com
esse StateBag:

1) fivepd_sp_police/client/main.lua
   Remove da maca as opcoes de placa, chassi, motor, identificacao de moto etc.

2) fivepd_sp_vehicle/client/main.lua
   Remove da maca as opcoes genericas de portas, vidros, capo, porta-malas, trava e empurrar.

3) fivepd_sp_inventory/client/main.lua
   Remove da maca revista/armazenamento de compartimentos de veiculo.

Instalacao:
- Pare o servidor.
- Faca backup dos tres arquivos originais.
- Copie cada pasta de framework_patch por cima do resource correspondente em [base].
- Inicie o servidor.

As mudancas nao identificam o model strykerpro diretamente. A exclusao acontece somente
quando Entity(vehicle).state['fiveems:stretcher'] == true, portanto outros veiculos e motos
continuam funcionando normalmente na framework.


PATCH V2:
- Agora tambem ignora qualquer entidade cujo model seja `strykerpro`, alem do StateBag FiveEMS.
- Isso evita que chassi, placa, motor, portas e revista aparecam mesmo antes da replicacao do StateBag.
- E necessario substituir os 3 arquivos na [base] e reiniciar os resources correspondentes.
