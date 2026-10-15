let active = null;
const nudge = {left:false,right:false,up:false,down:false,upZ:false,downZ:false,rotLeft:false,rotRight:false};

function v(v, i, key) {
  if (Array.isArray(v)) return Number(v[i] || 0);
  if (v && typeof v === 'object') return Number(v[key] || 0);
  return 0;
}

function makeMatrix(entity) {
  const [f, r, u, a] = GetEntityMatrix(entity);
  return new Float32Array([
    v(r,0,'x'), v(r,1,'y'), v(r,2,'z'), 0,
    v(f,0,'x'), v(f,1,'y'), v(f,2,'z'), 0,
    v(u,0,'x'), v(u,1,'y'), v(u,2,'z'), 0,
    v(a,0,'x'), v(a,1,'y'), v(a,2,'z'), 1,
  ]);
}

function applyMatrix(entity, m) {
  SetEntityMatrix(
    entity,
    m[4], m[5], m[6],
    m[0], m[1], m[2],
    m[8], m[9], m[10],
    m[12], m[13], m[14]
  );
}

function vec3Obj(vv) {
  if (Array.isArray(vv)) return {x:Number(vv[0]||0),y:Number(vv[1]||0),z:Number(vv[2]||0)};
  return {x:Number(vv?.x||0),y:Number(vv?.y||0),z:Number(vv?.z||0)};
}

function showHelp() {
  BeginTextCommandDisplayHelp('STRING');
  AddTextComponentSubstringPlayerName('~b~FiveEMS 3D Gizmo~s~~n~Setas: mover  |  PgUp/PgDn: subir/descer  |  Q/E: girar~n~G: modo mover  |  R: gizmo rotacao  |  L: local/world~n~Mouse esquerdo: arrastar eixo  |  ENTER: salvar  |  BACKSPACE: cancelar');
  EndTextCommandDisplayHelp(0, false, true, 1);
}

function cleanup(cancelled) {
  if (!active) return;
  const e = active.entity;
  if (DoesEntityExist(e)) {
    if (!IsEntityAPed(e)) SetEntityDrawOutline(e, false);
    if (active.pedAlpha !== null) SetEntityAlpha(e, active.pedAlpha, false);
  }
  if (active.playerFrozen !== null && DoesEntityExist(PlayerPedId())) {
    FreezeEntityPosition(PlayerPedId(), active.playerFrozen);
  }
  const result = {
    requestId: active.requestId,
    confirmed: !cancelled,
    cancelled: !!cancelled,
    entity: e,
    position: DoesEntityExist(e) ? vec3Obj(GetEntityCoords(e, false)) : null,
    rotation: DoesEntityExist(e) ? vec3Obj(GetEntityRotation(e, 2)) : null,
  };
  active = null;
  emit('fiveems:gizmo:result', JSON.stringify(result));
}

on('fiveems:gizmo:start', (payloadJson) => {
  try {
    const payload = typeof payloadJson === 'string' ? JSON.parse(payloadJson) : payloadJson;
    const entity = Number(payload?.entity || 0);
    if (!entity || !DoesEntityExist(entity) || active) {
      emit('fiveems:gizmo:result', JSON.stringify({requestId:payload?.requestId,confirmed:false,cancelled:true,error:'invalid_entity'}));
      return;
    }
    const isPed = IsEntityAPed(entity);
    active = {
      requestId: payload.requestId,
      entity,
      matrix: makeMatrix(entity),
      playerFrozen: IsEntityPositionFrozen(PlayerPedId()),
      pedAlpha: isPed ? GetEntityAlpha(entity) : null,
    };
    FreezeEntityPosition(PlayerPedId(), true);
    if (isPed) {
      SetEntityAlpha(entity, 210, false);
    } else {
      SetEntityDrawOutlineColor(80, 210, 255, 255);
      SetEntityDrawOutline(entity, true);
    }
  } catch (e) {
    emit('fiveems:gizmo:result', JSON.stringify({confirmed:false,cancelled:true,error:String(e)}));
  }
});

RegisterCommand('+gizmoSelect', () => {}, false);
RegisterCommand('-gizmoSelect', () => {}, false);
RegisterCommand('+gizmoTranslation', () => {}, false);
RegisterCommand('-gizmoTranslation', () => {}, false);
RegisterCommand('+gizmoRotation', () => {}, false);
RegisterCommand('-gizmoRotation', () => {}, false);
RegisterCommand('+gizmoLocal', () => {}, false);
RegisterCommand('-gizmoLocal', () => {}, false);
RegisterKeyMapping('+gizmoSelect', 'FiveEMS Gizmo - selecionar eixo', 'MOUSE_BUTTON', 'MOUSE_LEFT');
RegisterKeyMapping('+gizmoTranslation', 'FiveEMS Gizmo - mover', 'keyboard', 'G');
RegisterKeyMapping('+gizmoRotation', 'FiveEMS Gizmo - rotacionar', 'keyboard', 'R');
RegisterKeyMapping('+gizmoLocal', 'FiveEMS Gizmo - local/world', 'keyboard', 'L');

