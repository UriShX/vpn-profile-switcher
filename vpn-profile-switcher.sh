#!/bin/sh

###
# Script for keeping OpenVPN connected to the recommended NordVPN server on OpenWRT
#
# NordVPN API documentation by Milosz Galazka, at: https://blog.sleeplessbeastie.eu/2019/02/18/how-to-use-public-nordvpn-api/
#
# Uri Shani, 2020
###

set -e

PROTOCOL="udp"
SECRET="secret"

function show_usage() {
    printf "Usage: $0 [options <parameters>]\n"
    printf "\n"
    printf "Options: \n"
    printf "  -h | --help,\t\t\t\t\tPrint this help message\n"
    printf "  -p | --protocol < udp | tcp >,\t\tSelect either UDP or TCP connection. Default is UDP.\n"
    printf "  -c | --country < name | abbreviation >,\tSelect Country to filter by. Default is closest to your location.\n"
    printf "  -g | --group < group_name >,\t\t\tSelect group to filter by.\n"
    printf "  -l | --login-info < filename >,\t\tSpecify file for VPN login credentials. Default is 'secret'.\n"

    exit
}

function check_required() {
    WGET=$(which wget)
    JSONFILTER=$(which jsonfilter)

    if [ ! $WGET ] || [ ! $JSONFILTER ]; then
        # wget: SSL support not available, please install one of the libustream-.*[ssl|tls] packages as well as the ca-bundle and ca-certificates packages.
        logger -s "($0) You must have the required packages installed: wget jsonfilter\n"
        exit 1
    fi
}

function country_code() {
    IDENTIFIER=$(wget -q -O - "https://raw.githubusercontent.com/urishx/vpn-profile-switcher/db/countries.tsv" | grep -iw "$1" | awk -F '\t' '/[0-9]+/{print $1}')

    if [ -z "$IDENTIFIER" ]; then
        logger -s "($0) The query you entered ("$1") could not be found in the countries databse."
        logger -s "($0) You can view the list of countries in which NordVPN has servers online: https://github.com/urishx/vpn-profile-switcher/blob/db/countries.tsv"
        exit 1
    else
        echo "$IDENTIFIER"
    fi
}

function server_groups() {
    IDENTIFIER=$(wget -q -O - "https://raw.githubusercontent.com/urishx/vpn-profile-switcher/db/server-groups.tsv" | grep -iw "$1" | awk -F '\t' '/.*/{print $2}')

    if [ -z "$IDENTIFIER" ]; then
        logger -s "($0) The query you entered ("$1") could not be found in the server groups databse."
        logger -s "($0) You can view the list of NordVPN server groups online: https://github.com/urishx/vpn-profile-switcher/blob/db/server-groups.tsv"
        exit 1
    else
        echo "$IDENTIFIER"
    fi
}

function get_recommended() {
    URL="https://api.nordvpn.com/v1/servers/recommendations?"
    if [ ! -z "$GROUP_IDENTIFIER" ]; then
        URL=${URL}"filters[servers_groups][identifier]="${GROUP_IDENTIFIER}"&"
    fi
    if [ ! -z "$COUNTRY_ID" ]; then
        URL=${URL}"filters[country_id]="${COUNTRY_ID}"&"
    fi
    URL=${URL}"limit=1"
    logger -s "($0) Fetching VPN recommendations from: $URL"
    RECOMMENDED=$(wget -q -O - "$URL" | jsonfilter -e '$[0].hostname')
}

function check_in_configs() {
    # Config files: uci show openvpn | grep nordvpn | awk -F '=' '/config/{print $2}' | sed "s/'//g"
    SERVER_NAME=$(uci show openvpn | grep $RECOMMENDED.$PROTOCOL | awk -F '\.' '/config/{print $2}')
}

function check_enabled() {
    ENABLED_SERVER=$(uci show openvpn | grep "enabled='1'" | awk -F '\.' '/.*/{print $2}')
}

function grab_and_edit_config() {
    wget -q https://downloads.nordcdn.com/configs/files/ovpn_$PROTOCOL/servers/$RECOMMENDED.$PROTOCOL.ovpn
    mv $RECOMMENDED.$PROTOCOL.ovpn /etc/openvpn/
    sed -i "s/auth-user-pass/auth-user-pass $SECRET/g" /etc/openvpn/$RECOMMENDED.$PROTOCOL.ovpn
}

function create_new_entry() {
    NEW_SERVER=$(echo "$RECOMMENDED" | sed 's/\./_/g' | eval sed 's/com/$PROTOCOL/g')
    uci set openvpn.$NEW_SERVER=openvpn
    uci set openvpn.$NEW_SERVER.config="/etc/openvpn/$RECOMMENDED.$PROTOCOL.ovpn"
}

function enable_existing_entry() {
    eval uci set openvpn.$1.enabled='1'
}

function disable_current_entry() {
    eval uci del openvpn.$1.enabled
}

function restart_openvpn() {
    uci commit openvpn
    /etc/init.d/openvpn restart
}

### RUN ###
# if [[ $# -gt 3 ]] || [[ $# -eq 0 ]]; then
#     echo "Either 0 or more than 3 input arguments provided which is not supported"
#     show_usage
#     exit 1
# fi

check_required

while [ ! -z "$1" ]; do
    case "$1" in
    -h | --help)
        show_usage
        ;;
    -p | --protocol)
        shift
        PROTOCOL="$1"
        ;;
    -c | --country)
        shift
        COUNTRY_ID=$(country_code $1)
        ;;
    -g | --group)
        shift
        GROUP_IDENTIFIER=$(server_groups $1)
        ;;
    -l | --login-info)
        shift
        SECRET="$1"
        ;;
    *)
        logger -s "($0) Incorrect input provided"
        show_usage
        ;;
    esac
    shift
done

logger -s "($0) Arguments: Protocol: $PROTOCOL; Country: $COUNTRY_ID; NordVPN group: $GROUP_IDENTIFIER; User secrets: $SECRET."

get_recommended

if [ -z "$RECOMMENDED" ]; then
    logger -s "($0) Could not get recommended VPN, exiting script"
    exit
fi

logger -s "($0) Recommended server URL: $RECOMMENDED."

check_in_configs

if [ -z "$SERVER_NAME" ]; then
    logger -s "($0) Fetching OpenVPN config $RECOMMENDED.$PROTOCOL.ovpn, and setting credentials"
    grab_and_edit_config
    logger -s "($0) Adding new entry to OpenVPN configs: $NEW_SERVER"
    create_new_entry
else
    logger -s "($0) Server name: $SERVER_NAME"
fi

check_enabled

logger -s "($0) Currently active server: $ENABLED_SERVER"

if [ "$ENABLED_SERVER" == "$SERVER_NAME" ]; then
    logger -s "($0) Recommended server is already configured as active"
    exit
else
    if [ -z "$NEW_SERVER" ]; then
        logger -s "($0) Enabling existing entry"
        enable_existing_entry $SERVER_NAME
    else
        logger -s "($0) Enabling new entry"
        enable_existing_entry $NEW_SERVER
    fi
    logger -s "($0) Disabling current active server"
    disable_current_entry $ENABLED_SERVER
fi

logger -s "($0) Comitting changes and restarting OpenVPN"

restart_openvpn
