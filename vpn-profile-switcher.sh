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

protocol="udp"
secret="secret"

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
    LIBUSTREAM=$(opkg info libustream* | awk '/installed/{print $0}')

    if [ ! $WGET ] || [ ! $JSONFILTER ] || [ ! $LIBUSTREAM ]; then
        # wget: SSL support not available, please install one of the libustream-.*[ssl|tls] packages as well as the ca-bundle and ca-certificates packages.
        logger -s "($0) You must have the required packages installed: wget jsonfilter libustream*tls\n"
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
    identifier=$(wget -q -O - "https://raw.githubusercontent.com/urishx/vpn-profile-switcher/db/countries.tsv" | grep -iw "$1" | awk -F '\t' '/[0-9]+/{print $1}')

    if [ -z "$identifier" ]; then
        logger -s "($0) The query you entered ("$1") could not be found in the countries databse."
        logger -s "($0) You can view the list of countries in which NordVPN has OpenVPN servers online: https://github.com/urishx/vpn-profile-switcher/blob/db/countries.tsv"
        exit 1
    else
        echo "$identifier"
    fi
}

function server_groups() {
    identifier=$(wget -q -O - "https://raw.githubusercontent.com/urishx/vpn-profile-switcher/db/server-groups.tsv" | grep -iw "$1" | awk -F '\t' '/.*/{print $2}')

    if [ -z "$identifier" ]; then
        logger -s "($0) The query you entered ("$1") could not be found in the server groups databse."
        logger -s "($0) You can view the list of NordVPN OpenVPN server groups online: https://github.com/urishx/vpn-profile-switcher/blob/db/server-groups.tsv"
        logger -s "($0) Not all server groups are available for OpenVPN connection, please check NordVPN's server recommendation site: https://nordvpn.com/servers/tools/"
        exit 1
    else
        echo "$identifier"
    fi
}

function get_recommended() {
    _url="https://api.nordvpn.com/v1/servers/recommendations?"
    if [ ! -z "$group_identifier" ]; then
        _url=${_url}"filters[servers_groups][identifier]="${group_identifier}"&"
    fi
    if [ ! -z "$country_id" ]; then
        _url=${_url}"filters[country_id]="${country_id}"&"
    fi
    _url=${_url}"filters[servers_technologies][identifier]=openvpn_"${protocol}"&limit=1"
    logger -s "($0) Fetching VPN recommendations from: $_url"
    recommended=$(wget -q -O - "$_url" | jsonfilter -e '$[0].hostname') || true
}

function check_in_configs() {
    server_name=$(uci show openvpn | grep $recommended.$protocol | awk -F '\.' '/config/{print $2}')
}

function check_enabled() {
    enabled_server=$(uci show openvpn | grep "enabled='1'" | awk -F '\.' '/.*/{print $2}')
}

function grab_and_edit_config() {
    wget -q https://downloads.nordcdn.com/configs/files/ovpn_$protocol/servers/$recommended.$protocol.ovpn
    if [ ! -f "$recommended.$protocol.ovpn" ]; then
        logger -s "($0) The recommended server profile could not be downloaded from NordVPN's servers, quitting."
        logger -s "($0) Not all server groups are available for OpenVPN connection, please see the list of available group + country combinations at: https://github.com/UriShX/vpn-profile-switcher/blob/db/group-countries.tsv"
        logger -s "($0) Or check NordVPN's server recommendation site: https://nordvpn.com/servers/tools/"
        exit 1
    fi
    mv $recommended.$protocol.ovpn /etc/openvpn/
    sed -i "s/auth-user-pass/auth-user-pass $secret/g" /etc/openvpn/$recommended.$protocol.ovpn
}

function create_new_entry() {
    new_server=$(echo "$recommended" | sed 's/[\.\ -]/_/g' | eval sed 's/com/$protocol/g')
    uci set openvpn.$new_server=openvpn
    uci set openvpn.$new_server.config="/etc/openvpn/$recommended.$protocol.ovpn"
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
    nordvpn_configs=$(list_ovpn_configs names)
    nordvpn_files=$(list_ovpn_configs files)

    for X in $nordvpn_configs; do
        if [ ! "$X" == "$server_name" ] && [ ! "$X" == "$new_server" ] && [ ! "$X" == "$enabled_server" ]; then
            uci del openvpn.$X
        fi
    done

    uci commit

    if [ ! -z "$enabled_server" ]; then
        enabled_file=$(uci show openvpn.$enabled_server.config | awk -F '=' '{print $2}' | sed "s/'//g")
    fi
    if [ ! -z "$server_name" ]; then
        existing_file=$(uci show openvpn.$server_name.config | awk -F '=' '{print $2}' | sed "s/'//g")
    fi
    if [ ! -z "$new_server" ]; then
        new_file=$(uci show openvpn.$new_server.config | awk -F '=' '{print $2}' | sed "s/'//g")
    fi

    for X in $nordvpn_files; do
        if [ ! "$X" == "$enabled_file" ] && [ ! "$X" == "$existing_file" ] && [ ! "$X" == "$new_file" ]; then
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
        protocol=$(verify_protocol $1)
        ;;
    -c | --country)
        shift
        country_id=$(country_code $1)
        ;;
    -g | --group)
        shift
        group_identifier=$(server_groups $1)
        ;;
    -l | --login-info)
        shift
        secret="$1"
        ;;
    *)
        logger -s "($0) Incorrect input provided"
        show_usage
        ;;
    esac
    shift
done

logger -s "($0) Arguments: Protocol: $protocol; Country: $country_id; NordVPN group: $group_identifier; User credentials: $secret."

get_recommended

if [ -z "$recommended" ]; then
    logger -s "($0) Could not get recommended VPN, exiting script"
    logger -s "($0) This might be due to a group + country combination, or server group which is not supported by OpenVPN connection."
    logger -s "($0) To tune your request, please see the list of available combinations at: https://github.com/UriShX/vpn-profile-switcher/blob/db/group-countries.tsv"
    logger -s "($0) Or check NordVPN's server recommendation site: https://nordvpn.com/servers/tools/"
    exit
fi

logger -s "($0) Recommended server URL: $recommended."

check_in_configs

if [ -z "$server_name" ]; then
    logger -s "($0) Fetching OpenVPN config $recommended.$protocol.ovpn, and setting credentials"
    grab_and_edit_config
    create_new_entry
    logger -s "($0) Entered new entry to OpenVPN configs: $new_server"
else
    logger -s "($0) Recommended server name: $server_name"
fi

check_enabled

logger -s "($0) Currently active server: $enabled_server"

if [ "$enabled_server" == "$server_name" ]; then
    logger -s "($0) Recommended server is already configured as active"
    exit
else
    if [ -z "$new_server" ]; then
        logger -s "($0) Enabling existing entry"
        enable_existing_entry $server_name
    else
        logger -s "($0) Enabling new entry"
        enable_existing_entry $new_server
    fi
    logger -s "($0) Disabling current active server"
    disable_current_entry $enabled_server
fi

logger -s "($0) Comitting changes and restarting OpenVPN"

restart_openvpn

logger -s "($0) Removing unused NordVPN profiles, leaving current and last used."
remove_unused
