#!/bin/sh

ATO_NETS="62.20.146.242/32"
certbot="/usr/bin/certbot"
wanted_cert_path="/etc/letsencrypt/live"
apache_config="/storage/configuration/maps"
iis_config="/storage/configuration/iisv2"
le_auth=/appdir/atomia/le_auth.sh
le_cleanup=/appdir/atomia/le_cleanup.sh
f5hook=/appdir/atomia/f5_hook.sh

if [ -z "$1" ]; then
        echo "usage: $0 r preview_domain"
        echo "example:"
        echo "$0 preview.dev.atomia.com"
        exit 1
fi


in_net() {
        perl -e '
use strict;
my $net = shift @ARGV or die "no net";
my $ip = shift @ARGV or die "no ip";
my @pair = split("/", $net);
my $pf = $pair[0];
my $pl = $pair[1];
$pf =~ s/(\d+)([.]|$)/sprintf("%02X", $1)/ge;
$pf = unpack("N", pack("H8", $pf));
$pl = unpack("N", pack("b32", "1" x $pl . "0" x (32 - $pl)));
$ip =~ s/(\d+)([.]|$)/sprintf("%02X", $1)/ge;
$ip = unpack("N", pack("H8", $ip));
exit 1 if ($pf & $pl) ne ($ip & $pl);
' "$1" "$2"
}

in_ato_nets() {
        is_in=no
        for net in $ATO_NETS; do
                in_net $net "$1" && {
                        is_in=yes
                        break
                }
        done
        echo $is_in
}

echo "LINUX websites:"

if [ -f "$apache_config/vhost.map" ]; then
        cat "$apache_config"/vhost.map | awk '{ print $1 }' | grep -vE "$1"'$' | grep -v '^www\.' | grep -E '^[a-zA-Z0-9.-]+$' \
                        | sort -u | awk '{ print $0 " www." $0 }' | while read cert; do

                wanted_cert=$(echo "$cert" | cut -d " " -f 1)
                wanted_wwwcert=$(echo "$cert" | cut -d " " -f 2 )
                desired=$(echo "$cert" | cut -d " " -f 1 )

                if [ ! -d `echo "$wanted_cert_path/$desired"` ]; then
                        ip1="$(dig +short $wanted_wwwcert | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b')"
                        ip2="$(dig +short $wanted_cert | head -1)"

                                if  [ -n "$ip1" ] && [ "$(in_ato_nets $ip1)" = yes ] && [ -n "$ip2" ] && [ "$(in_ato_nets $ip2)" = yes ] ; then
                                        echo "$wanted_cert_path/$desired"
                                        echo "wanted cert: $wanted_cert"
                                        echo "www cert: $wanted_wwwcert"
                                        echo "certbot certonly --manual --manual-auth-hook $le_auth --manual-cleanup-hook $le_cleanup -d $wanted_cert -d $wanted_wwwcert --non-interactive --agree-tos --email noreply@hosting.telia.com --manual-public-ip-logging-ok "
										echo "$f5hook add $wanted_cert"
                                fi
                fi
        done
fi

echo "WINDOWS websites:"

if [ -f "$iis_config/applicationHost.config" ]; then
        grep -F binding "$iis_config/applicationHost.config" | grep -F ":80:" | awk -F ':80:' '{ print $2 }' | cut -d '"' -f 1 \
                        | grep -vE "$1"'$' | grep -v '^www\.' | grep -E '^[a-zA-Z0-9.-]+$' | sort -u | awk '{ print $0 " www." $0 }' | while read cert; do

                wanted_cert=$(echo "$cert" | cut -d " " -f 1)
                wanted_wwwcert=$(echo "$cert" | cut -d " " -f 2 )
                desired=$(echo "$cert" | cut -d " " -f 1 )

                if [ ! -d `echo "$wanted_cert_path/$desired"` ]; then
                        ip1="$(dig +short $wanted_wwwcert | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b')"
                        ip2="$(dig +short $wanted_cert | head -1)"
                                if  [ -n "$ip1" ] && [ "$(in_ato_nets $ip1)" = yes ] && [ -n "$ip2" ] && [ "$(in_ato_nets $ip2)" = yes ] ; then
                                        echo "$wanted_cert_path/$desired"
                                        echo "wanted cert: $wanted_cert"
                                        echo "www cert: $wanted_wwwcert"
                                        echo "certbot certonly --manual --manual-auth-hook $le_auth --manual-cleanup-hook $le_cleanup -d $wanted_cert -d $wanted_wwwcert --non-interactive --agree-tos --email noreply@hosting.telia.com --manual-public-ip-logging-ok "
										echo "$f5hook add $wanted_cert"
                                fi
                fi
        done
fi
