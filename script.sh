#!/bin/bash

# Make sure only root can run our script
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

#-------------------#
# Poin 1 and 2
#-------------------#

# On user creation, enable ssh access to users using 'PublicKey' PROVIDED BY THE USER

# ASK FOR USERNAME
if [ -z "$USERNAME" ]; then
    echo "Please enter a username to create: "
    read USERNAME
fi

# ASK FOR GROUP: 'devops' OR 'dev'
if [ -z "$GROUP" ]; then
    echo "Please enter a group to create, your choice is either 'devops' or 'dev': "
    read GROUP
fi

# CREATE USER WITHOUT PASSWORD WITH THE PROVIDED USERNAME
adduser --disabled-password --gecos "" $USERNAME
usermod -a -G $GROUP $USERNAME

# ASK FOR PUBKEY, COPY TO /tmp.
# ASSUME THAT THE DIRECTORY OF THE PUBKEY IS IN THE SAME DIRECTORY AS THIS SCRIPT
if [ -z "$PUBLIC_KEY" ]; then
    echo "Please enter your public key file: "
    read PUBLIC_KEY
fi

cp $PUBLIC_KEY /tmp/
chown $USERNAME:$USERNAME /tmp/$PUBLIC_KEY

# LOGIN AS THE CREATED USER TO COPY THE PUBKEY
su $USERNAME -c "if [ ! -d ~/.ssh ]; then
    mkdir ~/.ssh
    fi
    cat /tmp/$PUBLIC_KEY >> ~/.ssh/authorized_keys
    rm -rf /tmp/$PUBLIC_KEY
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/authorized_keys"
    # CHANGE THE PASSWORD
    pass=`openssl rand -base64 16`
    echo "$USERNAME:$pass" | chpasswd
    echo "User $USERNAME updated to password $pass"

#-------------------#
# Poin 3
#-------------------#

# Devops users have access on the server.
# sudoers file is in /etc/sudoers
# Modify the sudoers file to allow group devops to use sudo
# Add '%devops ALL=(ALL:ALL) ALL' to the bottom of the file
# Check if the line is already there
if [ grep -q "%devops ALL=(ALL:ALL) ALL" /etc/sudoers ]; then
    echo "ok"
else
    echo "%devops ALL=(ALL:ALL) ALL" >> /etc/sudoers
fi

#-------------------#
# Poin 4
#-------------------#

# OS is Ubuntu 18.04 LTS on a server with 1 CPU and 1 GB RAM 1.
# Server readiness and hardening

# Make sure that the server is up to date
apt-get update && apt-get upgrade -y

# Configure sysctl values to harden the server
if [ -f /etc/sysctl.d/60-custom.conf ]; then
    echo "ok"
else
    echo -e \
"net.core.wmem_default= 8388608
net.ipv4.tcp_window_scaling= 1
net.ipv4.tcp_timestamps= 1
net.core.rmem_default= 8388608
net.core.rmem_max= 16777216
net.core.wmem_max= 16777216
net.ipv4.tcp_rmem= 10240 87380 12582912
net.ipv4.route.flush=1
net.ipv4.tcp_wmem= 10240 87380 12582912
net.ipv4.tcp_sack= 1" >> /etc/sysctl.d/60-custom.conf
    # Reload sysctl.conf
    sysctl -p
fi

# Install the following packages:
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common

# Modify the sshd_config file to disable password authentication
# Check if the line 'PasswordAuthentication yes' is present
if grep -q "PasswordAuthentication yes" /etc/ssh/sshd_config; then
    # If the line is present, replace it with 'PasswordAuthentication no'
    sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
else
    # If the line is not present, add it to the end of the file
    echo "PasswordAuthentication no" | tee -a /etc/ssh/sshd_config
fi

if grep -q "PermitRootLogin yes" /etc/ssh/sshd_config; then
    # If the line is present, replace it with 'PermitRootLogin no'
    sed -i 's/PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config
else
    # If the line is not present, add it to the end of the file
    echo "PermitRootLogin no" | tee -a /etc/ssh/sshd_config
fi

# Add config for ClientAliveInterval and ClientAliveCountMax
# Change the ClientAliveInterval to 300 seconds
# Change the ClientAliveCountMax to 1
# Change the SSH TCP port to 22022
if grep -q "#ClientAliveInterval 0" /etc/ssh/sshd_config; then
    # If the line is present, replace it with 'ClientAliveInterval 300'
    sed -i 's/ClientAliveInterval 300/ClientAliveInterval 300/g' /etc/ssh/sshd_config
