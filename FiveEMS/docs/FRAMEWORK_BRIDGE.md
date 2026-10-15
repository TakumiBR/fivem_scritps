# FiveEMS v0.2.6 — FivePD SP Framework Bridge

Esta build inicia a migracao do FiveEMS standalone para a framework FivePD SP.

## Integracoes ativas
- `fivepd_sp_core`: `character_id`, `fixed_id`, tipo de personagem e chave canonica `char:<id>`.
- `fivepd_sp_records`: identidade de Player e API pronta para NPC persistente.
- `fivepd_sp_inventory`: entrega de itens via inventario nativo com metadata `fiveems_item`.
- `fivepd_sp_injuries`: snapshot fisico sincronizado no estado medico e tratamentos espelhados.
- `fivepd_sp_death`: claim de atendimento, liberacao e revive externo apos ROSC.
- `fivepd_sp_admin`: permissao global de Admin.
- `fivepd_sp_ui`: notificacoes FiveEMS.

## Compatibilidade
A estrutura SQL atual foi preservada nesta etapa para reduzir risco. O campo `identifier` passa a armazenar `char:<character_id>`; registros antigos por license sao migrados automaticamente quando o personagem entra.

## Inventario
A base atual nao possui todos os itens EMS no `Config.Items`. Por isso, esta build usa itens genericos existentes (`medicamento`, `mascara`, `luvas`, `documento`, `vestigio_lacrado`) com metadata do item FiveEMS. A proxima etapa deve registrar itens EMS dedicados no catalogo da framework.

## Proximas pontes
- Hospital: substituir cura instantanea por admissao FiveEMS quando o resource estiver ativo.
- Support: ambulancia NPC como fallback quando nao houver EMS player em duty.
- PC/DHPP: compartilhar cadeia de custodia e cenas medico-legais.
- NPC Medical Actor: usar `ObterOuCriarNPC()` em todos os atendimentos NPC.

## Regras adicionais
- O Admin global FiveEMS usa `fivepd_sp_admin:TemPermissao(source, 'gerenciar_staff')` por padrao (configuravel).
- Nao e permitido entrar em duty FiveEMS enquanto `fivepd_sp:pmEmServico=true`.
- `fivepd_sp:medical:tratamentoCompleto` reseta o estado fisiologico FiveEMS para manter compatibilidade com recursos antigos durante a transicao.
