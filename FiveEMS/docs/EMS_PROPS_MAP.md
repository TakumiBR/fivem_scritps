# FiveEMS — EMS Props Map (V0.4.8)

Pacote integrado a partir de `emsprops.zip`. O `ems_props.ytyp` e o `lifepak15.ydr` enviados eram byte-a-byte iguais aos que ja estavam na V0.4.7.

## Equipamentos usados agora

- `lifepak15.ydr` → LIFEPAK 15 fisico (ja operacional).
- `lucas2.ydr` → LUCAS 2, item `lucas2_device`, pode ser retirado do estoque/ambulancia, colocado no chao e recolhido por ox_target.
- `lucas3.ydr` → LUCAS 3, item `lucas3_device`, mesmo fluxo.
- `combicarrier2.ydr` → CombiCarrier II, item `combi_carrier`, mesmo fluxo.

Comandos de teste/uso:

- `/fiveemslifepak`
- `/fiveemslucas2`
- `/fiveemslucas3`
- `/fiveemscombi`
- `/fiveemsequip <lucas2|lucas3|combicarrier>`
- `/fiveemsequiptest` → valida todos os archetypes/modelos no F8.

## Props de maca adicionados ao stream

- `fernocot.ydr`
- `loweredfernocot.ydr`
- `sittingfernocot.ydr`
- `strykergurney.ydr`
- `loweredstrykergurney.ydr`
- `sittingstrykergurney.ydr`
- `fernotexture.ytd`
- `strykertexture.ytd`

Esses modelos ficam disponiveis para calibracao/Creator, mas **nao substituem automaticamente** o `strykerpro` operacional. Isso evita regressao no sistema de maca ja homologado. O proximo passo desses props e medir offsets, altura, pose do paciente e transicoes (normal/baixada/sentada) in-game antes de torná-los perfis operacionais.

## Bolsa medica

Este pack nao contem um modelo dedicado de bolsa medica. A V0.4.8 continua usando os fallbacks nativos configurados em `Config.FieldEquipment.medicalBag.models`.