else
    # If the line is not present, add it to the end of the file
    echo "ClientAliveInterval 300" | tee -a /etc/ssh/sshd_config
fi

if grep -q "#ClientAliveCountMax 3" /etc/ssh/sshd_config; then
    # If the line is present, replace it with 'ClientAliveCountMax 4'
    sed -i 's/ClientAliveCountMax 4/ClientAliveCountMax 1/g' /etc/ssh/sshd_config
else
    # If the line is not present, add it to the end of the file
    echo "ClientAliveCountMax 1" | tee -a /etc/ssh/sshd_config
fi

if grep -q "#Port 22" /etc/ssh/sshd_config; then
    # If the line is present, replace it with 'Port 22022'
    sed -i 's/Port 22/Port 22022/g' /etc/ssh/sshd_config
else
    # If the line is not present, add it to the end of the file
    echo "Port 22022" | tee -a /etc/ssh/sshd_config
fi

systemctl restart sshd

ufw allow 22022
ufw allow 80
ufw allow 443
ufw allow 27017

# Install MongoDB

apt install gnupg -y
wget -qO - https://www.mongodb.org/static/pgp/server-5.0.asc | apt-key add -

# Check if this line is exists on /etc/apt/sources.list.d/mongodb-org-5.0.list
# echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/5.0 multiverse"
# If the line is not present, add it to the end of the file, otherwise do nothing
if grep -q "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/5.0 multiverse" /etc/apt/sources.list.d/mongodb-org-5.0.list; then
    # If the line is present, do nothing
    echo "ok"
else
    # If the line is not present, add it to the end of the file
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/5.0 multiverse" | tee -a /etc/apt/sources.list.d/mongodb-org-5.0.list
fi

apt update

apt install -y mongodb-org

# Start MongoDB and Apache
systemctl start mongod.service
systemctl enable mongod.service

# Install Apache
apt install apache2 -y
systemctl start apache2
systemctl enable apache2

#-------------------#
# Poin 9
#-------------------#

# Give rwx access to group dev on directory /opt/sayurbox/sample-web-app and all subdirectories
# Create a directory /opt/sayurbox/sample-web-app if it does not exist
mkdir -p /opt/sayurbox/sample-web-app
chown -R dev:dev /opt/sayurbox/sample-web-app
chmod 755 /opt/sayurbox/sample-web-app

# Add config to /etc/apache2/sites-available/sample-web-app.conf
# Check if it is already exists
if grep -q "DocumentRoot /opt/sayurbox/sample-web-app" /etc/apache2/sites-available/sample-web-app.conf; then
    # If the line is present, do nothing
    echo "ok"
else
    # Add this config
    echo -e \
    "<VirtualHost *:80>
        DocumentRoot /opt/sayurbox/sample-web-app
        ServerAdmin webmaster@localhost
        ServerName sample-web-app
        ServerAlias www.sample-web-app.com    
        ErrorLog ${APACHE_LOG_DIR}/error.log
        CustomLog ${APACHE_LOG_DIR}/access.log combined
    </VirtualHost>" | tee -a /etc/apache2/sites-available/sample-web-app.conf
fi

# Change the run user to dev
sed -i 's/www-data/dev/' /etc/apache2/envvars

# Disable 000-default.conf
a2dissite 000-default.conf

# Enable sample-web-app.conf
a2ensite sample-web-app.conf

systemctl restart apache2

#-------------------#
# Poin 10
#-------------------#

# Give group 'dev' read access to /var/log/*.log
chgrp -R dev /var/log/*.log
chmod g+r /var/log/*.log

# Install logrotate
apt install logrotate -y

# Add config to logrotate override
# Config: 14 days log retention
# Check if it is already exists
# The config is for all log files in /var/log, not just apache2
if grep -q "rotate 14" /etc/logrotate.conf; then
    # If the line is present, do nothing
    echo "ok"
else
    # Add this config
    echo -e \
    "/var/log/*.log {
        rotate 14
        daily
        missingok
        notifempty
        compress
        delaycompress
        sharedscripts
        postrotate
            /usr/bin/kill -HUP \`cat /var/run/syslogd.pid 2> /dev/null\` 2> /dev/null || true
        endscript
    }" | tee -a /etc/logrotate.conf
fi