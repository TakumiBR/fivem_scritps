# Análise — NPC ferido desaparecendo

## Causa encontrada na FivePD SP
O resource `fivepd_sp_world/client/main.lua` possui um limpador de população ambiente.
A função `tryDeleteAmbient(entity)` ignora entidades protegidas por StateBag e entidades com population type 7 (mission entity), mas pode apagar um ped ambiente comum.

A própria framework já reconhece como protegidos:
- `fivepd_sp:protected`
- `fivepd_sp:supportPersistent`
- entidades de Support/QRU/Ambient/Illegal/etc.

O `fivepd_sp_support` confirma o padrão correto: vítimas de chamados são promovidas a mission entity no client e o servidor aplica `fivepd_sp:supportPersistent`, `fivepd_sp:protected` e orphan mode 2.

## Situação anterior no FiveEMS
Antes da V0.3.0, o FiveEMS só pegava o NPC quando o usuário escolhia `NPC próximo` no menu da maca. Se o player ferisse um ped, se afastasse para buscar a maca e o world manager fizesse cleanup antes disso, o FiveEMS ainda não tinha reclamado/protegido aquela entidade.

## Correção V0.3.0
O FiveEMS passa a reconhecer automaticamente um NPC humano ferido próximo como potencial paciente e protege a entidade com o mesmo padrão de persistência usado pela framework, sem modificar o `fivepd_sp_world`.
