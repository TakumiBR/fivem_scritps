# FivePD SP Records — patch de identidade visual para FiveEMS v0.4.3

Este patch é **opcional** e foi separado do resource FiveEMS para não sobrescrever silenciosamente
a framework do servidor.

## Diagnóstico da framework original

A framework já possui uma lógica correta para **sexo visual** no client:

- usa `IsPedMale(entidade)`;
- envia `masculino` ou `feminino` ao servidor;
- o servidor possui `corrigirSexoRegistroNpc`, que inclusive corrige nome/sexo de registros antigos.

O problema observado pelo FiveEMS acontecia porque a integração estava chamando o export server-side
sem enviar `sexo`, portanto o Records fazia fallback aleatório.

Para idade, a framework original não tenta inferir aparência: quando `dados.idade` não é fornecido,
usa apenas `math.random(minAge, maxAge)`.

## O que o patch adiciona

### client_main.lua
Além do sexo já existente, calcula uma faixa etária visual a partir do archetype/model do ped:

- `*_y_*`: 18–35;
- `*_m_*`: 30–59;
- `*_o_*`: 60–88;
- nomes com `old/elder`: 60–88;
- nomes com `young`: 18–35;
- fallback: 21–65.

A idade é determinística dentro da faixa para evitar mudar a cada consulta.

### server_main.lua
Adiciona `corrigirIdadeRegistroNpc` e `corrigirApresentacaoRegistroNpc`.

Ao reencontrar um NPC persistente:
- sexo/nome antigo incorreto é corrigido pelo mecanismo que a própria framework já tinha;
- idade só é corrigida se estiver **fora da faixa visual** recebida do client;
- o nascimento persistente é atualizado no banco e nos caches.

## Instalação

Faça backup do `fivepd_sp_records` atual e compare/mescle:

- `client_main.lua` -> `fivepd_sp_records/client/main.lua`
- `server_main.lua` -> `fivepd_sp_records/server/main.lua`

O FiveEMS v0.4.3 já envia sexo/idade visual corretamente mesmo sem este patch.
O patch serve para tornar a regra global na framework e corrigir registros legados com idade incompatível.
