# FiveEMS — Matriz de acesso aos comandos (V0.2.9)

## Filosofia
Comandos não são a interface principal do FiveEMS. Produção usa:
- pontos físicos;
- ox_target;
- garagem;
- painel Admin;
- Criador de Departamentos;
- Mesa do Diretor;
- computador/tablet quando ligados ao mundo.

## Público
| Comando | Acesso |
|---|---|
| `/ems911` | qualquer player |
| `/fiveemshelp` | qualquer player; lista é filtrada por permissão |

## EMS operacional
Requer membro FiveEMS em serviço. Admin pode testar sem duty.

| Comando | Permissão adicional |
|---|---|
| `/fiveems` | nenhuma |
| `/fiveemscomputer` | nenhuma |
| `/fiveemstablet` | nenhuma |
| `/fiveemsexam` | `patient.assess` |
| `/fiveemspatient <id>` | `patient.assess` |
| `/fiveemsmonitor` | `monitor.use` |

## Gestão do departamento
| Comando | Permissão |
|---|---|
| `/fiveemsdirector` | `department.manage` |

## Administrador
Diagnóstico, manutenção e ferramentas de desenvolvimento:
`/fiveemsadmin`, `/fiveemscreator`, `/fiveemsresetpatient`, `/fiveemsdb`, `/fiveemstest`,
`/fiveemsframework`, `/fiveemsseed`, `/fiveemsnpctest`, `/fiveemsstretcher`,
`/fiveemsstretcherin`, `/fiveemsstretcherout`, `/fiveemspatientstretcher`,
`/fiveemspatientrelease`.

A validação destes comandos acontece no servidor.


## V0.3.0 — nomes configuráveis
Os nomes dos comandos públicos/operacionais/painéis são aliases configuráveis pelo Admin.
A permissão é vinculada à função do comando, não ao texto digitado. Portanto renomear `/fiveemsadmin` para outro alias não transforma o comando em público.
