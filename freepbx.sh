#!/bin/bash

# ------------------------------
# Script: Instalar Asterisk + FreePBX en Rocky Linux 8
# Proyecto: Casa Loma - Central Telefónica
# ------------------------------

set -e

# --- Variables ---
ASTERISK_VERSION=20.6.0
NODEJS_VERSION=16

# --- Paso 1: Actualizar el sistema ---
yum update -y
yum install epel-release -y
yum install -y wget curl git vim net-tools tmux bash-completion chrony tar unzip

# --- Paso 2: Instalar dependencias ---
yum groupinstall -y "Development Tools"
yum install -y gcc gcc-c++ make libxml2-devel ncurses-devel libuuid-devel libedit-devel

yum install -y pjproject pjproject-devel jansson-devel sqlite-devel

yum install -y mariadb-server mariadb mariadb-devel
systemctl enable --now mariadb

# --- Paso 3: Instalar Apache, PHP y dependencias ---
yum install -y httpd
systemctl enable --now httpd

# Repositorio Remi para PHP 7.4 (compatible con FreePBX)
dnf install -y https://rpms.remirepo.net/enterprise/remi-release-8.rpm
dnf module reset php -y
dnf module enable php:remi-7.4 -y
dnf install -y php php-cli php-mysqlnd php-xml php-mbstring php-process php-pdo php-zip php-curl php-gd

# --- Paso 4: Instalar NodeJS ---
curl -sL https://rpm.nodesource.com/setup_${NODEJS_VERSION}.x | bash -
yum install -y nodejs

# --- Paso 5: Descargar e instalar Asterisk ---
cd /usr/src
wget http://downloads.asterisk.org/pub/telephony/asterisk/asterisk-${ASTERISK_VERSION}.tar.gz
tar xvfz asterisk-${ASTERISK_VERSION}.tar.gz
cd asterisk-${ASTERISK_VERSION}

contrib/scripts/install_prereq install

./configure --with-pjproject-bundled
make menuselect.makeopts
menuselect/menuselect --enable CORE-SOUNDS-EN-WAV --enable MOH-OPSOUND-WAV --enable chan_pjsip menuselect.makeopts

make -j$(nproc)
make install
make samples
make config
ldconfig

# --- Paso 6: Crear usuario asterisk ---
useradd -m asterisk
chown -R asterisk. /var/run/asterisk
chown -R asterisk. /etc/asterisk
chown -R asterisk. /var/{lib,log,spool}/asterisk
chown -R asterisk. /usr/lib64/asterisk
sed -i 's/^#AST_USER="asterisk"/AST_USER="asterisk"/' /etc/sysconfig/asterisk
sed -i 's/^#AST_GROUP="asterisk"/AST_GROUP="asterisk"/' /etc/sysconfig/asterisk

# --- Paso 7: Descargar FreePBX ---
cd /usr/src
wget https://mirror.freepbx.org/modules/packages/freepbx/freepbx-16.0-latest.tgz
tar xfz freepbx-16.0-latest.tgz
cd freepbx

# --- Paso 8: Configurar base de datos ---
mysql -u root <<EOF
CREATE DATABASE asterisk;
CREATE DATABASE asteriskcdrdb;
GRANT ALL PRIVILEGES ON asterisk.* TO 'asteriskuser'@'localhost' IDENTIFIED BY 'casaLomaPass';
GRANT ALL PRIVILEGES ON asteriskcdrdb.* TO 'asteriskuser'@'localhost' IDENTIFIED BY 'casaLomaPass';
FLUSH PRIVILEGES;
EOF

# --- Paso 9: Instalar FreePBX ---
systemctl stop firewalld
systemctl disable firewalld
fwconsole chown
./start_asterisk start
./install -n

# --- Paso 10: Iniciar servicios ---
systemctl enable --now asterisk
systemctl restart httpd

# --- INFO FINAL ---
echo "\n✅ Instalación completada. Accede a FreePBX desde tu navegador:"
IP=$(hostname -I | awk '{print $1}')
echo "http://$IP/"
echo "\nUsuario por defecto: admin (configúralo tras ingresar)"
