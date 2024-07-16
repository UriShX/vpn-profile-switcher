#!/bin/sh

wg_iface="nordlynx"
vpn_type="wireguard"
_create=0

function show_usage() {
    printf "get_nordvpn_credentials.sh v1.0.0\n"
    printf "Get NordVPN credentials and save OpenVPN 'secret' file or set a WireGuard interface with it.\n\n"
    printf "Usage: $0 [options <parameters>] (access_token)\n\n"
    printf "Options: \n"
    printf "  -h | --help,\t\t\t\t\t\tPrint this help message\n"
    printf "  -v | --vpn_type < openvpn | wireguard >, \t\tSelect either OpenVPN or WireGuard. Default is wireguard.\n" 
    printf "  -t | --token < path/to/nordvpn_access_token >,\tPath to the file containing the NordVPN access token.\n"
    printf "  -w | --wireguard_interface < interface_name >,\tName of the WireGuard interface. Default is 'nordlynx'.\n"
    printf "  -c | --create,\t\t\t\t\tCreate a new WireGuard interface with the provided name OR the OpenVPN 'secret' file.\n"
    printf "  access_token,\t\t\t\t\tThe NordVPN access token. This is not required if the -t option is used.\n"
    printf "\nIf no options are provided, the script will assume the access token is the first argument.\n"
    printf "\nExample: $0 -t /etc/nordvpn_access_token -v openvpn\n"
    printf "\nFor more information see README in repo: https://github.com/UriShX/vpn-profile-switcher\n"

    exit
}

function check_packages() {
    # Check if either wget-ssl or curl are installed
    opkg list-installed wget-ssl | grep -q . || opkg list-installed curl | grep -q .

    if [ $? -ne 0 ]; then
        logger -s "($0) Error: either wget-ssl or curl are required to run this script. Please install either one of the packages."
        exit 1
    fi

    return 0
}

function check_access_token_exists() {
    # Check if an access token was provided
    if [ $1 -eq 0 ]; then
        logger -s "$(0) Error: No access token provided."
        logger -s "$(0) Please provide the path to the file containing the NordVPN access token."
        exit 1
    fi

    echo $(cat $1)
}

function verify_vpn_type() {
    if [ ! "$1" == "openvpn" ] && [ ! "$1" == "wireguard" ]; then
        logger -s "($0) VPN type must be either openvpn or wireguard, your input was: $1."
        exit 1
    else
        echo $1
    fi
}

function test_and_set_wg_interface() {
    # if no interface name is provided, default to 'nordlynx'
    if [ -z "$1" ]; then
        wg_iface="nordlynx"
    else
        wg_iface=$1
    fi

    # check if the provided interface name is already in use
    uci show network.$wg_iface | grep -q .
    if [ $? == 0 ]; then
        logger -s "($0) Interface name $wg_iface is already in use."
        unset_variables
        exit 1
    fi
    
    echo $wg_iface
}

function get_credendtials() {
    which curl | grep -q .

    if [ $? -ne 0 ]; then
        # Run the wget command
        response_json=$(wget -q -O - --auth-no-challenge --user=token --password="$access_token" https://api.nordvpn.com/v1/users/services/credentials)
    else
        response_json=$(curl -s -u token:"$access_token" https://api.nordvpn.com/v1/users/services/credentials)
    fi

    # Check if the wget command was successful
    if [ $? -ne 0 ]; then
        logger -s "$(0) Error: Failed to fetch credentials. Please check your access token and internet connection."
        exit 1
    fi

    # logger -s $response_json
}

function save_credentials() {
    _err=$(jsonfilter -s "$response_json" -e '@.errors.message')
    # Check if the response contains an error message
    if [ $? -eq 0 ]; then
        logger -s "($0) Error: $_err"
        unset_variables
        exit 1
    fi

    if [ $vpn_type == "openvpn" ]; then
        _username=$(jsonfilter -s "$response_json" -e '@.username')
        _password=$(jsonfilter -s "$response_json" -e '@.password')
        if [ $_create -ne 1 ]; then
            echo "Username: $_username"
            echo "Password: $_password"
            logger -s "($0) OpenVPN credentials echoed to stdout."
        else
            echo $_username > /etc/openvpn/secret
            echo $_password >> /etc/openvpn/secret
            logger -s "($0) OpenVPN credentials saved to /etc/openvpn/secret"
        fi
    else
        _key=$(jsonfilter -s "$response_json" -e "@.nordlynx_private_key")
        if [ $_create -ne 1 ]; then
            echo "Nordlynx private key: $_key"
            echo "Please set the port to 51820 and the addresses to 10.5.0.2/32 in the WireGuard interface configuration."
            logger -s "($0) WireGuard private key echoed to stdout."
        else
            uci set network.$wg_iface=interface
            uci set network.$wg_iface.proto='wireguard'
            uci set network.$wg_iface.private_key=$_key
            uci set network.$wg_iface.listen_port='51820'
            uci set network.$wg_iface.addresses='10.5.0.2/32'
            uci add_list network.$wg_iface.dns='103.86.96.100'
            uci add_list network.$wg_iface.dns='103.86.99.100'
            uci set network.$wg_iface.auto='1'
            uci commit network
            logger -s "($0) WireGuard interface $wg_iface created and configured."
        fi
    fi
}

function unset_variables() {
    # free up the variables
    unset access_token
    unset vpn_type
    unset wg_iface
    unset wireguard_interface
    unset response_json
    unset _err
    unset _create
    unset _key
    unset _username
    unset _password
}

check_packages

while [ ! -z "$1" ]; do
    case "$1" in
    -h | --help)
        show_usage
        ;;
    -t | --token)
        shift
        access_token=$(check_access_token_exists $1)
        ;;
    -v | --vpn_type)
        shift
        vpn_type=$(verify_vpn_type $1)
        ;;
    -w | --wireguard_interface)
        shift
        wg_iface=$(test_and_set_wg_interface $1)
        ;;
    -c | --create)
        _create=1
        ;;
    *)
        if [ -z "$access_token" ]; then
            access_token=$1
        else
            logger -s "($0) Incorrect input provided"
            show_usage
            unset_variables
            exit 1
        fi
        ;;
    esac
    shift
done

get_credendtials

save_credentials
# echo "response_json: $response_json"

unset_variables

exit 0
