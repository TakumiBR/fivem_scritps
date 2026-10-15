Config = {}

Config.Locale = 'pt-BR'
Config.Debug = false
Config.DatabaseRequired = true
Config.Database = {
    autoInstall = true, -- cria/atualiza automaticamente as tabelas do FiveEMS ao iniciar
    autoSeedCatalogOnDepartmentCreate = true, -- cadastra o catalogo adequado ao criar um departamento
    startupTimeoutMs = 30000,
}
Config.AdminAce = 'fiveems.admin'
Config.AdminIdentifiers = {
    -- 'license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
}

-- Politica de comandos:
-- O gameplay normal deve acontecer por pontos, ox_target, garagem e interfaces.
-- Comandos operacionais ficam apenas como fallback para membros EMS em servico.
-- Comandos de diagnostico/manutencao sao exclusivos de administradores.
Config.CommandPolicy = {
    requireDutyForOperational = true,
    adminDebugCommands = true,
}

-- Nomes/aliases dos comandos visiveis.
-- Aceita mais de um alias separado por virgula. Ex.: '192,193,ems911'.
-- O Admin pode alterar estes valores em runtime; ficam persistidos no banco.
Config.Commands = {
    emergency = 'ems911',
    help = 'fiveemshelp',
    launcher = 'fiveems',
    computer = 'fiveemscomputer',
    tablet = 'fiveemstablet',
    exam = 'fiveemsexam',
    patient = 'fiveemspatient',
    monitor = 'fiveemsmonitor',
    director = 'fiveemsdirector',
    admin = 'fiveemsadmin',
    creator = 'fiveemscreator',
}

-- Protecao de NPCs feridos para que o population manager da FivePD SP / GTA
-- nao descarte uma vitima enquanto o EMS vai buscar maca/viatura.
Config.NpcPersistence = {
    enabled = true,
    scanRadius = 70.0,
    scanIntervalMs = 1500,
    persistMinutes = 20,
    injuredHealthRatio = 0.92,
    maxProtectedPerClient = 24,
}

Config.Framework = {
    mode = 'fivepd_sp', -- FiveEMS agora usa a framework FivePD SP como base canonica
    strict = true,
    adminPermission = 'gerenciar_staff', -- permissao existente no fivepd_sp_admin
    resources = {
        core = 'fivepd_sp_core',
        records = 'fivepd_sp_records',
        inventory = 'fivepd_sp_inventory',
        injuries = 'fivepd_sp_injuries',
        death = 'fivepd_sp_death',
        admin = 'fivepd_sp_admin',
        ui = 'fivepd_sp_ui',
        database = 'fivepd_sp_database',
        hospital = 'fivepd_sp_hospital',
        medical = 'fivepd_sp_medical',
        support = 'fivepd_sp_support',
        pc = 'fivepd_sp_pc',
        dhpp = 'fivepd_sp_dhpp',
    },
    -- Enquanto o catalogo do inventario da base nao recebe itens EMS dedicados,
    -- o FiveEMS entrega o item generico da framework com metadata fiveems_item.
    inventoryMap = {
        csi_gloves = 'luvas',
        oxygen_mask = 'mascara', nasal_cannula = 'mascara', non_rebreather = 'mascara', bvm = 'mascara',
        csi_evidence_bag = 'vestigio_lacrado',
        defaultMedical = 'medicamento',
        lifepak15_monitor = 'medicamento',
        defaultCsi = 'documento',
    },
}
Config.Inventory = 'fivepd_sp'
Config.Target = 'ox'

Config.Interaction = {
    drawDistance = 18.0,
    interactDistance = 1.8,
    markerType = 1,
    key = 38, -- E
}

Config.Progression = {
    reportSubmitted = 35,
    patientHandover = 25,
    successfulDefib = 40,
    completedAssessment = 12,
    treatment = 5,
    csiEvidenceBagged = 8,
    csiCaseClosed = 40,
    levelBaseXp = 150,
    levelGrowth = 1.35,
    maxLevel = 100,
}

Config.Calls = {
    enabled = true,
    minimumIntervalSeconds = 300,
    maximumIntervalSeconds = 720,
    useGeneratedNpcCalls = false, -- fica desligado ate a fase final de NPC persistente
    dispatchRadius = 80.0,
}

Config.Physiology = {
    tickMs = 2000,
    normalBloodMl = 5000,
    criticalBloodMl = 2500,
    arrestBloodMl = 1600,
    minSpo2 = 35,
    maxSpo2 = 100,
    baseTemperature = 36.8,
    bleedScale = 0.42,
    painDecayPerTick = 0.03,
}

Config.DamageMultipliers = {
    gunshot = 1.35,
    stabbing = 1.20,
    blunt = 0.85,
    vehicle = 1.10,
    fall = 1.00,
    explosion = 1.50,
    burn = 0.80,
    drowning = 1.00,
    unknown = 1.00,
}

