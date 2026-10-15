FiveEMS = FiveEMS or {}

FiveEMS.Locales = {
    ['pt-BR'] = {
        interact='Pressione ~INPUT_CONTEXT~ para interagir',
        no_permission='Voce nao tem permissao para esta acao.',
        on_duty='Voce entrou em servico.',
        off_duty='Voce saiu de servico.',
        admin_title='Administracao FiveEMS',
        patient_title='Atendimento ao Paciente',
        monitor_title='Monitor Multiparametrico',
        report_submitted='Relatorio enviado com sucesso.',
        xp_gain='Voce recebeu %s XP.',
        no_department='Voce nao pertence a um departamento FiveEMS.',
        csi_evidence='Evidencia registrada: %s',
    },
    ['en'] = {
        interact='Press ~INPUT_CONTEXT~ to interact',
        no_permission='You do not have permission for this action.',
        on_duty='You are now on duty.',
        off_duty='You are now off duty.',
        admin_title='FiveEMS Administration',
        patient_title='Patient Care',
        monitor_title='Multiparameter Monitor',
        report_submitted='Report submitted successfully.',
        xp_gain='You received %s XP.',
        no_department='You are not assigned to a FiveEMS department.',
        csi_evidence='Evidence registered: %s',
    },
    ['es'] = {
        interact='Presiona ~INPUT_CONTEXT~ para interactuar',
        no_permission='No tienes permiso para esta accion.',
        on_duty='Has iniciado servicio.',
        off_duty='Has finalizado servicio.',
        admin_title='Administracion FiveEMS',
        patient_title='Atencion al Paciente',
        monitor_title='Monitor Multiparametro',
        report_submitted='Informe enviado correctamente.',
        xp_gain='Recibiste %s XP.',
        no_department='No perteneces a un departamento FiveEMS.',
        csi_evidence='Evidencia registrada: %s',
    }
}

function _L(key, ...)
    local locale = FiveEMS.Locales[Config.Locale] or FiveEMS.Locales['pt-BR']
    local text = locale[key] or key
    if select('#', ...) > 0 then
        return string.format(text, ...)
    end
    return text
end
