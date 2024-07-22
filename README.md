# vpn-profile-switcher

`ash` shell script for getting the recommended NordVPN server, downloading said server's OpenVPN config file, setting credentials, and configuring OpenWRT for using said server.

Two more scripts are included as well: 
1. a script for getting the credentials from NordvPN's API.
1. a script for checking the "protection" status of the connection, like in [NordVPN's site](https://nordvpn.com/what-is-my-ip/).

## Description
### `vpn-profile-switcher.sh`
The main script is meant to be run either from the command line (once), or from [crontab](https://openwrt.org/docs/guide-user/base-system/cron) as a scheduled task.

By running the script from the command line once with the desired parameters ([country](https://github.com/UriShX/vpn-profile-switcher/blob/main/countries.tsv), [server group](https://support.nordvpn.com/General-info/Features/1047407962/What-do-the-different-server-categories-mean.htm), and [connection protocol](https://www.fastestvpnguide.com/openvpn-tcp-vs-udp/)), a recommended VPN server profile is retrieved and set as the active OpenVPN profile.

By running the script from a [crontab](https://openwrt.org/docs/guide-user/base-system/cron) with the desired parameters, users can maintain the optimal connection to the desired server country and group combination with the required protocol. This can be done by scheduling the script to run once per hour, for example. \
By using crontab, it is also possible to schedule connection to different VPN servers at certain times in a day or in a week.

The script outputs both error messages and normal operation log messages using OpenWRT's [logger](https://openwrt.org/docs/guide-user/base-system/log.essentials), using the `-s` flag. That means log messages are both logged in the system log, as well as seen displayed to the user when running from CLI.

[//]: #TODO adapt to both OpenVPN and WireGuard

The script scrubs unused profiles by removing them from the OpenWRT OpenVPN configuration and deleting the respective `.ovpn` files. \
The reason for saving at least the last used profile is that from my experience, sometimes a recommended server is actually too busy to operate reliably. In that case, switching to the last known good profile provides a good alternative, giving the opportunity to request a different server once again. _This should probably be written in a script that'll replace NordVPN's keep-alive script_. \
Only the currently used and the previous profiles are kept on the device. _An additional option for keeping more profiles on the device is planned, suggestions welcomed_.


[//]: # TODO add a script for for creating the coumtries and groups locally

The [countries](https://github.com/UriShX/vpn-profile-switcher/blob/db/countries.tsv) in which NordVPN operates servers, and the [server groups](https://github.com/UriShX/vpn-profile-switcher/blob/db/server-groups.tsv) are retrieved from this repository, in the [db](https://github.com/UriShX/vpn-profile-switcher/tree/db) branch. \
The [group-countries.tsv](https://github.com/UriShX/vpn-profile-switcher/blob/db/group-countries.tsv) table displays the possible combinations. \
The db branch is configured to be [updated every 15 minutes](https://github.com/UriShX/vpn-profile-switcher/blob/main/.github/workflows/main.yml) by a [Github action](https://github.com/UriShX/curl-then-jq-shell-action). In practice, the Github scheduling (for free repositories at least) runs the action at best once an hour. Not ideal, but until I figure out a better filtering system that doesn't require installing [JQ](https://stedolan.github.io/jq/) (~93 kB) on the router, scraping NordVPN's API on a remote machine seems like a better approach for the meantime.\
**_Please notice: It appears that the API lists different servers at different times, so re-check if you couldn't get to the servers you wanted to connect to._**

#### About server groups and server group + country combinations

NordVPN does not provide OpenVPN profiles ready to download for all groups, and does not provide every server groups in each country. This means that for some queries to the NordVPN API will return empty, and for others a `.ovpn` configuration file will not be downloaded. In those cases the script should fail gracefully with failure messages printed to system log, as well as to the terminal when running the script from CLI.

The best way to figure out if your parameters will actually work is to check the [group-countries.tsv](https://github.com/UriShX/vpn-profile-switcher/blob/db/group-countries.tsv) table, which is set up to be scraped every 15 minutes (doesn't really work on schedule, but about once an hour seems good enough). \
I noticed some recommended server for group and country combinations from [NordVPN server recommendation site](https://nordvpn.com/servers/tools/) did not show up in my scraped tables. Since the script downloads and connections are based on queries to NordVPN's API, and the tables the script queries are also scraped from the same API, I did not try to fix that. \
Of course, it is also possible to try the group + country combination from the script's CLI.

##### Server groups known to work, with countries in which there are servers of that group, with OpenVPN profiles

| Title                |               Remarks                | Works in the following countries                                                                                               |
| -------------------- | :----------------------------------: | :----------------------------------------------------------------------------------------------------------------------------- |
| Double_VPN           |                  -                   | CA, CH, FR, GB, HK, NL, SE, TW, US                                                                                             |
| Onion_Over_VPN       |   Shaky, usually returns only one    | (NL, CH)                                                                                                                       |
| Dedicated_IP         | Depends on purchase of dedicated IP? | DE, GB, NL, US                                                                                                                 |
| Standard_VPN_servers |                  -                   | AT, AU, BA, BE, BG, CA, CH, CY, CZ, DE, DK, ES, FR, GB, GR, HR, HU, IL, IT, JP, LU, LV, MY, NL, NO, PL, RO, SK, UA, US, VN, ZA |
| P2P                  |                  -                   | AT, AU, BA, BE, BG, CA, CH, CZ, DE, DK, ES, FR, GB, GR, HR, HU, IL, IT, JP, LU, LV, NL, NO, PL, RO, SK, US, ZA                 |

##### Regional groups

| Title                               |                      Countries in region                       |
| ----------------------------------- | :------------------------------------------------------------: |
| Europe                              | AT, BA, BE, CH, CY, CZ, DE, DK, FR, GB, HR, HU, NL, NO, PL, SE |
| The_Americas                        |                             CA, US                             |
| Asia_Pacific                        |               AU, HK, ID, JP, MY, NZ, SG, TW, VN               |
| Africa\_\_the_Middle_East_and_India |                         IL, IN, TR, ZA                         |

#### Special Thanks

Writing this script would not have been possible without the exquisite [NordVPN API documentation](https://blog.sleeplessbeastie.eu/2019/02/18/how-to-use-public-nordvpn-api/) by Milosz Galazka.

### `get_nordpn_credentials.sh`

This is a short script for getting the credentials from NordVPN's API. It is meant to be run once, and the output is either echoed back to the user, or saved.\
For WireGuard users, the script can create a NordVPN client intterface. For OepnVPN the username and password can be auttomatically saved to a file named `secret` in the `etc/openvpn/` folder.\

The script requires an access token, as suggested by stravos97 in [this gist](https://gist.github.com/bluewalk/7b3db071c488c82c604baf76a42eaad3?permalink_comment_id=5075473#gistcomment-5075473). The access token can then be used to get the credentials from the API.\

This script is meant to be run once, and the credentials can either be printed to screen, create a WireGuard interface, orsaved to a file for OpenVPN. The interface or saved credentials are then used by the `vpn-profile-switcher.sh` script to connect to the recommended server.

#### Required packages

This script requires either `curl` or `wget-ssl` to be installed on the device.\

### `vpn-status-checker-openwrt.sh`

This script is meant to be run from the command line, and checks the "protection" status of the connection, like in [NordVPN's site](https://nordvpn.com/what-is-my-ip/).\

This script is a preliminary version, and is meant to be run from the command line. The script outputs the status of the connection, and the IP address of the device.\

I plan to add DNS leak protection, and a check for the connection's speed, as well as a check for the connection's stability. In this way, the script can be used to check the connection's status before running the `vpn-profile-switcher.sh` script.

## Installation

### `vpn-profile-switcher.sh`

The script relies on [OpenWRT's](https://openwrt.org/start) ([BusyBox](https://www.busybox.net/downloads/BusyBox.html)) built-in `wget` and [`jsonfilter`](https://openwrt.org/docs/guide-developer/jshn#jsonfilter), but depends on several other packages. Check how much free space you have on your device either from LuCI (system -> software) or from shell by running `df` and looking at the `/overlay` line. You can compare the space left to the list of requirements below.


[//]: #TODO add instructions for wireguard

1. Follow (if you haven't already) [NordVPN's guide](https://support.nordvpn.com/Connectivity/Router/1047411192/OpenWRT-CI-setup-with-NordVPN.htm) for setting up OpenVPN on your router, and make sure your router connects to NordVPN's servers and your internet connection is good.
1. Log in to your router's shell, eg.: `ssh root@192.168.1.1`.
1. Run the following command on your remote shell to check whether `wget` can be used to send `GET` requests: \
   `wget -O - "https://raw.githubusercontent.com/urishx/vpn-profile-switcher/db/countries.tsv"`
1. If you get a table of countries in which NordVPN has servers, you're all set, skip to the last step to download the script to your router.
1. In case the response you you got was: \
   `wget: SSL support not available, please install one of the libustream-.*[ssl|tls] packages as well as the ca-bundle and ca-certificates packages.` \
   you will need to install `libustream*tls*` and its dependencies. - Run `opkg update` - Then `opkg list libustream*` - Look for `libustream-.*tls.*`, copy the package name, and install it by running `opkg install <the-package-name-you-copied>`. \
    eg.: `opkg install libustream-mbedtls20150806` on my TP-Link Archer C20i w/ OpenWRT v19.07.5. - Re-check step 3, to see you now get the table of countries.
1. Downloading the script and first run:
   - Run `wget https://raw.githubusercontent.com/UriShX/vpn-profile-switcher/main/vpn-profile-switcher.sh` to download the script to your router.
   - Run `chmod +x vpn-profile-switcher.sh`.
   - Test the script by running `./vpn-profile-switcher.sh`.

#### Requirements

[\\]: # TODO add requirements for WireGuard

- From NordVPN's guide (~800 kB with required dependencies):
  - openvpn-openssl (~158.4 kB)
  - ip-full (~167.4 kB)
  - luci-app-openvpn (~12.2 kB)
- tls for executing `GET` requests using `wget` (~180 kB):
  - libustream-mbedtls20150806 (~4.5 kB)
  - libmbedtls12 (~178 kB)
- Switching script, profiles, etc. (~14 kB):
  - vpn-profile-switcher.sh (~17 kB)
  - 2 OpenVPN profile - current and last used (ea. ~2.8)

## Usage

### `vpn-profile-switcher.sh`

Run `./vpn-profile-switcher.sh -h` to list the available parameters:

>vpn-profile-switcher.sh v1.1.0
>Get NordVPN recommended profile and set OpenVPN or WireGuard on OpenWRT to use said profile.
>
>Usage: ./vpn-profile-switcher.sh [options <parameters>]
>
>Options:
>  -h | --help,				Print this help message
>  -t | --type < openvpn | wireguard >,	Select either OpenVPN or WireGuard. Default is OpenVPN.
>  -p | --protocol < udp | tcp >,	Select either UDP or TCP connection. Default is UDP, and it is the only choice for WireGuard.
>  -c | --country < code | name >,	Select Country to filter by. Default is closest to your location.
>  -g | --group < group_name >,		Select group to filter by.
>  -r | --recommendations < number >,	Number of recommendations to ask from NordVPN API.
>  -d | --distance < number >,		Minimal load distance between recommended server and current configuration.
>  -l | --login-info < filename >,	Specify file for VPN login credentials. Default is 'secret' (stored in /etc/openvpn/). Applicable only for OpenVPN.
>  -i | --interface < interface >,	Specify interface to use for WireGuard. Default is 'nordlynx'. Applicable only for WireGuard.
>
>Examples:
>  ./vpn-profile-switcher.sh -t openvpn -p udp -c us -r 3 -d 10 -l secret
>  ./vpn-profile-switcher.sh -t wireguard -p udp -c us -r 3 -d 10 -i nordlynx
>
>For more information see README in repo: https://github.com/UriShX/vpn-profile-switcher

#### Script parameters

##### `-t` or `--type`

Has to be followed by either `openvpn` or `wireguard` (lowercase). \
Select either OpenVPN or WireGuard connection. \
If type is not defined, the script assumes OpenVPN, as it is the default connection type.

##### `-p` or `--protocol`

_Only for OpenVPN._ \
Has to be followed by either `udp` or `tcp` (lowercase). \
Select either UDP or TCP connection. \
If protocol is not defined, the script assumes UDP, for a faster (though less secure) connection.

For some details about the up and down sides of both TCP and UDP, see [this article](https://www.fastestvpnguide.com/openvpn-tcp-vs-udp/).

##### `-c` or `--country`

Has to be followed by either the country's ID, code, or name (ignores case). \
Select country to filter by. \
Default is closest to your location as determined by NordVPN's server, so if you are connected to a server which is far from your actual location and do not specify a different location for the script to filter by, your location will be remain in the same location as the server you are connected to.

You can view the list of available countries [here](https://github.com/UriShX/vpn-profile-switcher/blob/db/countries.tsv).

##### `-g` or `--group`

Has to be followed by desired server group's ID, identifier, or title. \
Select group to filter by. \
Unlike the `--country` filter, the group has to be specified with every request. According to NordVPN's documentation, [connecting to P2P services](https://support.nordvpn.com/General-info/Features/1047407792/Peer-to-Peer-P2P-traffic-with-NordVPN.htm) will be re-routed through either Canada or Holland, while [Onion over VPN](https://support.nordvpn.com/General-info/Features/1047408202/What-is-Onion-over-VPN-and-how-can-I-use-it.htm) is only available through specific servers. \
In short - the default server to which you will be will most likely be a standard server. Read more [here](https://support.nordvpn.com/General-info/Features/1047407962/What-do-the-different-server-categories-mean.htm).

You can view the list of available server groups [here](https://github.com/UriShX/vpn-profile-switcher/blob/db/server-groups.tsv).

##### `-r` or `--recommendations`

Has to be followed by a number. \
Number of recommendations to ask from NordVPN API. \
Default is 1, which will get the server currently recommended for the desired parameters by NordVPN.

##### `-d` or `--distance`

Has to be followed by a number. \
Minimal load distance between recommended server and current configuration. \
There is no default value, so if you do not specify a distance, the script will not check the distance between the recommended server and the current configuration.

##### `-l` or `--login-info`

_Only for OpenVPN._ \
Has to be followed by filename. \
Specify file for VPN login credentials. \
Default is 'secret', as in NordVPN's [guide](https://support.nordvpn.com/Connectivity/Router/1047411192/OpenWRT-CI-setup-with-NordVPN.htm) for setting a connection with OpenWRT over OpenVPN.

##### `-i` or `--interface`

_Only for WireGuard._ \
Has to be followed by interface name. \
Specify interface to use for WireGuard. Default is 'nordlynx', as is also the default for the `get_nordvpn_credentials.sh` script. \
I tried avoiding using the `wg0` interface, as it is the most commonly used for WireGuard in tutorials, and I wanted to avoid any conflicts.

### `get_nordpn_credentials.sh`

Run `./get_nordpn_credentials.sh -h` to list the available parameters:
>get_nordvpn_credentials.sh v1.0.0
>Get NordVPN credentials and save OpenVPN 'secret' file or set a WireGuard interface with it.
>
>Usage: ./get_nordvpn_credentials.sh [options <parameters>] (access_token)
>
>Options:
>  -h | --help,						Print this help message
>  -v | --vpn_type < openvpn | wireguard >, 		Select either OpenVPN or WireGuard. Default is wireguard.
>  -t | --token < path/to/nordvpn_access_token >,	Path to the file containing the NordVPN access token.
>  -w | --wireguard_interface < interface_name >,	Name of the WireGuard interface. Default is 'nordlynx'.
>  -c | --create,					Create a new WireGuard interface with the provided name OR the OpenVPN 'secret' file.
>  access_token,					The NordVPN access token. This is not required if the -t option is used.
>
>If no options are provided, the script will assume the access token is the first argument.
>
>Example: ./get_nordvpn_credentials.sh -t /etc/nordvpn_access_token -v openvpn
>
>For more information see README in repo: https://github.com/UriShX/vpn-profile-switcher

#### Script parameters

##### `-v` or `--vpn_type`

Has to be followed by either `openvpn` or `wireguard` (lowercase). \
Select either OpenVPN or WireGuard connection. \
If type is not defined, the script assumes WireGuard, as it is the default connection type.

##### `-t` or `--token`

Has to be followed by the path to the file containing the NordVPN access token. \
If the access token is not provided, the script will assume the access token is the first argument.

##### `-w` or `--wireguard_interface`

_Only for WireGuard._ \
Has to be followed by the name of the WireGuard interface. \
Default is 'nordlynx', as it is the default for the `vpn-profile-switcher.sh` script. \
This will be the name of the WireGuard interface created by the script.

##### `-c` or `--create`

Either create a new WireGuard interface with the provided name, or the OpenVPN 'secret' file. \
If this option is not provided, the script will only print the credentials to the screen.

### `vpn-status-checker-openwrt.sh`

Just run `./vpn-status-checker-openwrt.sh` to check the connection's status. \
The script will output the status of the connection, and the IP address of the device.

Example output:
>IP: 31.187.78.100
>ISP: NordVPN
>Location: Tel Aviv, Israel
>Status: Protected (VPN detected)

## Examples

### `vpn-profile-switcher.sh`
#### From CLI
##### Connect to a recommended OpenVPN Peer to Peer (P2P) server in the United States over UDP (default protocol)

```root
# ./vpn-profile-switcher.sh -c US -g p2p
```

Output:

> root: (./vpn-profile-switcher.sh) Arguments: Protocol: udp; Country: 228; NordVPN group: legacy_p2p; User credentials: secret. \
> root: (./vpn-profile-switcher.sh) Fetching VPN recommendations from: https://api.nordvpn.com/v1/servers/recommendations?filters[servers_groups][identifier]=legacy_p2p&filters[country_id]=228&filters[servers_technologies][identifier]=openvpn_udp&limit=1 \
> root: (./vpn-profile-switcher.sh) Recommended server URL: us6739.nordvpn.com. \
> root: (./vpn-profile-switcher.sh) Fetching OpenVPN config us6739.nordvpn.com.udp.ovpn, and setting credentials pointing to: secret \
> root: (./vpn-profile-switcher.sh) Entered new entry to OpenVPN configs: us6739_nordvpn_udp \
> root: (./vpn-profile-switcher.sh) Currently active server: cy14_nordvpn_udp \
> root: (./vpn-profile-switcher.sh) Enabling new entry \
> root: (./vpn-profile-switcher.sh) Disabling current active server \
> root: (./vpn-profile-switcher.sh) Comitting changes and restarting OpenVPN \
> root: (./vpn-profile-switcher.sh) Removing unused NordVPN profiles, leaving current and last used.

##### Connect to a standard VPN server in Argentina over TCP with OpenVPN

```root
# ./vpn-profile-switcher.sh -c 10 -p tcp
```

##### Connect to a standard VPN server in Israel over UDP with OpenVPN (default protocol)

```root
# ./vpn-profile-switcher.sh -c israel
```

##### Connect to a recommended VPN server in North America (USA and Canada) over UDP with OpenVPN (default protocol)

```root
# ./vpn-profile-switcher.sh -g the_americas
```

##### Connect to a recommended VPN server closest to you over UDP (default, and only, protocol) with WireGuard

```root
# ./vpn-profile-switcher.sh -t wireguard
```

Output:
> root: (./vpn-profile-switcher.sh) Arguments: VPN type: wireguard; Protocol: udp; Country: ; NordVPN group: ; User credentials: secret.
> root: (./vpn-profile-switcher.sh) Fetching VPN recommendations from: https://api.nordvpn.com/v1/servers/recommendations?filters[servers_technologies][identifier]=wireguard_udp&limit=1
> root: (./vpn-profile-switcher.sh) Recommended server URL: il61.nordvpn.com.
> root: (./vpn-profile-switcher.sh) Currently active wireguard server: il66
> root: (./vpn-profile-switcher.sh) Configured to receive only a single recommendation
> root: (./vpn-profile-switcher.sh) Entered new entry to wireguard configs: il61
> root: (./vpn-profile-switcher.sh) Enabling new entry
> root: (./vpn-profile-switcher.sh) Disabling current active server
> root: (./vpn-profile-switcher.sh) Comitting changes and restarting wireguard
> root: (./vpn-profile-switcher.sh) Removing unused NordVPN profiles, leaving current and last used.

#### Scheduling with [crontab](https://openwrt.org/docs/guide-user/base-system/cron)

It is possible to use crontab for maintaining a connection to a recommended server. In this basic example, the script runs once an hour (at a round hour) to get the recommended server in the area the router is connected to, over UDP (default protocol).

```bash
0 */1 * * * /root/vpn-profile-switcher.sh
```

The output will be displayed in the system log, like so:

> Wed Jan 13 23:02:00 2021 cron.info crond[22011]: USER root pid 22868 cmd /root/vpn-profile-switcher.sh \
> Wed Jan 13 23:02:00 2021 user.notice root: (/root/vpn-profile-switcher.sh) Arguments: Protocol: udp; Country: ; NordVPN group: ; User credentials: secret. \
> Wed Jan 13 23:02:00 2021 user.notice root: (/root/vpn-profile-switcher.sh) Fetching VPN recommendations from: https://api.nordvpn.com/v1/servers/recommendations?filters[servers_technologies][identifier]=openvpn_udp&limit=1 \
> Wed Jan 13 23:02:10 2021 user.notice root: (/root/vpn-profile-switcher.sh) Recommended server URL: il52.nordvpn.com. \
> Wed Jan 13 23:02:10 2021 user.notice root: (/root/vpn-profile-switcher.sh) Recommended server name: il52_nordvpn_udp \
> Wed Jan 13 23:02:10 2021 user.notice root: (/root/vpn-profile-switcher.sh) Currently active server: il38_nordvpn_udp \
> Wed Jan 13 23:02:10 2021 user.notice root: (/root/vpn-profile-switcher.sh) Enabling existing entry \
> Wed Jan 13 23:02:10 2021 user.notice root: (/root/vpn-profile-switcher.sh) Disabling current active server \
> Wed Jan 13 23:02:10 2021 user.notice root: (/root/vpn-profile-switcher.sh) Comitting changes and restarting OpenVPN

Using crontab, it is possible to set connection to different countries, groups, and over either UDP or TCP by scheduling running the script with different parameters. Check out both OpenWRT's [crontab](https://openwrt.org/docs/guide-user/base-system/cron) documentation, and [crontab guru](https://crontab.guru/) for more details.

In any case, **_don't forget to run `/etc/init.d/cron restart` to apply changes_**

### `get_nordvpn_credentials.sh

```root
./get_nordvpn_credentials.sh -t ./access_token.txt -w
```

Output:
> root: (./get_nordvpn_credentials.sh) Interface name nordlynx is already in use.
> Nordlynx private key: <your key>
> Please set the port to 51820 and the addresses to 10.5.0.2/32 in the WireGuard interface configuration.
> root: (./get_nordvpn_credentials.sh) WireGuard private key echoed to stdout.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/UriShX/vpn-profile-switcher.

## License

The script is available as open source under the terms of the [MIT License](https://github.com/UriShX/vpn-profile-switcher/blob/main/LICENSE).
