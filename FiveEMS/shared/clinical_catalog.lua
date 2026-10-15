FiveEMS = FiveEMS or {}

FiveEMS.Clinical = FiveEMS.Clinical or {}

FiveEMS.Clinical.regions = {
    head       = {label='Cabeça', x=50, y=8},
    neck       = {label='Pescoço', x=50, y=18},
    chest      = {label='Tórax', x=50, y=31},
    abdomen    = {label='Abdome', x=50, y=43},
    pelvis     = {label='Pelve', x=50, y=54},
    left_arm   = {label='Braço esquerdo', x=28, y=34},
    right_arm  = {label='Braço direito', x=72, y=34},
    left_leg   = {label='Perna esquerda', x=41, y=73},
    right_leg  = {label='Perna direita', x=59, y=73},
    left_foot  = {label='Pé esquerdo', x=43, y=90},
    right_foot = {label='Pé direito', x=57, y=90},
}

FiveEMS.Clinical.vitalMeasurements = {
    pulse = {label='Pulso / FC', equipment=nil, values={'hr'}},
    respiratory_rate = {label='Frequencia respiratoria', equipment=nil, values={'rr'}},
    blood_pressure = {label='Pressao arterial', equipment='bp_cuff', values={'sys','dia'}},
    spo2 = {label='SpO2', equipment='pulse_oximeter', values={'spo2'}},
    temperature = {label='Temperatura', equipment='thermometer', values={'temp'}},
    gcs = {label='Glasgow / GCS', equipment=nil, values={'gcs'}},
    auscultation = {label='Ausculta pulmonar', equipment='stethoscope', values={}},
}

FiveEMS.Clinical.xabcde = {
    X = {label='Hemorragia exsanguinante', regions={'neck','chest','abdomen','pelvis','left_arm','right_arm','left_leg','right_leg','left_foot','right_foot'}},
    A = {label='Via aerea / coluna', regions={'head','neck'}},
    B = {label='Respiracao', regions={'chest'}},
    C = {label='Circulacao', regions={'chest','abdomen','pelvis','left_arm','right_arm','left_leg','right_leg','left_foot','right_foot'}},
    D = {label='Neurologico', regions={'head'}},
    E = {label='Exposicao / ambiente', regions={'head','neck','chest','abdomen','pelvis','left_arm','right_arm','left_leg','right_leg','left_foot','right_foot'}},
}

-- Compatibilidade de tratamento por regiao/achado. A validacao final continua server-side.
FiveEMS.Clinical.treatmentRegions = {
    direct_pressure = {'head','neck','chest','abdomen','pelvis','left_arm','right_arm','left_leg','right_leg','left_foot','right_foot'},
    wound_pack = {'neck','chest','abdomen','pelvis','left_arm','right_arm','left_leg','right_leg','left_foot','right_foot'},
    pressure_bandage = {'head','neck','chest','abdomen','pelvis','left_arm','right_arm','left_leg','right_leg','left_foot','right_foot'},
    tourniquet = {'left_arm','right_arm','left_leg','right_leg','left_foot','right_foot'},
    chest_seal = {'chest'},
    splint = {'left_arm','right_arm','left_leg','right_leg','left_foot','right_foot'},
    c_collar = {'neck'},
    airway_opa = {'head','neck'},
    suction = {'head','neck'},
    iv_access = {'left_arm','right_arm'},
    thermal_blanket = {'head','neck','chest','abdomen','pelvis','left_arm','right_arm','left_leg','right_leg','left_foot','right_foot'},
    burn_dressing = {'head','neck','chest','abdomen','pelvis','left_arm','right_arm','left_leg','right_leg','left_foot','right_foot'},
}

FiveEMS.Clinical.bagLoadout = {
    stethoscope=1,
    bp_cuff=1,
    pulse_oximeter=1,
    thermometer=1,
    pressure_bandage=4,
    wound_pack=2,
    tourniquet=2,
    chest_seal=2,
    c_collar=1,
    splint=2,
    opa=2,
    suction_kit=1,
    bvm=1,
    oxygen_mask=1,
    non_rebreather=1,
    iv_kit=2,
    saline=1,
    thermal_blanket=1,
    burn_dressing=2,
}

FiveEMS.Clinical.nonConsumableItems = {
    stethoscope=true,
    bp_cuff=true,
    pulse_oximeter=true,
    thermometer=true,
    bvm=true,
    suction_kit=true,
}
