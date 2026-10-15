# FiveEMS × FivePD São Paulo 2.0 — Análise de Integração

Data da análise: 2026-10-12
Arquivo analisado: `[base].rar`

## Escopo analisado

O pacote contém 44 resources principais e 2.150 entradas. Foram extraídos e inspecionados 515 arquivos de código/configuração/texto, incluindo manifests, Lua client/server, NUI JS/CSS/HTML, SQL/migrations, configs e READMEs. O ecossistema é uma framework custom standalone; não é ESX/QBCore.

Resources principais: `fivepd_sp_database`, `fivepd_sp_core`, `fivepd_sp_base`, `fivepd_sp_character`, `fivepd_sp_settings`, `fivepd_sp_ui`, `fivepd_sp_admin`, `fivepd_sp_spawn`, `fivepd_sp_pm`, `fivepd_sp_police`, `fivepd_sp_records`, `fivepd_sp_inventory`, `fivepd_sp_injuries`, `fivepd_sp_medical`, `fivepd_sp_death`, `fivepd_sp_hospital`, `fivepd_sp_support`, `fivepd_sp_pc`, `fivepd_sp_dhpp`, `fivepd_sp_qru`, `fivepd_sp_copom`, `fivepd_sp_vehicle`, `fivepd_sp_phone`, `bodycam`, `ox_lib`, `ox_target` e módulos auxiliares.

## Arquitetura da framework

### Identidade e sessão

`fivepd_sp_core` é a autoridade de sessão. O jogador é persistido por `license:` na tabela `fivepd_sp_core`. O personagem selecionado vive em `fivepd_sp_character` e a sessão contém `personagemId`, `jogadorId`, `idFixo`, nome, sobrenome, sexo e `tipoPersonagem`.

Exports server relevantes:
- `ObterSessao(source)`
- `ObterPersonagemId(source)`
- `ObterIdFixo(source)`
- `ObterTipoPersonagem(source)`
- `ObterJogador(source)`
- `RegistrarPersonagem(source, personagem)`

State bags replicados pelo servidor:
- `fivepd_sp:personagemCarregado`
- `fivepd_sp:personagemId`
- `fivepd_sp:personagemTipo`
- `fivepd_sp:idFixo`
- `fivepd_sp:vipTier`
- `fivepd_sp:vipBooster`

O código deixa explícito que state bags replicados são escritos pelo servidor por compatibilidade com strict mode.

### Character

`fivepd_sp_character` gerencia multichar, aparência, roupas, posição, vida e colete. O modelo atual trabalha com dois tipos: `policial` e `ilegal`. O Core normaliza qualquer tipo diferente de `ilegal` para `policial`, portanto adicionar `ems` como terceiro `character_type` exigiria patch na framework e em vários resources.

### Banco de dados

`fivepd_sp_database` espera `oxmysql`, executa migrações automáticas e sinaliza prontidão com:
- `exports.fivepd_sp_database:EstaPronto()`
- `ConexaoPronta()`
- `ObterStatus()`
- evento `fivepd_sp:banco:pronto`

O padrão predominante é uma tabela física por resource, com coluna `entity` e partições para subentidades. O FiveEMS deve aguardar o banco da framework antes de inicializar schema próprio.

### UI

`fivepd_sp_ui` é a UI global. Exports client:
- `Notificar({tipo,titulo,descricao,duracao})`
- `MostrarAjuda(...)`
- `OcultarAjuda()`
- `IniciarProgresso(...)`
- `AtualizarProgresso(...)`
- `FinalizarProgresso(...)`

O FiveEMS deve usar esta UI para notificações/progressos em vez de manter notificações próprias fora do padrão.

### Admin

`fivepd_sp_admin` tem hierarquia `suporte`, `moderador`, `administrador`, `admin_geral`, `ceo` e matriz de permissões server-side. Exports relevantes:
- `ObterCargo(source)`
- `TemPermissao(source, permissao)`

O painel global do FiveEMS deve validar acesso via esta camada, não via ACE isolado.

### PM / progressão policial

`fivepd_sp_pm` implementa corporações, unidades, pontos, ranks, progressão, XP, garagem, uniforme, arsenal e duty. Apesar de ser relativamente genérico internamente, a entrada operacional é explicitamente limitada a `tipoPersonagem == 'policial'` e vários fluxos continuam police-specific.

Exports úteis:
- `EmServico(source)`
- `ContextoAtual(source)`
- `CorporacaoAtual(source)`
- `UnidadeAtual(source)`
- `ProgressoAtual(source)`
- `TemFuncao(source, role)`
- `AdicionarXP(...)`
- `ConcederXPServico(...)`

Conclusão: não é recomendado reutilizar `fivepd_sp_pm` como engine direta do EMS agora, pois isso acoplaria FiveEMS a regras policiais. O FiveEMS deve manter departamentos/progressão EMS próprios, mas usar `character_id` da framework como identidade.

