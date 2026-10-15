FiveEMS = FiveEMS or {}

FiveEMS.DepartmentTypes = {
    EMS = 'ems',
    HOSPITAL = 'hospital',
    CSI = 'csi',
}

FiveEMS.PointTypes = {
    BLIP = 'blip',
    DUTY = 'duty',
    SUPPLY = 'supply',
    GARAGE = 'garage',
    DIRECTOR = 'director',
    COMPUTER = 'computer',
    TABLET = 'tablet',
    MONITOR = 'monitor',
    BED = 'bed',
    SURGERY = 'surgery',
    IML = 'iml',
    OTHER = 'other',
    STRETCHER = 'stretcher',
    LAB = 'lab',
    EVIDENCE_LOCKER = 'evidence_locker',
}

FiveEMS.PermissionKeys = {
    'department.manage',
    'staff.manage',
    'ranks.manage',
    'garage.use',
    'garage.manage',
    'supplies.use',
    'supplies.manage',
    'patient.assess',
    'patient.treat',
    'patient.advanced',
    'reports.create',
    'reports.view',
    'stock.view',
    'stock.manage',
    'monitor.use',
    'defib.use',
    'csi.scene',
    'csi.collect',
    'csi.lab',
    'admin.settings',
}

FiveEMS.Rhythms = {
    SINUS = 'sinus',
    TACHY = 'tachy',
    BRADY = 'brady',
    VF = 'vf',
    PVT = 'pvt',
    ASYSTOLE = 'asystole',
    PEA = 'pea',
}
