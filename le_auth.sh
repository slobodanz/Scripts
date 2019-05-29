#!/bin/bash

WWW="www."
MAPS="/storage/configuration/maps"
DOMAIN=${CERTBOT_DOMAIN#$WWW}
USER=`grep $DOMAIN $MAPS/users.map | awk '{print $2}'`
LAST=`echo -n $USER | tail -c 2`

ROOTDIR="/storage/content/$LAST/$USER/$DOMAIN/public_html"

if [ -d "$ROOTDIR" ]; then
   mkdir -p $ROOTDIR/.well-known/acme-challenge
   echo $CERTBOT_VALIDATION > $ROOTDIR/.well-known/acme-challenge/$CERTBOT_TOKEN
   chown $USER:apache -R $ROOTDIR/.well-known
else
  echo "Dir $ROOTDIR does not exsits"
  exit 1
fi
