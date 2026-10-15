# FiveEMS V0.5.1b — Garage Ped Gizmo Fix

## Corrigido

### NPC duplicado
O carregamento do modelo do NPC era assíncrono. Um refresh podia apagar o ped
atual enquanto uma thread antiga ainda terminava de carregar o modelo; essa thread
criava um novo ped depois do cleanup. Agora cada refresh possui uma geração e
threads antigas são invalidadas.

### Ped permanecendo depois de mudar para Marker
Ao salvar `Marker`, o `ped_transform` deixa de ser persistido e o refresh invalida
qualquer spawn antigo. Um ped de uma configuração anterior não pode reaparecer
depois que o modelo termina de carregar.

### Altura/posição do NPC
O NPC da garagem agora possui 3D Gizmo próprio:
- criar uma garagem como Ped/NPC abre o Gizmo automaticamente;
- uma garagem existente mostra `3D Gizmo · Posicionar NPC`;
- X/Y/Z e rotação escolhidos são persistidos em `interaction.ped_transform`;
- sem transform antigo, o preview é primeiro assentado no chão;
- o ponto interativo da garagem acompanha a posição final do NPC.

Nenhuma migration de banco é necessária. O transform fica no JSON `data`
já existente em `fiveems_points`.
