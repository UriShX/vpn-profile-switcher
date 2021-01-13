# vpn-profile-switcher

`-ash` shell script for getting the recommended NordVPN server, downloading said server's OpenVPN config file, setting credentials, and configuring OpenWRT for using said server.

### Description

The script is meant to be run either from the command line (once), or from [crontab](https://openwrt.org/docs/guide-user/base-system/cron) as a scheduled task.

By running the script from the command line once with the desired parameters ([country](https://github.com/UriShX/vpn-profile-switcher/blob/main/countries.tsv), [server group](https://support.nordvpn.com/General-info/Features/1047407962/What-do-the-different-server-categories-mean.htm), and [connection protocol](https://www.fastestvpnguide.com/openvpn-tcp-vs-udp/)), a recommended VPN server profile is retrieved and set as the active OpenVPN profile.

By running the script from a [crontab](https://openwrt.org/docs/guide-user/base-system/cron) with the desired parameters, users can maintain the optimal connection to the desired server country and group combination with the required protocol. This can be done by scheduling the script to run once per hour, for example. \
By using crontab, it is also possible to schedule connection to different VPN servers at certain times in a day or in a week.

The script outputs both error messages and normal operation log messages using OpenWRT's [logger](https://openwrt.org/docs/guide-user/base-system/log.essentials), using the `-s` flag. That means log messages are both logged in the system log, as well as seen displayed to the user when running from CLI.

The script scrubs unused profiles by removing them from the OpenWRT OpenVPN configuration and deleting the respective `.ovpn` files. \
The reason for saving at least the last used profile is that from my experience, sometimes a recommended server is actually too busy to operate reliably. In that case, switching to the last known good profile provides a good alternative, giving the opportunity to request a different server once again. _This should probably be written in a script that'll replace NordVPN's keep-alive script_. \
Only the currently used and the previous profiles are kept on the device. _An additional option for keeping more profiles on the device is planned, using regular expressions as the option's parameter_.

The [countries](https://github.com/UriShX/vpn-profile-switcher/blob/db/countries.tsv) in which NordVPN operates servers, and the [server groups](https://github.com/UriShX/vpn-profile-switcher/blob/db/server-groups.tsv) are retrieved from this repository, in the [db](https://github.com/UriShX/vpn-profile-switcher/tree/db) branch. \
The [group-countries.tsv](https://github.com/UriShX/vpn-profile-switcher/blob/db/group-countries.tsv) table displays the possible combinations. \
The db branch is configured to be [updated every 15 minutes](https://github.com/UriShX/vpn-profile-switcher/blob/main/.github/workflows/main.yml) by a [Github action](https://github.com/UriShX/curl-then-jq-shell-action). In practice, the Github scheduling (for free repositories at least) runs the action at best once an hour. Not ideal, but until I figure out a better filtering system that doesn't require installing [JQ](https://stedolan.github.io/jq/) (~93 kB) on the router, scraping NordVPN's API on a remote machine seems like a better approach for the meantime. **Please notice: It appears that the API lists different servers at different times, so re-check if you couldn't get to the servers you wanted to connect to.**

### About server groups and server group + country combinations

NordVPN does not provide OpenVPN profiles ready to download for all groups, and does not provide every server groups in each country. This means that for some queries to the NordVPN API will return empty, and for others a `.ovpn` configuration file will not be downloaded. In those cases the script should fail gracefully with failure messages printed to system log, as well as to the terminal when running the script from CLI.

The best way to figure out if your parameters will actually work is to check the [group-countries.tsv](https://github.com/UriShX/vpn-profile-switcher/blob/db/group-countries.tsv) table, which is set up to be scraped every 15 minutes (doesn't really work on schedule, but about once an hour seems good enough). \
I noticed some recommended server for group and country combinations from [NordVPN server recommendation site](https://nordvpn.com/servers/tools/) did not show up in my scraped tables. Since the script downloads and connections are based on queries to NordVPN's API, and the tables the script queries are also scraped from the same API, I did not try to fix that. \
Of course, it is also possible to try the group + country combination from the script's CLI.

#### Server groups known to work, with countries in which there are servers of that group, with OpenVPN profiles

| Title                |               Remarks                | Works in the following countries                                                                                               |
| -------------------- | :----------------------------------: | :----------------------------------------------------------------------------------------------------------------------------- |
| Double_VPN           |                  -                   | CA, CH, FR, GB, HK, NL, SE, TW, US                                                                                             |
| Onion_Over_VPN       |   Shaky, usually returns only one    | (NL, CH)                                                                                                                       |
| Dedicated_IP         | Depends on purchase of dedicated IP? | DE, GB, NL, US                                                                                                                 |
| Standard_VPN_servers |                  -                   | AT, AU, BA, BE, BG, CA, CH, CY, CZ, DE, DK, ES, FR, GB, GR, HR, HU, IL, IT, JP, LU, LV, MY, NL, NO, PL, RO, SK, UA, US, VN, ZA |
| P2P                  |                  -                   | AT, AU, BA, BE, BG, CA, CH, CZ, DE, DK, ES, FR, GB, GR, HR, HU, IL, IT, JP, LU, LV, NL, NO, PL, RO, SK, US, ZA                 |

#### Regional groups

| Title                               |                      Countries in region                       |
| ----------------------------------- | :------------------------------------------------------------: |
| Europe                              | AT, BA, BE, CH, CY, CZ, DE, DK, FR, GB, HR, HU, NL, NO, PL, SE |
| The_Americas                        |                             CA, US                             |
| Asia_Pacific                        |               AU, HK, ID, JP, MY, NZ, SG, TW, VN               |
| Africa\_\_the_Middle_East_and_India |                         IL, IN, TR, ZA                         |

### Special Thanks

Writing this script would not have been possible without the exquisite [NordVPN API documentation](https://blog.sleeplessbeastie.eu/2019/02/18/how-to-use-public-nordvpn-api/) by Milosz Galazka.

## Installation

The script relies on [OpenWRT's](https://openwrt.org/start) ([BusyBox](https://www.busybox.net/downloads/BusyBox.html)) built-in `wget` and [`jsonfilter`](https://openwrt.org/docs/guide-developer/jshn#jsonfilter), but depends on several other packages. Check how much free space you have on your device either from LuCI (system -> software) or from shell by running `df` and looking at the `/overlay` line. You can compare the space left to the list of requirements below.

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

### Requirements

- From NordVPN's guide (~800 kB with required dependencies):
  - openvpn-openssl (~158.4 kB)
  - ip-full (~167.4 kB)
  - luci-app-openvpn (~12.2 kB)
- tls for executing `GET` requests using `wget` (~180 kB):
  - libustream-mbedtls20150806 (~4.5 kB)
  - libmbedtls12 (~178 kB)
- Switching script, profiles, etc. (~14 kB):
  - vpn-profile-switcher.sh (~8 kB)
  - 2 OpenVPN profile - current and last used (ea. ~2.8)

## Usage

Run `./vpn-profile-switcher.sh -h` to list the available parameters:

> vpn-profile-switcher.sh v1.0.0 \
> Get NordVPN recommended profile and set OpenVPN on OpenWRT to use said profile.
>
> Usage: ./vpn-profile-switcher.sh [options <parameters>]
>
> Options: \
> -h | --help, Print this help message \
> -p | --protocol < udp | tcp >, Select either UDP or TCP connection. Default is UDP. \
> -c | --country < code | name >, Select Country to filter by. Default is closest to your location. \
> -g | --group < group_name >, Select group to filter by. \
> -l | --login-info < filename >, Specify file for VPN login credentials. Default is 'secret'.
>
> For more information see README in repo: https://github.com/UriShX/vpn-profile-switcher

### Script parameters

#### `-p` or `--protocol`

Has to be followed by either `udp` or `tcp` (lowercase). \
Select either UDP or TCP connection. \
If protocol is not defined, the script assumes UDP, for a faster (though less secure) connection.

For some details about the up and down sides of both TCP and UDP, see [this article](https://www.fastestvpnguide.com/openvpn-tcp-vs-udp/).

#### `-c` or `--country`

Has to be followed by either the country's ID, code, or name (ignores case). \
Select country to filter by. \
Default is closest to your location as determined by NordVPN's server, so if you are connected to a server which is far from your actual location and do not specify a different location for the script to filter by, your location will be remain in the same location as the server you are connected to.

You can view the list of available countries [here](https://github.com/UriShX/vpn-profile-switcher/blob/db/countries.tsv).

#### `-g` or `--group`

Has to be followed by desired server group's ID, identifier, or title. \
Select group to filter by. \
Unlike the `--country` filter, the group has to be specified with every request. According to NordVPN's documentation, [connecting to P2P services](https://support.nordvpn.com/General-info/Features/1047407792/Peer-to-Peer-P2P-traffic-with-NordVPN.htm) will be re-routed through either Canada or Holland, while [Onion over VPN](https://support.nordvpn.com/General-info/Features/1047408202/What-is-Onion-over-VPN-and-how-can-I-use-it.htm) is only available through specific servers. \
In short - the default server to which you will be will most likely be a standard server. Read more [here](https://support.nordvpn.com/General-info/Features/1047407962/What-do-the-different-server-categories-mean.htm).

You can view the list of available server groups [here](https://github.com/UriShX/vpn-profile-switcher/blob/db/server-groups.tsv).

#### `-l` or `--login-info`

Has to be followed by filename. \
Specify file for VPN login credentials. \
Default is 'secret', as in NordVPN's [guide](https://support.nordvpn.com/Connectivity/Router/1047411192/OpenWRT-CI-setup-with-NordVPN.htm) for setting a connection with OpenWRT over OpenVPN.

## Examples

### From CLI

#### Connect to a recommended Peer to Peer (P2P) server in the United States over UDP (default protocol)

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

#### Connect to a standard VPN server in Argentina over TCP

```root
# ./vpn-profile-switcher.sh -c 10 -p tcp
```

#### Connect to a standard VPN server in Israel over UDP (default protocol)

```root
# ./vpn-profile-switcher.sh -c israel
```

#### Connect to a recommended VPN server in North America (USA and Canada) over UDP (default protocol)

```root
# ./vpn-profile-switcher.sh -g the_americas
```

### Scheduling with [crontab](https://openwrt.org/docs/guide-user/base-system/cron)

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

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/UriShX/vpn-profile-switcher.

## License

The script is available as open source under the terms of the [MIT License](https://github.com/UriShX/vpn-profile-switcher/blob/main/LICENSE).
