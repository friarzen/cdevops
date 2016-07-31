#!/bin/bash

# This assumes you are running as root on ubuntu 16.04 or later,
# have ssh keys set up for your github account,
# have cdevopskey.pem stored in /root/,
# are spinning up an instance called web1,
# and have exported AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY to your environment
KEYFILE="/root/cdevopskey.pem"
USER="ubuntu"
HOST="web1"

if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
	echo "Missing ENVs:"
	echo "    export AWS_ACCESS_KEY_ID=your_access_key_id"
	echo "    export AWS_SECRET_ACCESS_KEY=your_secret_access_key"
	exit 1
fi

if [ -z "$AWS_REGION" ]; then
	export AWS_REGION="us-east-1"
fi

if [ "$(id -u)" != "0" ]; then
	echo "please run this as root or sudo"
	exit 1
fi


# attempt to figure out our "puppetmaster" IP4 address dynamically using ifconfig
IFCONFIG=`which ifconfig`
if [ -n $IFCONFIG ] && [ -x $IFCONFIG ]; then
	export FACTER_serverip=`$IFCONFIG|grep inet|egrep -v '(inet6|127.0.0.1)'|cut -d: -f2|cut -d' ' -f1`
fi

# override with public-ipv4 if we are an AWS instance
AWS_PUBLIC_IP=`curl -s http://169.254.169.254/latest/meta-data/public-ipv4`
if [[ $AWS_PUBLIC_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
	export FACTER_serverip="$AWS_PUBLIC_IP"
fi

echo "Using FACTER_serverip=$FACTER_serverip"

# Package setup
if ! dpkg --get-selections | grep nmap; then
	apt-get -y install nmap
fi

if ! dpkg --get-selections | grep awscli; then
	apt-get -y install awscli
fi

if ! dpkg --get-selections | grep puppet; then
	apt-get -y install puppet
fi

if ! gem list | grep aws-sdk-core; then
	gem install aws-sdk-core
fi

if ! gem list | grep retries; then
	gem install retries
fi

# make sure puppet common files are up to date
if [ -d "/etc/puppet/hiera" ]; then
        cd /etc/puppet
	git pull
else
        cd /etc
        rm -rf /etc/puppet
	git clone https://github.com/friarzen/cdevops puppet
fi

cd /etc/puppet/env

# Make sure production puppet environment branch is up to date
if [ -d "/etc/puppet/env/production" ]; then
	cd /etc/puppet/env/production
	git pull
	cd ..
else
	git clone https://github.com/friarzen/cdevops-env production
	cd /etc/puppet/env/production
	git checkout production
	cd ..
fi

# Make sure dev puppet environment branch is up to date
if [ -d "/etc/puppet/env/dev" ]; then
	cd /etc/puppet/env/dev
	git pull
	cd ..
else
	git clone https://github.com/friarzen/cdevops-env dev
	cd /etc/puppet/env/dev
	git checkout dev
	cd ..
fi

# test to make sure we have some place to put Certificate Authority files
if [ ! -e "/etc/puppet/ca" ]; then
	mkdir /etc/puppet/ca
fi

# Make sure the puppet master is restarted
PM=`ps -ef | grep puppet | grep master`
if [ "$?" != "0" ]; then
	puppet master
else
	kill -TERM `echo $PM | cut -d' ' -f2`
	sleep 2
	puppet master
fi

sleep 2

# install the puppetlabs-aws module 
MOD=`puppet module list | grep puppetlabs-aws`
if [ -z "$MOD" ]; then
	puppet module install puppetlabs-aws --environment common
fi

# spin up the defined infrastructure boxes
puppet apply /etc/puppet/env/provisioning/manifests/create.pp --test | tee ./puppet.log
if ! grep "Notice: Finished catalog run" ./puppet.log ; then
	echo "Spin request failed, puppet run did not finish well"
	exit 1
fi

# Give AWS time to spin
sleep 30

# Run Puppet agent on the new box. 
PUBIP=`aws ec2 describe-instances --region $AWS_REGION --filters "Name=tag-value,Values=$HOST" | grep PublicIpAddress | cut -d\" -f4`

if [ -z "$PUBIP" ]; then
	echo "Could not obtain Public IP address for $HOST"
	exit 1
fi

echo "Searching for $PUBIP"

if ! nmap $PUBIP -p 22 | grep "22/tcp open"; then
for x in 1 2 3 4 5 6
do
        if ! nmap $PUBIP -p 22 | grep "22/tcp open"; then
		sleep 60
	fi
done
fi

if ! nmap $PUBIP -p 22 | grep "22/tcp open"; then
	echo "Tried for over 6 minutes to connect...$PUBIP still not responding"
	exit 1
fi



# do the client side provisioning -- this is a hack so I dont have to create a custom AMI
ssh-keyscan -t rsa,dsa $PUBIP >> /root/.ssh/known_hosts

cat <<EOL > /etc/puppet/provision.sh
#! bash -ex

apt-get -y install puppet

curl -s http://169.254.169.254/latest/user-data > /home/$USER/user_data.txt
hostname \`grep hostname /home/$USER/user_data.txt | cut -d= -f2\`

grep hosts /home/$USER/user_data.txt | cut -d= -f2 >> /etc/hosts

echo '[main]' > /etc/puppet/puppet.conf
echo 'logdir=/var/log/puppet' >> /etc/puppet/puppet.conf
echo 'vardir=/var/lib/puppet' >> /etc/puppet/puppet.conf
echo 'ssldir=/var/lib/puppet/ssl' >> /etc/puppet/puppet.conf
echo 'rundir=/run/puppet' >> /etc/puppet/puppet.conf
echo 'factpath=\$vardir/lib/facter' >> /etc/puppet/puppet.conf
grep environment /home/$USER/user_data.txt >> /etc/puppet/puppet.conf
echo '[agent]' >> /etc/puppet/puppet.conf
grep server= /home/$USER/user_data.txt >> /etc/puppet/puppet.conf

systemctl enable puppet.service

puppet agent --enable

if ! puppet agent -t; then
    echo "puppet agent failed or changed something"
fi

exit 0
EOL

scp -qi $KEYFILE /etc/puppet/provision.sh "$USER@$PUBIP:provision.sh"
if [ "$?" != 0 ]; then
	echo "Could not copy provision to $HOST"
	exit 1
fi

ssh -i $KEYFILE -tq $USER@$PUBIP sudo bash /home/$USER/provision.sh
if [ "$?" != 0 ]; then
	echo "provisioning $HOST failed!"
	exit 1
fi

# validate firewall
if [ `nmap -p1-21,23-79,81-442,444-65535 $PUBIP | grep "^[0-9]" | wc -l` != "0" ]; then
	echo "Invalid scannable ports detected"
	exit 1
fi

# test1 -- should produce a 301 redirect error page
if ! curl -ks "http://$PUBIP:80/" | grep "301 Moved Permanently" ; then
	echo "Invalid redirect response detected"
	exit 1
fi 

# test2 -- should redirect and produce the bland "Hello World" html
if [ `curl -Lks "http://$PUBIP:80/" | md5sum` = "cda50b8445ec91c9f1d0ec23dafcd010  -" ]; then
	echo "Invalid http to https response detected"
	exit 1
fi

exit 0
