#!/bin/sh

###
# vpn-profile-switcher.sh v1.0.0
#
# Script for getting the recommended NordVPN server, downloading the server's OpenVPN config file,
# setting credentials, and configuring OpenWRT for using said server.
#
# For more details see README on: https://github.com/UriShX/vpn-profile-switcher
# or run ./vpn-profile-switcher.sh -h
#
# Written by Uri Shani, 2021
# MIT License
#
# NordVPN API documentation by Milosz Galazka, at: https://blog.sleeplessbeastie.eu/2019/02/18/how-to-use-public-nordvpn-api/
###

set -e

PROTOCOL="udp"
SECRET="secret"

function show_usage() {
    printf "vpn-profile-switcher.sh v1.0.0\n"
    printf "Get NordVPN recommended profile and set OpenVPN on OpenWRT to use said profile.\n\n"
    printf "Usage: $0 [options <parameters>]\n\n"
    printf "Options: \n"
    printf "  -h | --help,\t\t\t\tPrint this help message\n"
    printf "  -p | --protocol < udp | tcp >,\tSelect either UDP or TCP connection. Default is UDP.\n"
    printf "  -c | --country < code | name >,\tSelect Country to filter by. Default is closest to your location.\n"
    printf "  -g | --group < group_name >,\t\tSelect group to filter by.\n"
    printf "  -l | --login-info < filename >,\tSpecify file for VPN login credentials. Default is 'secret'.\n"
    printf "\nFor more information see README in repo: https://github.com/UriShX/vpn-profile-switcher\n"

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

function verify_protocol() {
    if [ ! "$1" == "tcp" ] && [ ! "$1" == "udp" ]; then
        logger -s "($0) Protocol must be either udp or tcp, your input was: $1."
        exit 1
    else
        echo $1
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
        logger -s "($0) Not all server groups are available for OpenVPN connection, please check NordVPN's server recommendation site: https://nordvpn.com/servers/tools/"
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
    RECOMMENDED=$(wget -q -O - "$URL" | jsonfilter -e '$[0].hostname') || true
}

function check_in_configs() {
    SERVER_NAME=$(uci show openvpn | grep $RECOMMENDED.$PROTOCOL | awk -F '\.' '/config/{print $2}')
}

function check_enabled() {
    ENABLED_SERVER=$(uci show openvpn | grep "enabled='1'" | awk -F '\.' '/.*/{print $2}')
}

function grab_and_edit_config() {
    wget -q https://downloads.nordcdn.com/configs/files/ovpn_$PROTOCOL/servers/$RECOMMENDED.$PROTOCOL.ovpn
    if [ ! -f "$RECOMMENDED.$PROTOCOL.ovpn" ]; then
        logger -s "($0) The recommended server profile could not be downloaded from NordVPN's servers, quitting."
        logger -s "($0) Not all server groups are available for OpenVPN connection, please check NordVPN's server recommendation site: https://nordvpn.com/servers/tools/"
        exit 1
    fi
    mv $RECOMMENDED.$PROTOCOL.ovpn /etc/openvpn/
    sed -i "s/auth-user-pass/auth-user-pass $SECRET/g" /etc/openvpn/$RECOMMENDED.$PROTOCOL.ovpn
}

function create_new_entry() {
    NEW_SERVER=$(echo "$RECOMMENDED" | sed 's/[\.\ -]/_/g' | eval sed 's/com/$PROTOCOL/g')
    uci set openvpn.$NEW_SERVER=openvpn
    uci set openvpn.$NEW_SERVER.config="/etc/openvpn/$RECOMMENDED.$PROTOCOL.ovpn"
}

function enable_existing_entry() {
    eval uci set openvpn.$1.enabled='1'
}

function disable_current_entry() {
    eval uci del openvpn.$1.enabled
}

function list_ovpn_configs() {
    uci show openvpn | grep nordvpn | while read y; do
        if [ "$1" == 'files' ]; then
            echo $(awk -F '=' '/config/{print $2}' | sed "s/'//g")
        elif [ "$1" == 'names' ]; then
            echo $(awk -F '.' '/config/{print $2}')
        else
            logger -s "($0) bad argument $1 in list_ovpn_configs()"
        fi
    done
}

function remove_unused() {
    NORDVPN_CONFIGS=$(list_ovpn_configs names)
    NORDVPN_FILES=$(list_ovpn_configs files)

    for X in $NORDVPN_CONFIGS; do
        if [ ! "$X" == "$SERVER_NAME" ] && [ ! "$X" == "$NEW_SERVER" ] && [ ! "$X" == "$ENABLED_SERVER" ]; then
            uci del openvpn.$X
        fi
    done

    uci commit

    if [ ! -z "$ENABLED_SERVER" ]; then
        ENABLED_FILE=$(uci show openvpn.$ENABLED_SERVER.config | awk -F '=' '{print $2}' | sed "s/'//g")
    fi
    if [ ! -z "$SERVER_NAME" ]; then
        EXISTING_FILE=$(uci show openvpn.$SERVER_NAME.config | awk -F '=' '{print $2}' | sed "s/'//g")
    fi
    if [ ! -z "$NEW_SERVER" ]; then
        NEW_FILE=$(uci show openvpn.$NEW_SERVER.config | awk -F '=' '{print $2}' | sed "s/'//g")
    fi

    for X in $NORDVPN_FILES; do
        if [ ! "$X" == "$ENABLED_FILE" ] && [ ! "$X" == "$EXISTING_FILE" ] && [ ! "$X" == "$NEW_FILE" ]; then
            rm $X
        fi
    done
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
        PROTOCOL=$(verify_protocol $1)
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

logger -s "($0) Arguments: Protocol: $PROTOCOL; Country: $COUNTRY_ID; NordVPN group: $GROUP_IDENTIFIER; User credentials: $SECRET."

get_recommended

if [ -z "$RECOMMENDED" ]; then
    logger -s "($0) Could not get recommended VPN, exiting script"
    logger -s "($0) This might be due to a group + country combination, or server group which is not supported by OpenVPN connection."
    logger -s "($0) Please see NordVPN's server recommendation site, to tune your request: https://nordvpn.com/servers/tools/"
    exit
fi

logger -s "($0) Recommended server URL: $RECOMMENDED."

check_in_configs

if [ -z "$SERVER_NAME" ]; then
    logger -s "($0) Fetching OpenVPN config $RECOMMENDED.$PROTOCOL.ovpn, and setting credentials"
    grab_and_edit_config
    create_new_entry
    logger -s "($0) Entered new entry to OpenVPN configs: $NEW_SERVER"
else
    logger -s "($0) Recommended server name: $SERVER_NAME"
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

logger -s "($0) Removing unused NordVPN profiles, leaving current and last used."
remove_unused
