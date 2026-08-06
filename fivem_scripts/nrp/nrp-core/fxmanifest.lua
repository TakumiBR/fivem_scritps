fx_version '1'
game 'gta5'
lua54 'yes'

name 'nrp-core'
description 'Nação Roleplay Core Framework - Independente de QB/ESX/QBox'
author 'Nação RP'
version '1.0.0'

shared_scripts {
    'framework/shared/config.lua',
    'framework/shared/main.lua'
}

client_scripts {
    'framework/client/ui.lua',
    'framework/client/appearance.lua',
    'framework/client/hud.lua'
}

server_scripts {
    '@oxmysql/lib/exports.lua',
    'framework/server/player.lua',
    'framework/server/economy.lua',
    'framework/server/events.lua',
    'bridges/esx.lua',
    'bridges/qb.lua',
    'bridges/qbox.lua'
}

ui_page 'html/multichar/index.html'

files {
    'html/multichar/index.html',
    'html/multichar/style.css',
    'html/multichar/script.js',
    'html/creation/index.html',
    'html/creation/style.css',
    'html/creation/script.js'
}

dependencies {
    '/server:5848',
    'oxmysql'
}