### Records — identidade persistente de Players e NPCs

`fivepd_sp_records` já resolve uma parte crítica do FiveEMS.

Para players, `GarantirRegistroPersonagem(characterId)` cria/garante registro civil persistente com RG, nome, nascimento, sexo, telefone e `tipo_sanguineo`.

Para NPCs, `ObterOuCriarNPC(networkId, dados)` cria identidade persistente server-side, usa state bag da entidade, revalida reutilização de Net ID e pode persistir no banco. Isto fornece exatamente a base necessária para Medical Actor persistente e sincronizado por OneSync.

Exports mais importantes para FiveEMS:
- `GarantirRegistroPersonagem(characterId)`
- `PessoaPorPersonagem(characterId)`
- `PessoaPorRecordId(recordId)`
- `ObterOuCriarNPC(networkId, dados)`
- `RegistrarNPC(dados)`

O FiveEMS não deve criar nomes/tipos sanguíneos próprios. Deve usar `fivepd_sp_records` como identidade canônica.

### Inventário

A framework não usa `ox_inventory` como inventário principal. Existe `fivepd_sp_inventory`, com inventário físico por compartimentos/roupas, itens persistentes e exports server-side.

Exports úteis:
- `AdicionarItemAoJogador(source, name, metadata)`
- `AdicionarItemQuantidade(...)`
- `RemoverItemDoJogador(source, name, amount)`
- `ContarItemJogador(source, name)`
- `ObterInventarioJogador(source)`

O FiveEMS deve cadastrar/remédios/equipamentos no catálogo deste resource ou através de um bridge/runtime seed compatível. A integração anterior com `ox_inventory` deve ser removida.

### Injuries

`fivepd_sp_injuries` já detecta danos e implementa:
- cabeça/tórax/braço/perna
- sangramento
- ragdoll por impacto
- mancar
- fratura de pernas por queda
- carregar player ferido

Exports client:
- `ObterFerimentos()`
- `EstaSangrando()`
- `PernasQuebradas()`
- `LimparFerimentos()`
- `AplicarTratamento(regiao, quantidade)`

Eventos locais úteis:
- `fivepd_sp:injuries:alterado`
- `fivepd_sp:injuries:curado`
- `fivepd_sp:injuries:legsBroken`

O FiveEMS deve ser uma camada médica avançada sobre este sistema, não um segundo detector físico concorrente. Ele pode manter fisiologia detalhada, órgãos, sinais vitais, tratamentos e histórico, enquanto `fivepd_sp_injuries` continua responsável pelas consequências físicas GTA (mancar, fratura, carry etc.).

### Medical

`fivepd_sp_medical` hoje é uma camada fina sobre Injuries. Ele fornece `ObterResumo`, `TratamentoCompleto`, `Estabilizar` e o comando `/ferimentos`.

Com FiveEMS instalado, o melhor desenho é transformá-lo em compatibility shim: chamadas antigas continuam funcionando, mas delegam ao FiveEMS quando este estiver ativo.

### Death

`fivepd_sp_death` é autoridade de incapacidade/óbito. Estados: `alive`, `downed`, `confirmed`, `ghost`. Persiste estado no banco e usa state bags:
- `fivepd_sp:deathState`
- `fivepd_sp:medicalClaimed`
- `fivepd_sp:deathPose`

Exports server importantes:
- `MarcarAtendimento(targetSource, enabled, claimId)`
- `AvaliarSocorro(targetSource)`
- `ConcluirIML(targetSource)`
- `ObterEstado(targetSource)`

O FiveEMS deve respeitar esta máquina de estados. Ao começar atendimento em um downed player, deve usar `MarcarAtendimento` para impedir respawn/fluxos paralelos. Revive pelo FiveEMS precisa comunicar a recuperação ao `fivepd_sp_death`; não deve apenas dar SetEntityHealth.

### Hospital existente

`fivepd_sp_hospital` atualmente oferece NPC recepcionista que, após progress bar, chama `fivepd_sp:medical:tratamentoCompleto` e cura tudo. Isso conflita diretamente com o hospital realista do FiveEMS.

Modo recomendado quando FiveEMS estiver ativo: o atendente existente vira fallback/triagem e redireciona para o fluxo FiveEMS, em vez de cura instantânea.

### Support / Ambulância NPC / IML

`fivepd_sp_support` já possui ambulância NPC, IML, tratamento/avaliação de players e NPCs, criação de corpos, espera de IML e integração com DHPP. Isto precisa continuar funcionando como fallback e apoio NPC.

O FiveEMS deve coexistir sem criar um segundo sistema de óbito/IML. Chamados com EMS player devem priorizar FiveEMS; sem EMS online, o support NPC pode permanecer como fallback.

