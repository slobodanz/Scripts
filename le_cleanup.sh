#!/bin/bash

WWW="www."
MAPS="/storage/configuration/maps"
DOMAIN=${CERTBOT_DOMAIN#$WWW}
USER=`grep $DOMAIN $MAPS/users.map | awk '{print $2}'`
LAST=`echo -n $USER | tail -c 2`

ROOTDIR="/storage/content/$LAST/$USER/$DOMAIN/public_html"
rm -f $ROOTDIR/.well-known/acme-challenge/*
