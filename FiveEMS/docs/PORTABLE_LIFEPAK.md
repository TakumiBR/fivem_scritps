# FiveEMS V0.4.7a — LIFEPAK 15 portátil + Monitor Overlay

## Fluxo operacional

1. Retire **LIFEPAK 15 - Monitor multiparamétrico portátil** no estoque do departamento.
2. Use **F7** ou `/fiveemslifepak`. O servidor valida permissão e o item FiveEMS exato no inventário antes de liberar o posicionamento.
3. Posicionamento: setas ajustam distância/lateral, PgUp/PgDn ajustam altura, Q/E giram, ENTER confirma e BACKSPACE cancela.
4. Use `ox_target` no aparelho para conectar paciente, abrir monitor, abrir em overlay, desconectar, reposicionar ou guardar.
5. No monitor completo, use **Overlay** para fixar uma versão menor sobre o gameplay.
6. No overlay: arraste, Scale-/Scale+, Compacto/Expandido e Trava. Clique **Continuar jogando** para liberar mouse/teclado mantendo o monitor visível.
7. Com o overlay ativo, abra a Auditoria Clínica normalmente. O monitor continua recebendo os sinais pelo canal `monitorState`, independente da tela clínica.
8. `/fiveemsmonitoroverlay` devolve o foco ao overlay quando quiser reposicionar ou redimensionar novamente.

## OneSync e distância dos cabos

O prop é criado como entidade networked e o vínculo `monitor -> paciente` é mantido no servidor/statebag. Outro EMS pode abrir o mesmo aparelho. Por padrão, o paciente precisa permanecer a até **5,5 m** do LIFEPAK; acima disso a conexão cai e o monitor acusa eletrodos/cabos desconectados.

## Inventário

A framework atual permite ler a metadata do inventário, então o FiveEMS valida especificamente `metadata.fiveems_item = lifepak15_monitor`. O export documentado de remoção remove pelo nome-base do item, não por slot/metadata. Para não consumir por engano outro item médico que compartilhe `medicamento`, a V0.4.7a reserva no máximo um LIFEPAK físico por player enquanto implantado.

## Asset 3D recebido

O pacote inclui exatamente `stream/lifepak15.ydr` fornecido ao projeto. Se o FiveM não reconhecer o model `lifepak15` mesmo com o YDR streamado, o asset de origem pode depender também do `.ytyp` (archetype) e/ou `.ytd` correspondente. Nesse caso, envie esses arquivos do prop e eles devem ser adicionados ao `stream/`/manifest sem alterar a lógica do sistema.


## Asset analisado na V0.4.7

O `stream.zip` fornecido contém `ems_props.ytyp`.
Ao inspecionar o YTYP compilado, existe um archetype independente `lifepak15`; ele não depende
de spawnar a `strykergurney`.

Arquivos usados pelo FiveEMS:
- `stream/lifepak15.ydr`
- `stream/ems_props.ytyp`

Manifest:
- `data_file 'DLC_ITYP_REQUEST' 'stream/ems_props.ytyp'`

Debug:
- `/fiveemslifepaktest`
