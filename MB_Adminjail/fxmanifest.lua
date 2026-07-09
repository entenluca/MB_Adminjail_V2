fx_version 'cerulean'
game 'gta5'

lua54 'yes'

author 'Max Berger FiveM Development'
description 'MB_Adminjail - Adminjail Tablet System with uploaded UI'
version '1.4.2'

dependencies {
    'ox_lib'
}

ui_page 'html/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    'server.lua'
}

files {
    'html/index.html',
    'html/assets/*'
}
