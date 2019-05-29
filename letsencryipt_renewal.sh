#!/bin/bash

PATH=$PATH:/usr/sbin
export PATH

ATO_NETS="62.20.146.242/32"

CERTS_DIR="/etc/letsencrypt/live"
le_auth=/appdir/atomia/le_auth.sh
le_cleanup=/appdir/atomia/le_cleanup.sh
f5hook=/appdir/atomia/f5_hook.sh

curdate=$(date +%s)
renewed_cert=0
revoked_cert=0

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

cd $CERTS_DIR
ls -tr | \
while read domain; do
        pem="$domain""/cert.pem"
        expdate1=$(date --date="$(openssl x509 -enddate -noout -in "$pem"|cut -d= -f 2)" +%s)
        expdays=$(( (expdate1-curdate) / 86400))


        if [ $expdays -le 25 ];
        then
                wanted_cert=`openssl x509 -noout -subject -in $pem | sed -n '/^subject/s/^.*CN=//p'`

                ip="$(dig +short $wanted_cert | head -1)"

                if [ -n "$ip" ] && [ "$(in_ato_nets $ip)" = yes ] ; then
                    echo "Certificate $wanted_cert expire on $expdate1, in $expdays days !"
                    echo "Renewing.."

                    echo "certbot renew --cert-name $wanted_cert --force-renewal --manual --manual-auth-hook $le_auth --manual-cleanup-hook $le_cleanup --non-interactive --agree-tos --email noreply@hosting.telia.com --manual-public-ip-logging-ok"

                    OUT=$? #0 if renew is succesfull, 1 if it's failed

                    if [ $OUT -eq 0 ];then
                        echo "$f5hook remove $wanted_cert"
                        echo "$f5hook add $wanted_cert"
                        rm /var/log/letsencrypt/letsencrypt.log
                        find /var/log/letsencrypt/ -size 0 -delete

                        ((renewed_cert++))
                    fi
                else
                    echo "Certificate $wanted_cert not hosted on Telia !"
                    echo "Revoking.."
                    echo "certbot revoke -d $wanted_cert --cert-path /etc/letsencrypt/live/${wanted_cert}/cert.pem --non-interactive"
                    echo "$f5hook remove $wanted_cert"
                    ((revoked_cert++))
                fi
        fi

        if [ $revoked_cert -ge 1000 ];
        then
                echo "Revoke limit hit - breaking"
                echo "Total number of revoked certs is $revoked_cert"
                echo "Total number of renewed certs is $renewed_cert"
                break
        fi

        if [ $renewed_cert -ge 1000 ];
        then
                echo "Renew limit hit - breaking"
                echo "Total number of revoked certs is $revoked_cert"
                echo "Total number of renewed certs is $renewed_cert"
                break
        fi
done