### PC / DHPP / CSI

A framework já possui investigação e perícia avançada em `fivepd_sp_pc` e `fivepd_sp_dhpp`, incluindo:
- casos e inquéritos
- evidências
- cenas médicas
- cadeia de custódia
- exames forenses
- balística
- autópsia
- integração IML

O módulo Polícia Científica/CSI do FiveEMS não deve duplicar essas estruturas. Ele deve usar um bridge para vincular atendimento médico/óbito/evidência clínica aos casos/evidências já existentes na PC/DHPP.

## Conflitos do FiveEMS standalone atual

1. Identidade própria de paciente duplica Core/Records.
2. NPC Medical Actor próprio duplica a identidade persistente já existente em Records.
3. Integração `ox_inventory` está errada para esta base; deve usar `fivepd_sp_inventory`.
4. Sistema de danos FiveEMS concorre com `fivepd_sp_injuries`.
5. Revive/óbito FiveEMS pode quebrar `fivepd_sp_death` se alterar health diretamente.
6. Hospital FiveEMS conflita com atendimento instantâneo de `fivepd_sp_hospital`.
7. CSI FiveEMS duplica PC/DHPP.
8. Admin por ACE não segue `fivepd_sp_admin`.
9. As tabelas atuais do FiveEMS não seguem o padrão de banco da framework.
10. Progressão EMS não deve usar diretamente `fivepd_sp_pm`, pois este continua police-specific.

## Arquitetura recomendada do FiveEMS integrado

### Hard dependencies

- `ox_lib`
- `oxmysql`
- `ox_target`
- `fivepd_sp_database`
- `fivepd_sp_core`
- `fivepd_sp_ui`
- `fivepd_sp_records`
- `fivepd_sp_inventory`
- `fivepd_sp_injuries`
- `fivepd_sp_death`

### Soft integrations

- `fivepd_sp_hospital`
- `fivepd_sp_medical`
- `fivepd_sp_support`
- `fivepd_sp_pc`
- `fivepd_sp_dhpp`
- `fivepd_sp_pm`
- `fivepd_sp_vehicle`
- `fivepd_sp_phone`

### Adapter FiveEMS

Criar uma camada `server/framework.lua` e `client/framework.lua` para concentrar acesso à framework:
- sessão / character_id / fixed_id
- notificações / progress
- identidade civil de player/NPC
- inventário
- death claims / revive
- staff/admin
- estado de injuries

Assim o restante do FiveEMS não chama resources externos diretamente em dezenas de arquivos.

## Decisão de emprego/duty EMS

Recomendação: manter Department Creator + cargos + XP/Level do FiveEMS, persistidos por `character_id`, e não migrar EMS para `fivepd_sp_pm` agora. O PM é um subsistema policial e modificar sua semântica para EMS aumentaria muito a superfície de regressão.

O FiveEMS deve escrever um state bag server-authoritative como `fiveems:onDuty` e manter membership EMS próprio. Opcionalmente deve bloquear duty EMS quando o personagem estiver em serviço policial e vice-versa.

## Banco FiveEMS integrado

Em vez das muitas tabelas standalone atuais, usar uma tabela física própria do resource, seguindo o padrão da base, por exemplo `fiveems`, com `entity` discriminando departamentos, ranks, members, points, vehicles, supplies, progression, medical_profiles, encounters, injuries, vitals, treatments, reports, beds, devices, CSI links, settings e audit.

Identidade do paciente não é duplicada: registros FiveEMS referenciam `fivepd_sp_records.id` (`record_id`) e/ou `character_id`.

## Ordem recomendada de refatoração

1. Framework adapter + nova inicialização/banco.
2. Identidade: Core + Records para players e NPCs.
3. Admin e UI: Admin/UI da framework.
4. Inventário: FivePD inventory.
5. Injuries compatibility layer.
6. Death authoritative integration.
7. Department Creator/XP sobre character_id.
8. Hospital integration e desativação da cura instantânea quando FiveEMS estiver ativo.
9. Support/ambulância NPC fallback.
10. PC/DHPP/CSI bridge.
11. Só então retomar Computer/Tablet OS e demais features de apresentação.

## Conclusão

A base do seu amigo já contém várias fundações que o FiveEMS precisava construir. O maior ganho é `fivepd_sp_records`, que já fornece identidade persistente de player e NPC, tipo sanguíneo e sincronização baseada em state bag/OneSync. O caminho correto não é encaixar o FiveEMS standalone por cima sem alterações; é refatorá-lo para ser um resource nativo da FivePD SP 2.0, reutilizando Core, Records, Inventory, Injuries, Death, UI e PC/DHPP e mantendo dentro do FiveEMS apenas o que é especificamente EMS/hospitalar.
