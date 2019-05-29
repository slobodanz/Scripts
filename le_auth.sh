#!/bin/bash

CERTBOT_DOMAIN='atm0357.telia.atomia.se'
CERTBOT_VALIDATION='143132423412'
CERTBOT_TOKEN='afasdfasdf'


WWW="www."
MAPS="/storage/configuration/maps"
DOMAIN=${CERTBOT_DOMAIN#$WWW}
USER=`grep $DOMAIN $MAPS/users.map | awk '{print $2}'`
LAST=`echo -n $USER | tail -c 2`

ROOTDIR="/storage/content/$LAST/$USER/$DOMAIN/public_html"

if [ -d "$ROOTDIR" ]; then
  echo "mkdir -p $ROOTDIR/.well-known/acme-challenge"
  echo "echo $CERTBOT_VALIDATION > $ROOTDIR/.well-known/acme-challenge/$CERTBOT_TOKEN"
  echo "chown $USER:apache -R $ROOTDIR/.well-known"
else
  exit 1
fi
