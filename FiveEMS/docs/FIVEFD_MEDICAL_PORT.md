# FiveEMS V0.4.0 — Mapeamento do Medical Workflow do FiveFD

## Objetivo

Reaproveitar decisões de gameplay já amadurecidas no FiveFD, sem transportar a implementação C# diretamente para a framework FivePD SP.

## Mapeamento

| FiveFD | FiveEMS / FivePD SP |
|---|---|
| Medical Actor | TargetRef Player/NPC + `fivepd_sp_records` |
| Patient State | `fiveems_patient_state` |
| Injury Engine | fisiologia FiveEMS + `fivepd_sp_injuries` |
| Scene Health Audit | Patient Workspace / pontos `+` |
| XABCDE | `server/clinical.lua` server-authoritative |
| Vitals measurement | `observedVitals` + Medical Bag |
| Medical Bag | `fiveems_medical_bags` + `fiveems_supplies` |
| Treatments | `clinicalApplyTreatment` |
| Patient Timeline | `state.timeline` |
| ePCR | `fiveems_reports` + `fiveems_encounters` |
| Persistent identity | `fivepd_sp_records` |
| Stretcher/bed renderer | SUPINE_NEUTRAL + exact ANCHOR |

## Princípios preservados

1. O jogo sabe a fisiologia; o profissional precisa descobri-la.
2. Não existe botão mágico de cura/revive como fluxo normal.
3. Tratamento estabiliza e altera fisiologia; não apaga o histórico da lesão.
4. Player e NPC passam pelo mesmo Clinical Runtime.
5. Server valida mutações, inventário, permissões e persistência.
6. Maca e leito são suportes físicos; a pose clínica do paciente é um renderer controlado.
7. ANCHOR calibrado pelo Creator é autoritativo em MLO custom.
