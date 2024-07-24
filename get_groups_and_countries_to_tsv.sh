#!/bin/sh

# Record the start time
start_time=$(date +%s)

# Ensure the ./db/ directory exists
mkdir -p ./db

# Function to create TSV files
create_tsv() {
    [ -f "./db/$1" ] && rm "./db/$1"
    touch "./db/$1"
    printf "%s\n" "$2" >> "./db/$1"
}

# Function to extract identifiers
identifiers() {
    sed 1d "./db/$1" | awk '{print $2}'
}

# Fetch and process groups data
GROUPS_DATA=$(wget -qO- "https://api.nordvpn.com/v1/servers/groups" | jsonfilter -e '@[*]' | while read -r group; do
    id=$(echo "$group" | jsonfilter -e '$.id')
    identifier=$(echo "$group" | jsonfilter -e '$.identifier')
    title=$(echo "$group" | jsonfilter -e '$.title' | sed 's/[,\ ]/_/g')
    printf "%s\t%s\t%s\n" "$id" "$identifier" "$title"
done)

GROUPS_DATA=$(printf "ID\tIdentifier\tTitle\n%s" "$GROUPS_DATA")

# Fetch and process countries data
COUNTRIES_DATA=$(wget -qO- "https://api.nordvpn.com/v1/servers/countries" | jsonfilter -e '@[*]' | while read -r country; do
    id=$(echo "$country" | jsonfilter -e '$.id')
    code=$(echo "$country" | jsonfilter -e '$.code')
    name=$(echo "$country" | jsonfilter -e '$.name' | sed 's/ /_/g')
    printf "%s\t%s\t%s\n" "$id" "$code" "$name"
done)

COUNTRIES_DATA=$(printf "ID\tCode\tName\n%s" "$COUNTRIES_DATA")

COUNTRIES=$(printf "Group_Identifier\tCountries")

# Create TSV files with headers
create_tsv "server-groups.tsv" "$GROUPS_DATA"
create_tsv "countries.tsv" "$COUNTRIES_DATA"
create_tsv "group-countries.tsv" "$COUNTRIES"

# Process each group
IDS=$(identifiers server-groups.tsv)
for X in $IDS; do
    COUNTRIES=$(wget -qO- "https://api.nordvpn.com/v1/servers?filters\[servers_groups\]\[identifier\]=$X&filters\[servers_technologies\]\[identifier\]=openvpn_tcp" | jsonfilter -e '@[*].locations[*].country.code' | sort -u | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
    # COUNTRIES=$(printf "Group_Identifier\tCountries\n%s" "$COUNTRIES")
    if [ -n "$COUNTRIES" ]; then
        printf "%s\t%s\n" "$X" "$COUNTRIES" >> "./db/group-countries.tsv"
    else
        sed -i "/\t$X\t/d" "./db/server-groups.tsv"
    fi
done

# Process each country
CODES=$(identifiers countries.tsv)
for X in $CODES; do
    if ! grep -q "$X" "./db/group-countries.tsv"; then
        sed -i "/\t$X\t/d" "./db/countries.tsv"
    fi
done

# Record the end time
end_time=$(date +%s)

# Calculate the duration
duration=$((end_time - start_time))

# Output the results
logger -s "Script took $duration seconds to complete."

unset start_time end_time duration GROUPS_DATA COUNTRIES_DATA COUNTRIES IDS CODES X