Config.BodyRegions = {
    head = {functionalThreshold = 55},
    neck = {functionalThreshold = 60},
    chest = {functionalThreshold = 65},
    abdomen = {functionalThreshold = 65},
    pelvis = {functionalThreshold = 60},
    left_arm = {functionalThreshold = 58},
    right_arm = {functionalThreshold = 58},
    left_leg = {functionalThreshold = 55},
    right_leg = {functionalThreshold = 55},
    left_foot = {functionalThreshold = 55},
    right_foot = {functionalThreshold = 55},
}

Config.Oxygen = {
    devices = {
        nasal_cannula = {minFlow = 1, maxFlow = 6, defaultFlow = 2, efficiency = 0.34},
        simple_mask = {minFlow = 5, maxFlow = 10, defaultFlow = 6, efficiency = 0.55},
        non_rebreather = {minFlow = 10, maxFlow = 15, defaultFlow = 12, efficiency = 0.86},
        bvm = {minFlow = 10, maxFlow = 15, defaultFlow = 15, efficiency = 0.95},
    },
    hyperoxiaThreshold = 98,
    prolongedHighOxygenSeconds = 600,
    gameplayHyperoxiaEnabled = true,
}

Config.Defibrillator = {
    propModel = '', -- informe aqui o model do prop que voce possui
    defaultEnergy = 200,
    allowedEnergy = {120, 150, 200, 250, 300, 360},
    shockableRhythms = {
        vf = true,
        pvt = true,
    },
}

Config.Monitor = {
    beepEnabled = true,
    pulseVolume = 0.035,
    alarmVolume = 0.060,
    alarmRepeatMs = 1800,
    portable = {
        enabled = true,
        model = 'lifepak15',
        itemName = 'lifepak15_monitor',
        label = 'LIFEPAK 15',
        requireInventory = true,
        maxCableDistance = 5.5,
        openDistance = 4.0,
        deployDistance = 1.35,
        defaultHeadingOffset = 180.0,
    },
    alarms = {
        hrLow = 45,
        hrHigh = 140,
        spo2Low = 90,
        sysLow = 85,
        tempLow = 35.0,
        tempHigh = 39.5,
    }
}

Config.Stretcher = {
    defaultModel = 'strykerpro',
    carryDistance = 2.0,
    syncIntervalMs = 250,
    targetDistance = 2.5,

    -- Durante a conducao o ox_target fica indisponivel na propria maca.
    -- Esta tecla serve SOMENTE para soltar a maca. Nao pega a maca e nao muda a altura.
    releaseKey = 'H',

    -- Calibrado para o strykerpro enviado como referencia.
    -- O modelo e um CVehicle e precisa de rotacao/offset especificos ao conduzir.
    pushOffset = {
        -- Offset ORIGINAL do Stretcher-1.0.5 que posiciona corretamente as maos/ped na maca alta.
        x = -0.05, y = 1.375, z = -0.345,
        rx = 180.0, ry = 180.0, rz = 180.0,
    },

    -- A geometria alta (Extra 1) nao faz parte do contato de roda que o GTA usa para
    -- SetVehicleOnGroundProperly. Por isso precisamos levantar a entidade inteira depois
    -- de calcular o "chao" usando a geometria baixa (Extra 2).
    -- A geometria BAIXA ja esta homologada no chao.
    -- Pelos testes in-game, a geometria ALTA precisa de ~12 cm adicionais alem
    -- da primeira calibracao de 0.345 m para que os pes/rodas nao fiquem enterrados.
    heightCalibration = {
        highLift = 0.465,
        lowLift = 0.0,
    },

    -- Extras conhecidos do strykerpro.
    extras = {
        legA = 1,
        legB = 2,
        backboard = 3,
        monitor = 5,
        redBag = 6,
        blueBag = 7,
        headrestA = 11,
        headrestB = 12,
    },

    -- Estado em que a StrykerPro deve sair da garagem.
    -- "clean" = sem prancha/monitor/bolsas e com encosto abaixado.
    garagePreset = {
        legsHigh = true,
        backboard = false,
        monitor = false,
        redBag = false,
        blueBag = false,
        headrest = 'down',
    },

    -- Renderer final homologado na linha fisica do FiveFD:
    -- body_search em fase fixa + transform exclusivo da Stryker.
    -- O leito continua usando o ANCHOR world-space salvo no Creator.
    patientPose = {
        dict = 'anim@gangops@morgue@table@',
        anim = 'body_search',

        -- Fallback manual. Quando autoPhase=true o client procura, por modelo,
        -- o frame do body_search com pernas/bracos mais estendidos.
        phase = 0.46,
        autoPhase = true,

        repairIntervalMs = 700,
        defaultTransform = {
            x = 0.0, y = 0.08, z = 1.12,
            rx = 0.0, ry = 0.0, rz = 180.0,
        },
    },

    patientTransport = {
        -- Janela em que o client espera o mesmo NetID voltar a streamar
        -- durante troca de exterior <-> MLO/interior.
        streamGraceMs = 12000,

        -- Renova protecao/orphan mode enquanto o NPC esta na maca.
        refreshMs = 5000,

        -- Distancia para aparecer "Transferir NPC/Player" na maca.
        transferRadius = 7.5,
    },
}

