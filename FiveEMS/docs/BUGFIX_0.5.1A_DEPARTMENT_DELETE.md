# FiveEMS V0.5.1a — Department Delete Fix

Correção do Criador de Departamentos.

## Causa
A V0.5.1 emitia `fiveems:client:departmentDeleted` no servidor, mas não havia
handler correspondente no client. Assim, mesmo quando a exclusão era processada,
a NUI podia continuar exibindo o hospital até um novo bootstrap/restart.

O botão também dependia de `window.confirm()`, que não é uma confirmação
confiável dentro da NUI/CEF do FiveM.

## Correções
- handler client-side para `departmentDeleted`;
- atualização imediata do bootstrap/NUI;
- modal de confirmação desenhado dentro da própria NUI;
- exclusão server-authoritative com transação;
- limpeza explícita das referências conhecidas antes do DELETE;
- histórico de relatórios, atendimentos e CSI preservado com `department_id=NULL`;
- feedback explícito de sucesso/falha;
- broadcast dos departamentos do mundo após exclusão.

Não há migration ou alteração de schema nesta build.
