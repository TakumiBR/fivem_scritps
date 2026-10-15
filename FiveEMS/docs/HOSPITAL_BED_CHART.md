# FiveEMS V0.5.1 — Ficha Hospitalar de Leito

A ficha do leito é uma interface separada da Auditoria Clínica de cena. Ela representa o prontuário hospitalar disponível na prancheta/estação do leito e sempre resolve o paciente associado ao `carePointId`.

## Seções
- Resumo: identificação, leito, triagem, alergias/antecedentes disponíveis, sinais aferidos e resumo clínico.
- Evolução: timeline multiprofissional do Medical Actor.
- Prescrição / Condutas: oxigenoterapia, acesso IV, precaução cervical e procedimentos registrados; área reservada para prescrição medicamentosa.
- Exames: aferições à beira-leito e exame físico documentado; preparada para laboratório/imagem.
- Enfermagem: cuidados, aferições e tratamentos documentados.
- Histórico: ePCRs e encounters anteriores persistidos no banco.

## Interação
- `E` no pé do leito -> abre Ficha do Leito.
- `ox_target` sobre o paciente -> Ficha do Leito / Atender paciente / Tratamentos EMS.

A zona de target usa a posição real do paciente configurada pelo 3D Gizmo. Ela não depende da colisão do ped, portanto continua funcionando enquanto o paciente está congelado e sem colisão no leito.
