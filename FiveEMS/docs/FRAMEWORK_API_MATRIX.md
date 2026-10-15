# FiveEMS x FivePD SP — Matriz de APIs usadas na V0.2.0

## fivepd_sp_core
- `ObterSessao(source)`
- `ObterPersonagemId(source)`
- `ObterIdFixo(source)`
- `ObterTipoPersonagem(source)`

## fivepd_sp_records
- `PessoaPorPersonagem(characterId)`
- `ObterOuCriarNPC(networkId, dados)`

## fivepd_sp_inventory
- `AdicionarItemQuantidade(sourceId, name, amount, metadata, forcedCompartment)`
- `ContarItemJogador(sourceId, name)`

## fivepd_sp_injuries
Client exports/eventos usados:
- `AplicarTratamento(regiao, quantidade)`
- `fivepd_sp:injuries:alterado`
- `fivepd_sp:injuries:curado`

## fivepd_sp_death
- `ObterEstado(source)`
- `MarcarAtendimento(targetSource, enabled, claimId)`
- evento `fivepd_sp:morte:revividoExterno` disparado pelo proprio paciente
- evento client `fivepd_sp:morte:reviver`

## fivepd_sp_admin
- `TemPermissao(source, permissao)`
- `ObterCargo(source)`

## fivepd_sp_ui
- `Notificar({tipo,titulo,descricao})`
