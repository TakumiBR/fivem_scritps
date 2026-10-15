# FiveEMS V0.5.0 — Physical Treatment Workflow

## Fluxo

1. Retire a bolsa medica da ambulancia.
2. Leve a bolsa ate o paciente e coloque no chao.
3. Abra a bolsa pelo `ox_target`.
4. Use **Pegar para usar** no material desejado. O item passa para **Em maos**.
5. Mire no NPC/Player com `ox_target` e escolha **Tratamentos EMS**.
6. Selecione o procedimento e depois a regiao corporal.
7. O FiveEMS executa uma acao com progresso/animacao.
8. Se cancelar, o item continua em maos. Se concluir, o servidor valida tudo novamente e so entao consome o material quando ele for consumivel.

## Tratamentos disponiveis

- Compressao direta — sem item.
- Empacotamento de ferida — `wound_pack`.
- Torniquete — `tourniquet`.
- Curativo compressivo — `pressure_bandage`.
- Selo toracico — `chest_seal`.
- Tala — `splint`.
- Colar cervical — `c_collar`.
- Canula orofaringea — `opa` (procedimento avancado).
- Aspiracao de via aerea — `suction_kit` (duravel).
- Acesso venoso — `iv_kit` (procedimento avancado).
- Manta termica — `thermal_blanket`.
- Curativo para queimadura — `burn_dressing`.

## Regras server-authoritative

O servidor valida permissao, distancia, regiao, lesao compativel, duplicidade e item em maos no inicio e novamente ao concluir. Um consumivel nao e removido quando o progresso comeca. Isso evita perder material por cancelamento e dificulta chamadas client-side falsas.

Equipamentos listados em `FiveEMS.Clinical.nonConsumableItems` nao sao consumidos. Eles continuam em maos e podem ser devolvidos a bolsa.

## Animacao

Paciente no chao: postura de atendimento ajoelhado.
Paciente em maca/leito/em pe: animacao de atendimento em pe.

A progressao usa `ox_lib` (`progressCircle`) e pode ser cancelada pelo jogador.

## Proxima evolucao

- Oxigenoterapia fisica com mascara/canula/BVM aplicada e removida do paciente.
- Medicacoes com via, dose e efeito fisiologico.
- LUCAS 2/3 funcional em PCR com integracao ao LIFEPAK.
