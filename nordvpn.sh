#!/bin/sh

###
# Script for keeping OpenVPN connected to the recommended NordVPN server on OpenWRT
#
# NordVPN API documentation by Milosz Galazka, at: https://blog.sleeplessbeastie.eu/2019/02/18/how-to-use-public-nordvpn-api/
#
# Uri Shani, 2020
###

function get_recommended() {
    echo "Getting list of recommended servers"
    RECOMMENDED=$(curl "https://api.nordvpn.com/v1/servers/recommendations?filter\[server_groups\]\[identifier\]=legacy_p2p" | jsonfilter -e '$[0].hostname')
}

function get_configs() {
    # wget https://downloads.nordcdn.com/configs/archives/servers/ovpn.zip
    eval wget https://downloads.nordcdn.com/configs/files/ovpn_udp/servers/$1.udp.ovpn
}

function check_in_configs() {
    SERVER_NAME=$(cat /etc/config/openvpn | grep -B 1 $RECOMMENDED | awk '/config openvpn/{print $3}')
}

function check_enabled() {
    ENABLED_SERVER=$(cat /etc/config/openvpn | grep -C 2 "enabled '1'" | awk '/config openvpn/{print $3}')
}

function unzip_and_edit_in_place() {
    # unzip -jo ovpn.zip "ovpn_udp/$RECOMMENDED.udp.ovpn" -d /etc/openvpn/
    get_configs $RECOMMENDED
    mv $RECOMMENDED.udp.ovpn /etc/openvpn/
    sed -i "s/auth-user-pass/auth-user-pass secret/g" /etc/openvpn/$RECOMMENDED.udp.ovpn
}

function create_new_entry() {
    NEW_SERVER=$(echo "$RECOMMENDED" | sed 's/\./_/g' | sed 's/com/udp/g')
    uci set openvpn.$NEW_SERVER=openvpn
    uci set openvpn.$NEW_SERVER.config="/etc/openvpn/$RECOMMENDED.udp.ovpn"
    uci commit openvpn
}

function enable_existing_entry() {
    eval uci set openvpn.$1.enabled='1'
    uci commit openvpn
}

function disable_current_entry() {
    eval uci del openvpn.$1.enabled
    uci commit openvpn
}

function restart_openvpn() {
    /etc/init.d/openvpn restart
}

### RUN ###
get_recommended
if [ -z "$RECOMMENDED" ]; then
    echo "Could not get recommended server, exiting script"
    exit
fi
echo $RECOMMENDED
check_in_configs
if [ -z "$SERVER_NAME" ]; then
    echo "Server does not exist"
    # if test ! -f "ovpn.zip"; then
    #     echo "Downloading configs..."
    #     get_configs
    # fi
    echo "Copying and adding to OpenVPN configs"
    unzip_and_edit_in_place
    echo "Adding new entry to OpenVPN configs and enabling the new entry"
    create_new_entry
else
    echo "Server name: $SERVER_NAME"
fi
check_enabled
echo $ENABLED_SERVER
if [ $ENABLED_SERVER == $SERVER_NAME ]; then
    echo "Recommended server is already configured as active"
    exit
else
    if [ -z "$NEW_SERVER" ]; then
        echo "Enabling existing entry"
        enable_existing_entry $SERVER_NAME
    else
        echo "Enabling new entry"
        enable_existing_entry $NEW_SERVER
    fi
    echo "Disabling current active server and enabling the recommended one"
    disable_current_entry $ENABLED_SERVER
fi
echo "Restarting OpenVPN"
restart_openvpn
