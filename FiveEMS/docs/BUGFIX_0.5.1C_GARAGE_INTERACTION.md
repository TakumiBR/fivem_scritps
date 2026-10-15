# FiveEMS V0.5.1c — Garage Interaction Fix

- Remove uso invalido de `PlaceEntityOnGroundProperly` em Peds.
- NPC de preview/runtime nasce no Z exato do ponto e o 3D Gizmo controla o transform.
- Garagens pendentes agora podem ser editadas imediatamente.
- Exclusao de garagem usa modal da NUI, sem `window.confirm`.
- Interacao pode ser `none`, `marker` ou `ped`.
- Dentro da edicao e possivel:
  - reposicionar/editar o NPC com 3D Gizmo;
  - excluir somente o NPC;
  - excluir somente o Marker;
  - adicionar novamente Marker ou Ped/NPC sem recriar a garagem.
- Ao remover Ped/Marker, a garagem e suas vagas permanecem.
- Runtime nao desenha Marker nem permite E quando a interacao esta `none`.

Sem migration de banco.
