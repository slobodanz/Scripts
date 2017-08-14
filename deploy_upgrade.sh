#!/bin/bash

if [ -z "$1" ] ; then
        echo "usage: $0 -a single|cluster -h hostname|clustername"
        echo "example:"
        echo -e "$0 -a cluster -h APACHE,FTP \t# will upgrade all servers in apache and ftp clusters"
        echo -e "$0 -a single -h apache01.atomia.hostcenter.com \t# will upgrade only apache01 server"
                echo "allowed clusters: HOSTING DNS FTP APACHE1 APACHE2 APACHE3 MAIL MYSQL LB STORAGE AILINT MIGRATION PUPPET LOINT BACULA NAGIOS"
        exit 1
fi

#Get current user ID
USER=`who am i | awk '{print $1}'`
USERKEY="/home/$USER/.ssh/id_rsa"

SERVERS="/opt/upgrade/servers.conf"
UPGRADED=0
HOSTS=""

#validates server types
function validate_type(){
config=$1
formated=`echo "$config" | tr ',' '\n'`
allowed="HOSTING DNS FTP APACHE1 APACHE2 APACHE3 MAIL MYSQL LB STORAGE AILINT MIGRATION PUPPET LOINT BACULA NAGIOS"

for types in $formated
do
        echo "$allowed" | grep -q "$types"
                comapre=$?

                if [ $comapre -eq 1 ];then
                echo "Type $types is not allowed. Allowed values are: $allowed"
                exit 1
                fi
done
return 0
}


function upgrade_cluster(){
TOUPGRADE=$1
while read -r line
do
        VMCONFIG="$line"
        if [[ $VMCONFIG != \#* ]]; then
                IP=`echo "$VMCONFIG" | cut -d '*' -f1 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'`
                TYPE=`echo "$VMCONFIG" | cut -d '*' -f3 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'`
                FQDN=`echo "$VMCONFIG" | cut -d '*' -f2 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'`

                echo "$TOUPGRADE" | grep -q "$TYPE"
                comapretype=$?

                if [ $comapretype -eq 0 ];then
                        echo "Enter your passphrase for server: $FQDN"
                        ssh -n -i "$USERKEY" "$USER@$IP" sudo unattended-upgrade -d
                        echo "$FQDN ($IP) is completed! - $TYPE"
                        ((UPGRADED++))
                fi
        fi

done < "$SERVERS"
echo "SERVERS UPGRADED IN TOTAL: $UPGRADED"
return 0
}

function upgrade_single(){
TOUPGRADE=$1
VM=`cat ${SERVERS} | grep "$TOUPGRADE"`
IP=`echo "$VM" | cut -d '*' -f1 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'`
FQDN=`echo "$VM" | cut -d '*' -f2 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'`

if [[ $IP == "" ]]; then
        echo "Server $TOUPGRADE not found!"
        exit 1
fi

echo "Enter your passphrase for server: $FQDN"
ssh -n -i "$USERKEY" "$USER@$IP" sudo unattended-upgrade -d
echo "$FQDN ($IP) is completed!"
return 0
}

while [ "$1" != "" ]; do
    case $1 in
        -a | --action )
                ACTION=$2
                shift 1
                ;;
        -h | --hosts )
                HOSTS=$2
                shift 1
                ;;
    esac
shift
done


if [[ $ACTION == "single" ]] ; then
    upgrade_single "$HOSTS"
elif [[ $ACTION == "cluster" ]] ; then
    validate_type "$HOSTS"
    upgrade_cluster "$HOSTS"
else
    echo "You have provided wrong ACTION: $ACTION !"
    echo "ACTION allowed single or cluster."
fi