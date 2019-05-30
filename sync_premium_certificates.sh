#!/bin/sh

if [ -z "$1" ]; then
	echo "usage: $0 rsync path to certificate base folder"
	echo "example:"
	echo "$0 /storage/content/ssl"
	exit 1
fi

synced_dir="/appdir/atomia/ssl/synced_certificates"
intermediate_dir="$synced_dir/intermediates"
f5_cert_dir="/appdir/atomia/ssl/premium_certificates"
f5_download_dir="/var/www/html/premium"
f5hook=/appdir/atomia/f5_hook.sh
mkdir -p "$intermediate_dir"
mkdir -p "$f5_cert_dir"

# Sync all files from /storage/content/ssl to local dir
rsync -a -e "ssh -o StrictHostKeyChecking=no" --delete "$1"/ "$synced_dir"

# Create symlinks from cert subject to the public cert key for intermediates
if [ -d "$intermediate_dir" ]; then
	find "$intermediate_dir" -type f | while read intermediate; do
		intermediate_subject=`openssl x509 -noout -subject -in "$intermediate" |\
			cut -d "=" -f 2- | sed 's/^[[:space:]]*//' | tr "/" "#"`
		subject_link="$intermediate_dir/$intermediate_subject"
		if ! [ -L "$subject_link" ]; then
			ln -s "$intermediate" "$subject_link"
		fi
	done
fi

# Go through all customer certificates with keys and create bundles in the dir haproxy uses
newcerts_loaded=`mktemp`
certs_on_storage=`mktemp`
newcerts_to_upload_f5=`mktemp`
echo "0" > "$newcerts_loaded"
find "$synced_dir" -type f -path "*/keys/*" | while read key; do
	cert=`echo "$key" | sed 's,/keys/,/certificates/,'`

	if [ -f "$cert" ]; then
		# Figure out if there is already newer cert bundles created for the same CN
		# or if this bundle was created previously
		old_cert_bundle_to_remove=""
		cert_subject=`openssl x509 -noout -subject -in "$cert" |\
			awk -F 'CN=' '{ print $2 }' | tr "/" " " | cut -d " " -f 1`
		cert_end_date=`date +%s \
			-d "$(openssl x509 -noout -enddate -in "$cert" | cut -d "=" -f 2- | sed 's/^[[:space:]]*//')"`
		echo "$cert_subject"_"$cert_end_date" >> "$certs_on_storage"
		if [ -n "$cert_end_date" ] && [ -n "$cert_subject" ]; then
			cert_for_same_cn=`ls "$f5_cert_dir" | grep "^${cert_subject}_" \
				| cut -d "_" -f 2 | cut -d . -f 1 | head -n 1`
			if echo "$cert_for_same_cn" | grep "^$cert_end_date"'$' > /dev/null; then
				# This cert is already generated
				continue
			elif [ -n "$cert_for_same_cn" ]; then
				if [ "$cert_end_date" -lt "$cert_for_same_cn" ]; then
					# This cert is older than some other already generated cert for same CN
					continue
				else
					# This cert is newer than the existing one for the same CN
					old_cert_bundle_to_remove="$f5_cert_dir/${cert_subject}_${cert_for_same_cn}.pem"
				fi
			fi
		else
			echo "ERROR: couldn't determine endDate or subject for cert $cert"
			continue
		fi

		# If we only have one certificate in the file, then lets figure out the intermediate ourself 
		num_certs_in_file=`grep "BEGIN CERTIFICATE" "$cert" | wc -l | tr -d " "`
		intermediate=""
		if [ x"$num_certs_in_file" = x"1" ]; then
			intermediate_subject=`openssl x509 -noout -issuer -in "$cert" |\
				cut -d "=" -f 2- | sed 's/^[[:space:]]*//' | tr "/" "#"`
			subject_link="$intermediate_dir/$intermediate_subject"
			if [ -L "$subject_link" ]; then
				intermediate=`cat "$subject_link"`
			fi
		fi

		# We found a new cert, lets generate the bundle and remove the old bundle for this CN if existing
		echo "1" > "$newcerts_loaded"
		echo "OK: generating certificate bundle for $cert_subject with end timestamp $cert_end_date"
		#create files for F5 upload
		mkdir -p $f5_download_dir/${cert_subject}
		chown apache:apache $f5_download_dir/${cert_subject}
		(cat "$cert";
		 echo "$intermediate" | grep -v '^$') > $f5_download_dir/${cert_subject}/${cert_subject}.crt
		 chown apache:apache $f5_download_dir/${cert_subject}/${cert_subject}.crt
		(cat "$key") > $f5_download_dir/${cert_subject}/${cert_subject}.key
		 chown apache:apache $f5_download_dir/${cert_subject}/${cert_subject}.key
		 echo "${cert_subject}" > "$newcerts_to_upload_f5"
		 #done creating files for F5
		(cat "$cert";
		 echo "$intermediate" | grep -v '^$';
		 cat "$key") > "$f5_cert_dir/${cert_subject}_${cert_end_date}.pem"
		if [ -n "$old_cert_bundle_to_remove" ]; then
			rm -f "$old_cert_bundle_to_remove"
			echo "OK: removing old certificate bundle for $cert_subject from $old_cert_bundle_to_remove"
		fi
	fi
done

active_certs=`mktemp`
cert_diff=`mktemp`
# Synchronize public certificates folder with active ones
find "$f5_cert_dir" -type f -not -name 'default.pem' | while read active_cert; do
	# or if this bundle was created previously
	active_cert_subject=`openssl x509 -noout -subject -in "$active_cert" | awk -F 'CN=' '{ print $2 }' | tr "/" " " | cut -d " " -f 1`
	active_cert_end_date=`date +%s \
		-d "$(openssl x509 -noout -enddate -in "$active_cert" | cut -d "=" -f 2- | sed 's/^[[:space:]]*//')"`
	echo "$active_cert_subject"_"$active_cert_end_date" >> "$active_certs"
done

#upload new certificate on F5
cat "$newcerts_to_upload_f5" | while read line; do
	echo "OK: Uploading certificate for $line"
	$f5hook replace premium $line
done

# Find certificates no more available on shared storage
grep -Fxv -f "$certs_on_storage" "$active_certs" > "$cert_diff"
rm -f "$certs_on_storage" "$active_certs"

# Remove certificates from actives
cat "$cert_diff" | while read line; do
	obsolete_cert="$f5_cert_dir/${line}.pem"
	rm -f "$obsolete_cert"
	echo "OK: removing obsolete certificate bundle for $line from $obsolete_cert"
	domain=`echo "$line" | cut -d '_' -f1`
	$f5hook remove premium $domain
	rm -Rf "$f5_download_dir/$domain"
done

rm -f "$cert_diff"
rm -f "$newcerts_loaded"
rm -f "$newcerts_to_upload_f5"
