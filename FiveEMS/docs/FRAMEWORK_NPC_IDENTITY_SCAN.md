# FiveEMS v0.4.3 — Varredura da identidade NPC na FivePD SP

## Resultado

A autoridade correta para identidade continua sendo `fivepd_sp_records`.
O FiveEMS não cria uma segunda lista de nomes nem um segundo registro civil.

## Sexo visual e nome

A framework original **já possui** no client a leitura:

- `IsPedMale(entidade)`;
- `masculino` para ped masculino;
- `feminino` para ped feminino.

O servidor de Records também já possui `corrigirSexoRegistroNpc(registro, sexoEsperado)`.
Quando recebe o sexo esperado e encontra um registro antigo incompatível, ele:

- corrige `sexo`;
- seleciona um primeiro nome da lista masculina/feminina correspondente;
- preserva/gera sobrenome;
- atualiza o banco;
- atualiza os caches por `npc_key` e RG.

### Por que apareceu “Larissa Pereira” em um NPC masculino?

O FiveEMS estava chamando o export server-side `ObterOuCriarNPC` sem enviar `sexo`.
Essa rota não passa pela função client-side da framework que chama `IsPedMale`, então o Records
caía no fallback aleatório de sexo/nome.

A V0.4.3 corrige isso: FiveEMS observa o ped real no client e envia `sexo` no primeiro claim,
na auditoria clínica e no teste administrativo.

## Idade

Na framework original, se `dados.idade` não chega, a criação faz apenas:

`math.random(FSPRecords.Npc.minAge, FSPRecords.Npc.maxAge)`

Portanto a versão original **não relaciona idade civil com aparência do ped**.

A V0.4.3 envia uma faixa visual com base no archetype/model:

- `*_y_*` / `young`: 18–35;
- `*_m_*`: 30–59;
- `*_o_*` / `old` / `elder`: 60–88;
- fallback sem pista visual: 21–65.

A idade é determinística dentro da faixa para o mesmo ped durante sua identidade persistente.

## Registros antigos

Sem modificar a framework, o Records original consegue corrigir sexo/nome antigo porque essa rotina
já existe. Porém ele **não corrige idade antiga** quando o registro já existe.

Por isso o pacote inclui `framework_patch/fivepd_sp_records/`:

- `client_main.lua`: torna a geração por aparência global na framework;
- `server_main.lua`: adiciona correção de nascimento/idade somente quando a idade persistida estiver
  fora da faixa visual recebida.

O patch é separado e opcional para não sobrescrever silenciosamente a base do servidor.

## Regra arquitetural

FiveEMS fornece contexto visual/clinico.
`fivepd_sp_records` continua sendo a identidade civil canônica e persistente.