RegisterCommand('+gizmoNudgeLeft', () => { nudge.left = true; }, false);
RegisterCommand('-gizmoNudgeLeft', () => { nudge.left = false; }, false);
RegisterCommand('+gizmoNudgeRight', () => { nudge.right = true; }, false);
RegisterCommand('-gizmoNudgeRight', () => { nudge.right = false; }, false);
RegisterCommand('+gizmoNudgeUp', () => { nudge.up = true; }, false);
RegisterCommand('-gizmoNudgeUp', () => { nudge.up = false; }, false);
RegisterCommand('+gizmoNudgeDown', () => { nudge.down = true; }, false);
RegisterCommand('-gizmoNudgeDown', () => { nudge.down = false; }, false);
RegisterCommand('+gizmoNudgeUpZ', () => { nudge.upZ = true; }, false);
RegisterCommand('-gizmoNudgeUpZ', () => { nudge.upZ = false; }, false);
RegisterCommand('+gizmoNudgeDownZ', () => { nudge.downZ = true; }, false);
RegisterCommand('-gizmoNudgeDownZ', () => { nudge.downZ = false; }, false);
RegisterKeyMapping('+gizmoNudgeLeft', 'FiveEMS Gizmo - mover esquerda', 'keyboard', 'LEFT');
RegisterKeyMapping('+gizmoNudgeRight', 'FiveEMS Gizmo - mover direita', 'keyboard', 'RIGHT');
RegisterKeyMapping('+gizmoNudgeUp', 'FiveEMS Gizmo - mover frente', 'keyboard', 'UP');
RegisterKeyMapping('+gizmoNudgeDown', 'FiveEMS Gizmo - mover tras', 'keyboard', 'DOWN');
RegisterKeyMapping('+gizmoNudgeUpZ', 'FiveEMS Gizmo - subir', 'keyboard', 'PAGEUP');
RegisterKeyMapping('+gizmoNudgeDownZ', 'FiveEMS Gizmo - descer', 'keyboard', 'PAGEDOWN');
RegisterCommand('+gizmoRotateLeft', () => { nudge.rotLeft = true; }, false);
RegisterCommand('-gizmoRotateLeft', () => { nudge.rotLeft = false; }, false);
RegisterCommand('+gizmoRotateRight', () => { nudge.rotRight = true; }, false);
RegisterCommand('-gizmoRotateRight', () => { nudge.rotRight = false; }, false);
RegisterKeyMapping('+gizmoRotateLeft', 'FiveEMS Gizmo - girar esquerda', 'keyboard', 'Q');
RegisterKeyMapping('+gizmoRotateRight', 'FiveEMS Gizmo - girar direita', 'keyboard', 'E');

function applyNudge(entity) {
  const pos = vec3Obj(GetEntityCoords(entity, false));
  const rot = vec3Obj(GetEntityRotation(entity, 2));
  const [forwardRaw, rightRaw] = GetEntityMatrix(entity);
  const forward = vec3Obj(forwardRaw);
  const right = vec3Obj(rightRaw);
  const step = IsControlPressed(0, 21) ? 0.05 : 0.015;
  const rotStep = IsControlPressed(0, 21) ? 2.5 : 0.75;
  let dx = 0.0;
  let dy = 0.0;
  let dz = 0.0;

  // Setas seguem os eixos intuitivos da entidade:
  // cima/baixo = frente/tras; esquerda/direita = lateral.
  if (nudge.up) { dx += forward.x * step; dy += forward.y * step; }
  if (nudge.down) { dx -= forward.x * step; dy -= forward.y * step; }
  if (nudge.left) { dx -= right.x * step; dy -= right.y * step; }
  if (nudge.right) { dx += right.x * step; dy += right.y * step; }
  if (nudge.upZ) dz += step;
  if (nudge.downZ) dz -= step;
  if (dx !== 0.0 || dy !== 0.0 || dz !== 0.0) {
    SetEntityCoordsNoOffset(entity, pos.x + dx, pos.y + dy, pos.z + dz, false, false, false);
  }

  let yaw = rot.z;
  if (nudge.rotLeft) yaw += rotStep;
  if (nudge.rotRight) yaw -= rotStep;
  if (yaw !== rot.z) SetEntityRotation(entity, rot.x, rot.y, yaw, 2, true);
}

setTick(() => {
  if (!active) return;
  const e = active.entity;
  if (!DoesEntityExist(e)) {
    cleanup(true);
    return;
  }
  DisablePlayerFiring(PlayerId(), true);
  DisableControlAction(0, 24, true);
  DisableControlAction(0, 25, true);
  DisableControlAction(0, 30, true);
  DisableControlAction(0, 31, true);
  DisableControlAction(0, 32, true);
  DisableControlAction(0, 33, true);
  DisableControlAction(0, 34, true);
  DisableControlAction(0, 35, true);
  DisableControlAction(0, 38, true);
  DisableControlAction(0, 44, true);
  showHelp();
  active.matrix = makeMatrix(e);
  const changed = DrawGizmo(active.matrix, `FiveEMS_${active.requestId}`);
  if (changed) applyMatrix(e, active.matrix);
  applyNudge(e);
  if (IsDisabledControlJustReleased(0, 191) || IsControlJustReleased(0, 191)) cleanup(false);
  if (IsDisabledControlJustReleased(0, 177) || IsControlJustReleased(0, 177) || IsDisabledControlJustReleased(0, 200)) cleanup(true);
});
