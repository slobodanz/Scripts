#!/bin/bash

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
   echo "usage: $0 operation type domain"
   echo "example:"
   echo "$0 [add|replace|remove] [letsencrypt|premium] example.com"
   exit 1
fi

typeset -A config # init config array

while read line
do
  if echo $line | grep -F = &>/dev/null
  then
        varname=$(echo "$line" | cut -d '=' -f 1)
        config[$varname]=$(echo "$line" | cut -d '=' -f 2-)
  fi
done < /etc/f5bigip.conf

OPERATION=$1
DOMAIN=$2
TIME=`date '+%Y-%m-%d %H:%M:%S'`
LOGFILE=${config[log_file]}

case $3 in
	letsencrypt)
		DOWNLOAD_URL=${config[apache_url_letsencrypt]}
	;;
	premium)
		DOWNLOAD_URL=${config[apache_url_premium]}
	;;
	*)
		echo "Wrong certificate type used"
		exit 1
	;;
esac

echo "" | tee -a $LOGFILE
echo "Timestamp: $TIME" | tee -a $LOGFILE
echo "Action: $OPERATION for domain: $DOMAIN" | tee -a $LOGFILE

#curl command with credentials
CURL="curl -sk -u ${config[f5_user]}:${config[f5_pass]} -H \"Content-Type: application/json\""

#get virtual server status:Q
VSRV=`$CURL -X GET ${config[f5_url]}/mgmt/tm/ltm/virtual/~Common~${config[v_server]} | jq '.enabled'`
if [ $VSRV != 'true' ]; then
        echo "Virtul server ${config[v_server]} is not configured! Exit!" | tee -a $LOGFILE
        exit 1
fi

