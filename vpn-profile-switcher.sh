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
OVPN_PATH="/etc/openvpn"
SECRET="secret"
VPN_PROVIDER="nordvpn"

function show_usage() {
    printf "Usage: $0 [options <parameters>]\n"
    printf "\n"
    printf "Options: \n"
    printf "  -h | --help,\t\t\t\t\tPrint this help message\n"
    printf "  -p | --protocol < udp | tcp >,\t\tSelect either UDP or TCP connection. Default is UDP.\n"
    printf "  -c | --country < name | abbreviation >,\tSelect Country to filter by. Default is closest to your location.\n"
    printf "  -g | --group < group_name >,\t\t\tSelect group to filter by.\n"
    printf "  -l | --login-info < filename >,\t\tSpecify file for VPN login credentials. Default is 'secret'.\n"
    printf "  -d | --directory < /config/path >,\t\tSpecify path for storing OpenVPN configurations. Default is /etc/openvpn.\n"
    printf "  -s | --save-configs,\t\t\t\tSpecify if configuration files are stored on device. Requires approx. 26MB and unzip.\n"

    exit
}

function check_required() {
    CURL=$(which curl)
    WGET=$(which wget)
    JSONFILTER=$(which jsonfilter)
    UNZIP=$(which unzip)

    if [ ! $CURL ] || [ ! $WGET ] || [ ! $JSONFILTER ] || [ ! $UNZIP ]; then
        printf "You must have the required packages installed: curl unzip\n"
        exit 1
    fi
}

function country_city_code() {
    IDENTIFIER=$(curl --silent "https://raw.githubusercontent.com/urishx/vpn-profile-switcher/db/countries.tsv" | grep -iw "$1" | awk -F '\t' '/[0-9]+/{print $1}')

    if [ -z "$IDENTIFIER" ]; then
        logger -s "The query you entered ("$1") could not be found in the countries databse."
        exit 1
    else
        echo "$IDENTIFIER"
    fi
}

function server_groups() {
    IDENTIFIER=$(curl --silent "https://raw.githubusercontent.com/urishx/vpn-profile-switcher/db/server-groups.tsv" | grep -iw "$1" | awk -F '\t' '/.*/{print $2}')

    if [ -z "$IDENTIFIER" ]; then
        logger -s "The query you entered ("$1") could not be found in the server groups databse."
        exit 1
    else
        echo "$IDENTIFIER"
    fi
}

function get_recommended() {
    echo $PROTOCOL $VPN_PROVIDER $COUNTRY_ID $CITY_ID $GROUP_IDENTIFIER $SECRET $OVPN_PATH $SAVE_CONFIGS
    echo "Getting list of recommended servers"
    URL="https://api.nordvpn.com/v1/servers/recommendations?"
    if [ ! -z "$GROUP_IDENTIFIER" ]; then
        URL=${URL}"filters\[servers_groups\]\[identifier\]="${GROUP_IDENTIFIER}"&"
    fi
    if [ ! -z "$COUNTRY_ID" ]; then
        URL=${URL}"filters\[country_id\]="${COUNTRY_ID}"&"
    fi
    URL=${URL}"limit=1"
    logger -s "Fetching VPN recommendations from: $URL"
    RECOMMENDED=$(curl --silent "$URL" | jsonfilter -e '$[0].hostname')
}

function get_configs() {
    # wget https://downloads.nordcdn.com/configs/archives/servers/ovpn.zip
    eval wget -q https://downloads.nordcdn.com/configs/files/ovpn_$PROTOCOL/servers/$1.$PROTOCOL.ovpn
}

function check_in_configs() {
    # Config files: uci show openvpn | grep nordvpn | awk -F '=' '/config/{print $2}' | sed "s/'//g"
    # Config name: uci show openvpn | grep $RECOMMENDED.$PROTOCOL | awk -F '\.' '/config/{print $2}'
    SERVER_NAME=$(cat /etc/config/openvpn | grep -B 1 $RECOMMENDED.$PROTOCOL | awk '/config openvpn/{print $3}')
}

function check_enabled() {
    # uci show openvpn | grep "enabled='1'" | awk -F '\.' '/.*/{print $2}'
    ENABLED_SERVER=$(cat /etc/config/openvpn | grep -B 2 "enabled '1'" | awk '/config openvpn/{print $3}')
}

function unzip_and_edit_in_place() {
    # consider using bsdtar eg.: bsdtar -x -f ovpn.zip ovpn_*/il53*udp*
    # unzip -jo ovpn.zip "ovpn_udp/$RECOMMENDED.udp.ovpn" -d /etc/openvpn/
    get_configs $RECOMMENDED
    mv $RECOMMENDED.$PROTOCOL.ovpn /etc/openvpn/
    sed -i "s/auth-user-pass/auth-user-pass secret/g" /etc/openvpn/$RECOMMENDED.$PROTOCOL.ovpn
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
        COUNTRY_ID=$(country_city_code $1 "country")
        ;;
    -g | --group)
        shift
        GROUP_IDENTIFIER=$(server_groups $1)
        ;;
    -l | --login-info)
        shift
        SECRET="$1"
        ;;
    -d | --directory)
        shift
        OVPN_PATH="$1"
        ;;
    -s | --save-configs)
        SAVE_CONFIGS=true
        ;;
    *)
        echo "Incorrect input provided"
        show_usage
        ;;
    esac
    shift
done

get_recommended
if [ -z "$RECOMMENDED" ]; then
    logger -s "Could not get recommended VPN, exiting script"
    exit
fi
logger -s "Recommended server URL: $RECOMMENDED. Protocol: $PROTOCOL"
check_in_configs
if [ -z "$SERVER_NAME" ]; then
    echo "Server does not exist"
    # if test ! -f "ovpn.zip"; then
    #     echo "Downloading configs..."
    #     get_configs
    # fi
    logger -s "Copying and adding to OpenVPN configs"
    unzip_and_edit_in_place
    logger -s "Adding new entry to OpenVPN configs"
    create_new_entry
else
    logger -s "Server name: $SERVER_NAME"
fi
check_enabled
logger -s "Currently active server: $ENABLED_SERVER"
if [ "$ENABLED_SERVER" == "$SERVER_NAME" ]; then
    logger -s "Recommended server is already configured as active"
    exit
else
    if [ -z "$NEW_SERVER" ]; then
        logger -s "Enabling existing entry"
        enable_existing_entry $SERVER_NAME
    else
        logger -s "Enabling new entry"
        enable_existing_entry $NEW_SERVER
    fi
    logger -s "Disabling current active server"
    disable_current_entry $ENABLED_SERVER

    uci commit openvpn
fi
logger -s "Restarting OpenVPN"
restart_openvpn
