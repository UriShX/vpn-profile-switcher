#!/bin/sh

###
# Script for keeping OpenVPN connected to the recommended NordVPN server on OpenWRT
#
# NordVPN API documentation by Milosz Galazka, at: https://blog.sleeplessbeastie.eu/2019/02/18/how-to-use-public-nordvpn-api/
#
# Uri Shani, 2020
###

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
    printf "  -V | --vpn < vpn_provider >,\t\t\tSelect vpn provider. Currently only NordVPN is supported.\n"
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
    JQ=$(which jq)
    JSONFILTER=$(which jsonfilter)
    UNZIP=$(which unzip)

    if [ ! $CURL ] || [ ! $WGET ] || [ ! $JQ ] || [ ! $JSONFILTER ] || [ ! $UNZIP ]; then
        printf "You must have the required packages installed: curl jq unzip\n"
        exit 1
    fi
}

function country_code() {
    case $1 in
    '' | *[!0-9]*)
        if [ ! -f "countries.tsv" ]; then
            if [ -z "$JQ" ]; then
                printf "Please either upload countries.tsv, or install the package jq and try again.\n"
                exit 1
            fi
            curl --silent "https://api.nordvpn.com/v1/servers/countries" | jq --raw-output '.[] | [.id, .code, .name] | @tsv' >countries.tsv
        fi

        IDENTIFIER=$(cat countries.tsv | grep "$1" | awk -F '\t' '/[0-9]+/{print $1}')
        echo "$IDENTIFIER"
        ;;
    *)
        if [ -z "$(cat countries.tsv | grep "$1")" ]; then
            printf "The code you entered ("$1") could not be found in the local databse.\n"
            exit 1
        fi
        echo "$1"
        ;;
    esac
}

function server_groups() {
    if [ ! -f "server-groups.tsv" ]; then
        if [ -z "$JQ" ]; then
            printf "Please either upload server-groups.tsv, or install the package jq and try again.\n"
            exit 1
        fi
        curl --silent "https://api.nordvpn.com/v1/servers/groups" | jq --raw-output '.[]  | [.id, .identifier, .title] | @tsv' >server-groups.tsv
    fi

    IDENTIFIER=$(cat server-groups.tsv | grep "$1" | awk -F '\t' '/.*/{print $2}')
    if [ -z "$IDENTIFIER" ]; then
        printf "The identifier you entered ("$1") could not be found in the local databse.\n"
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
        URL=${URL}"filters\[servers_groups\]\[identifier\]="
        URL=${URL}${GROUP_IDENTIFIER}
        URL=${URL}"&"
    fi
    if [ ! -z "$COUNTRY_ID" ]; then
        URL=${URL}"filters\[country_id\]="
        URL=${URL}${COUNTRY_ID}
        URL=${URL}"&"
    fi
    URL=${URL}"limit=1"
    echo $URL
    RECOMMENDED=$(curl --silent "$URL" | jsonfilter -e '$[0].hostname')
}

function get_configs() {
    # wget https://downloads.nordcdn.com/configs/archives/servers/ovpn.zip
    eval wget -q https://downloads.nordcdn.com/configs/files/ovpn_$PROTOCOL/servers/$1.$PROTOCOL.ovpn
}

function check_in_configs() {
    SERVER_NAME=$(cat /etc/config/openvpn | grep -B 1 $RECOMMENDED | awk '/config openvpn/{print $3}')
}

function check_enabled() {
    ENABLED_SERVER=$(cat /etc/config/openvpn | grep -C 2 "enabled '1'" | awk '/config openvpn/{print $3}')
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
    -V | --vpn)
        shift
        if [ ! "$1" == VPN_PROVIDER ]; then
            echo "Script currently supports only NordVPN."
            exit 1
        fi
        # VPN_PROVIDER="$1"
        ;;
    -c | --country)
        shift
        COUNTRY_ID=$(country_code $1 "country")
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
    echo "Could not get recommended server, exiting script"
    exit
fi
echo "Recommended server: $RECOMMENDED"
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
echo "Currently active server: $ENABLED_SERVER"
if [ "$ENABLED_SERVER" == "$SERVER_NAME" ]; then
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
    echo "Disabling current active server"
    disable_current_entry $ENABLED_SERVER
fi
echo "Restarting OpenVPN"
restart_openvpn