case $OPERATION in
        add)
          #validate certificate and key
          if  ! wget --spider $DOWNLOAD_URL/$DOMAIN/$DOMAIN.crt 2>/dev/null; then
            echo "Certificate does not exists on remote webserver $DOWNLOAD_URL/$DOMAIN/$DOMAIN.crt. Exit!" | tee -a $LOGFILE
            exit 1
          fi

          if  ! wget --spider $DOWNLOAD_URL/$DOMAIN/$DOMAIN.key 2>/dev/null; then
             echo "Private key does not exists on remote webserver $DOWNLOAD_URL/$DOMAIN/$DOMAIN.key. Exit!" | tee -a $LOGFILE
             exit 1
          fi

          #curl comand to get information about cert,key,ssl profile
          CURL_GET="curl -sk -u ${config[f5_user]}:${config[f5_pass]} ${config[f5_url]}/mgmt/tm"

          #Manage certificate
          CERT=`$CURL_GET/sys/file/ssl-cert/~Common~"$DOMAIN".crt | jq '.name'`
          #if exists, delete and upload again
          JSON_CERT="'"{\"command\":\"install\",\"name\":\"$DOMAIN.crt\",\"from-url\":\"$DOWNLOAD_URL/$DOMAIN/$DOMAIN.crt\"}"'"
          ADD_CERT="$CURL -X POST ${config[f5_url]}/mgmt/tm/sys/crypto/cert -d $JSON_CERT | jq '.' | tee -a $LOGFILE"

          if [ $CERT == \"$DOMAIN".crt\"" ]; then
             echo "Certificate $DOMAIN.crt already uploaded on F5." | tee -a $LOGFILE
          else
             echo "Certificate $DOMAIN.crt not uploaded.Uploading..." | tee -a $LOGFILE
             eval $ADD_CERT
          fi


          #Manage keys
          KEY=`$CURL_GET/sys/file/ssl-key/~Common~"$DOMAIN".key | jq '.name'`
          #if exists, delete and upload again
          JSON_KEY="'"{\"command\":\"install\",\"name\":\"$DOMAIN.key\",\"from-url\":\"$DOWNLOAD_URL/$DOMAIN/$DOMAIN.key\"}"'"
          ADD_KEY="$CURL -X POST ${config[f5_url]}/mgmt/tm/sys/crypto/key -d $JSON_KEY | jq '.' | tee -a $LOGFILE"

          if [ $KEY == \"$DOMAIN".key\"" ]; then
             echo "Key $DOMAIN.key already uploaded on F5." | tee -a $LOGFILE
          else
             echo "Key $DOMAIN.key not uploaded.Uploading..." | tee -a $LOGFILE
             eval $ADD_KEY
          fi

          #Manage SSL profile
          SSL_PROFILE=`$CURL_GET/ltm/profile/client-ssl/~Common~$DOMAIN | jq '.name'`
          if [ $SSL_PROFILE == \"$DOMAIN\" ]; then
             echo "SSL profile $DOMAIN already created." | tee -a $LOGFILE
          else
             echo "SSL profile $DOMAIN not created. Creating..." | tee -a $LOGFILE
             JSON_SSL="'"{\"name\":\"$DOMAIN\",\"cert\":\"$DOMAIN.crt\",\"key\":\"$DOMAIN.key\"}"'"
             ADD_SSL="$CURL -X POST ${config[f5_url]}/mgmt/tm/ltm/profile/client-ssl -d $JSON_SSL | jq '.' | tee -a $LOGFILE"
             eval $ADD_SSL
          fi

          #Assign SSL profile to Virtual Server
          ASSIGNED=`$CURL_GET/ltm/virtual/~Common~${config[v_server]}/profiles/$DOMAIN | jq '.name'`
          if [ $ASSIGNED == \"$DOMAIN\" ]; then
             echo "SSL profile $DOMAIN  already assigned to Virtual Server ${config[v_server]}." | tee -a $LOGFILE
          else
             echo "SSL profile $DOMAIN not assigned to ${config[v_server]}. Configuring..." | tee -a $LOGFILE
             JSON_VSRV="'"{\"context\":\"clientside\",\"name\":\"$DOMAIN\"}"'"
             ASSIGN_SSL="$CURL -X POST ${config[f5_url]}/mgmt/tm/ltm/virtual/~Common~${config[v_server]}/profiles -d $JSON_VSRV | jq '.' | tee -a $LOGFILE"
             eval $ASSIGN_SSL
          fi
          ;;

        remove)
          echo "Removing certificate and configurations for $DOMAIN" | tee -a $LOGFILE
          #Delete SSL profile from Virtual Server
          `$CURL -X DELETE ${config[f5_url]}/mgmt/tm/ltm/virtual/~Common~${config[v_server]}/profiles/$DOMAIN`
          #Delete SSL profile
          `$CURL -X DELETE ${config[f5_url]}/mgmt/tm/ltm/profile/client-ssl/~Common~$DOMAIN`
          #Delete private key
          `$CURL -X DELETE ${config[f5_url]}/mgmt/tm/sys/file/ssl-key/~Common~"$DOMAIN".key`
          #Delete certificate
          `$CURL -X DELETE ${config[f5_url]}/mgmt/tm/sys/file/ssl-cert/~Common~"$DOMAIN".crt`
          echo "Certificate for $DOMAIN deleted from F5." | tee -a $LOGFILE
          ;;


        replace)
          echo "Certificate cleanup for $DOMAIN." | tee -a $LOGFILE
          `$CURL -X DELETE ${config[f5_url]}/mgmt/tm/ltm/virtual/~Common~${config[v_server]}/profiles/$DOMAIN`
          `$CURL -X DELETE ${config[f5_url]}/mgmt/tm/ltm/profile/client-ssl/~Common~$DOMAIN`
          `$CURL -X DELETE ${config[f5_url]}/mgmt/tm/sys/file/ssl-key/~Common~"$DOMAIN".key`
          `$CURL -X DELETE ${config[f5_url]}/mgmt/tm/sys/file/ssl-cert/~Common~"$DOMAIN".crt`

          echo "Create certificate, private key, ssl profile for $DOMAIN" | tee -a $LOGFILE
          JSON_CERT="'"{\"command\":\"install\",\"name\":\"$DOMAIN.crt\",\"from-url\":\"$DOWNLOAD_URL/$DOMAIN/$DOMAIN.crt\"}"'"
          ADD_CERT="$CURL -X POST ${config[f5_url]}/mgmt/tm/sys/crypto/cert -d $JSON_CERT"
          eval $ADD_CERT

          JSON_KEY="'"{\"command\":\"install\",\"name\":\"$DOMAIN.key\",\"from-url\":\"$DOWNLOAD_URL/$DOMAIN/$DOMAIN.key\"}"'"
          ADD_KEY="$CURL -X POST ${config[f5_url]}/mgmt/tm/sys/crypto/key -d $JSON_KEY"
          eval $ADD_KEY

          JSON_SSL="'"{\"name\":\"$DOMAIN\",\"cert\":\"$DOMAIN.crt\",\"key\":\"$DOMAIN.key\"}"'"
          ADD_SSL="$CURL -X POST ${config[f5_url]}/mgmt/tm/ltm/profile/client-ssl -d $JSON_SSL"
          eval $ADD_SSL

          JSON_VSRV="'"{\"context\":\"clientside\",\"name\":\"$DOMAIN\"}"'"
          ASSIGN_SSL="$CURL -X POST ${config[f5_url]}/mgmt/tm/ltm/virtual/~Common~${config[v_server]}/profiles -d $JSON_VSRV"
          eval $ASSIGN_SSL
          ;;

         *)
          echo "Wrong operation called!" | tee -a $LOGFILE
          ;;
esac
