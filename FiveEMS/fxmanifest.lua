fx_version 'cerulean'
game 'gta5'
name 'FiveEMS'
author "Sasori's Development / FiveEMS"
description 'FiveEMS integrado nativamente a framework FivePD SP: character, records, inventory, injuries, death, admin e UI.'
version '0.5.1d'
ui_page 'web/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/constants.lua',
    'shared/medical_catalog.lua',
    'shared/clinical_catalog.lua',
    'shared/locales.lua'
}

client_scripts {
    'client/main.lua',
    'client/placement_editor.lua',
    'client/gizmo.js',
    'client/framework.lua',
    'client/zones.lua',
    'client/damage.lua',
    'client/npc_persistence.lua',
    'client/medical.lua',
    'client/clinical.lua',
    'client/bed_chart.lua',
    'client/monitor.lua',
    'client/portable_monitor.lua',
    'client/field_equipment.lua',
    'client/stretcher.lua',
    'client/csi.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/db.lua',
    'server/framework.lua',
    'server/main.lua',
    'server/departments.lua',
    'server/progression.lua',
    'server/medical.lua',
    'server/clinical.lua',
    'server/portable_monitor.lua',
    'server/field_equipment.lua',
    'server/calls.lua',
    'server/csi.lua',
    'server/admin.lua',
    'server/npc_persistence.lua',
    'server/commands.lua'
}

files {
    'web/index.html',
    'web/styles.css',
    'web/app.js',
    'web/assets/fiveems-banner.png',
    'web/assets/fiveems-wordmark.png',
    'web/assets/fiveems-shield.png',
    'stream/lifepak15.ydr',
    'stream/combicarrier2.ydr',
    'stream/fernocot.ydr',
    'stream/loweredfernocot.ydr',
    'stream/sittingfernocot.ydr',
    'stream/fernotexture.ytd',
    'stream/strykergurney.ydr',
    'stream/loweredstrykergurney.ydr',
    'stream/sittingstrykergurney.ydr',
    'stream/strykertexture.ytd',
    'stream/lucas2.ydr',
    'stream/lucas3.ydr',
    'stream/ems_props.ytyp',
    'sql/fiveems.sql'
}

data_file 'DLC_ITYP_REQUEST' 'stream/ems_props.ytyp'

dependencies {
    'oxmysql',
    'ox_lib',
    'fivepd_sp_database',
    'fivepd_sp_core',
    'fivepd_sp_records',
    'fivepd_sp_inventory',
    'fivepd_sp_injuries',
    'fivepd_sp_death',
    'fivepd_sp_admin',
    'fivepd_sp_ui',
    'ox_target'
}
