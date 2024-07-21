#!/bin/sh

# Function to get public IP information
get_ip_info() {
    wget -qO- "https://nordvpn.com/wp-admin/admin-ajax.php?action=get_user_info_data" 2>/dev/null || \
    curl -s "https://nordvpn.com/wp-admin/admin-ajax.php?action=get_user_info_data" 2>/dev/null
}

# Main function to check VPN status
check_vpn_status() {
    # Get IP information
    ip_info=$(get_ip_info)

    if [ -z "$ip_info" ]; then
        echo "Error: Failed to retrieve IP information"
        exit 1
    fi

    # Extract relevant information using jsonfilter
    ip=$(echo "$ip_info" | jsonfilter -e '@.ip')
    isp=$(echo "$ip_info" | jsonfilter -e '@.isp')
    country=$(echo "$ip_info" | jsonfilter -e '@.country')
    city=$(echo "$ip_info" | jsonfilter -e '@.city')
    status=$(echo "$ip_info" | jsonfilter -e '@.status')

    echo "IP: $ip"
    echo "ISP: $isp"
    echo "Location: $city, $country"

    if [ "$status" = "true" ]; then
        echo "Status: Protected (VPN detected)"
        exit 1
    else
        echo "Status: Unprotected (No VPN detected)"
        exit 0
    fi
}

# Run the main function
check_vpn_status