Config.CSI = {
    evidenceLifetimeHours = 72,
    requireGloves = true,
    labAnalysisSeconds = 20,
    createEvidenceFromPlayerDamage = true,
    createEvidenceFromNpcDamage = true,
    defaultTools = {
        'csi_gloves', 'csi_camera', 'csi_evidence_bag', 'csi_swab_kit',
        'csi_uv_light', 'csi_ruler', 'csi_tweezers', 'csi_fingerprint_kit'
    }
}


-- Criador de garagens. Os IDs de marker usam DrawMarker nativo do GTA/FiveM.
Config.GarageCreator = {
    defaultBlip = { enabled = true, sprite = 225, color = 3, scale = 0.75 },
    defaultInteraction = { kind = 'marker', marker_type = 36, ped_model = 's_m_m_paramedic_01' },
    previewModels = {
        car = 'ambulance',
        motorcycle = 'policeb',
        aircraft = 'frogger',
        boat = 'dinghy',
        truck = 'mule',
        bus = 'bus',
    },
}


-- Equipamentos fisicos de cena / compartimento de ambulancia.
Config.FieldEquipment = {
    medicalBag = {
        itemName = 'medical_bag',
        label = 'Bolsa medica de atendimento',
        -- Primeiro modelo preferido + fallbacks nativos caso o servidor nao tenha um addon de bolsa.
        models = {'xm_prop_x17_bag_med_01a','prop_cs_heist_bag_02','prop_ld_health_pack'},
        deployDistance = 1.15,
        openDistance = 2.5,
        useDistance = 4.0,
        -- V0.4.12: transporte pela alca, em uma mao, usando a animacao de
        -- jerrycan/briefcase. Os valores abaixo sao calibrados para
        -- xm_prop_x17_bag_med_01a; fallbacks continuam funcionando.
        carry = {
            bone = 57005,
            x = 0.40, y = -0.08, z = -0.05,
            rx = 41.50, ry = -43.25, rz = -107.75,
            animDict = 'move_weapon@jerrycan@generic',
            animName = 'idle',
            animFlag = 51,
            patientSideOffset = 0.85,
        },
        vehicle = {
            -- Raio em torno do suporte fisico usado para Retirar/Guardar bolsa.
            -- O alvo e validado na carroceria da viatura para funcionar mesmo
            -- com o prop visual sem colisao.
            mountTargetRadius = 1.05,
            visualDistance = 85.0,
        },
    },
    vehicleCompartment = {
        -- V0.4.11: o compartimento deixou de usar a bolsa como marcador. A area
        -- e uma caixa 3D relativa ao veiculo, equivalente a um poly/zone movel.
        -- Isso acompanha a ambulancia sem recriar uma PolyZone estatica a cada frame.
        interactDistance = 3.75,
        openDistance = 4.0,
        defaultSize = {x = 1.20, y = 1.00, z = 1.10},
        previewModel = 'prop_cs_cardbox_01',
    },

    -- Equipamentos addon do pack EMS. O item continua no inventario enquanto
    -- o prop representa fisicamente o equipamento na cena (mesma filosofia do LIFEPAK).
    portableEquipment = {
        lucas2 = {
            itemName = 'lucas2_device',
            label = 'LUCAS 2 - Compressor toracico',
            model = 'lucas2',
            deployDistance = 1.15,
            openDistance = 2.5,
        },
        lucas3 = {
            itemName = 'lucas3_device',
            label = 'LUCAS 3 - Compressor toracico',
            model = 'lucas3',
            deployDistance = 1.15,
            openDistance = 2.5,
        },
        combicarrier = {
            itemName = 'combi_carrier',
            label = 'CombiCarrier II',
            model = 'combicarrier2',
            deployDistance = 1.25,
            openDistance = 2.8,
        },
    },

    -- Biblioteca de props de maca adicionados nesta build. Nao substituem o
    -- strykerpro operacional automaticamente: primeiro devem ser calibrados/testados.
    stretcherPropLibrary = {
        'fernocot', 'loweredfernocot', 'sittingfernocot',
        'strykergurney', 'loweredstrykergurney', 'sittingstrykergurney',
    },
}
