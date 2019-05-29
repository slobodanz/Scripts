#!/bin/bash

CERTBOT_DOMAIN='atm0357.telia.atomia.se'
CERTBOT_VALIDATION='143132423412'
CERTBOT_TOKEN='afasdfasdf'


MAPS="/storage/configuration/maps"
USER=`grep $CERTBOT_DOMAIN $MAPS/users.map | awk '{print $2}'`
LAST=`echo -n $USER | tail -c 2`

ROOTDIR="/storage/content/$LAST/$USER/$CERTBOT_DOMAIN/public_html"
LEDIR="/var/www/html/le_cert/$CERTBOT_DOMAIN"

echo "rm -f $ROOTDIR/.well-known/acme-challenge/*"

if [ ! -d "$LEDIR" ]; then
  echo "mkdir -p $LEDIR"
  echo "chmod 755 $LEDIR"
  echo "cp /etc/letsencrypt/live/$CERTBOT_DOMAIN/fullchain.pem $LEDIR/$CERTBOT_DOMAIN.crt"
  echo "cp /etc/letsencrypt/live/$CERTBOT_DOMAIN/privkey.pem $LEDIR/$CERTBOT_DOMAIN.key"
  echo "chown apache:apache $LEDIR/*"
else
  echo "cp /etc/letsencrypt/live/$CERTBOT_DOMAIN/fullchain.pem $LEDIR/$CERTBOT_DOMAIN.crt"
  echo "cp /etc/letsencrypt/live/$CERTBOT_DOMAIN/privkey.pem $LEDIR/$CERTBOT_DOMAIN.key"
  echo "chown apache:apache $LEDIR/*"
fi
