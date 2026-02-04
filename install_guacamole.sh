#!/bin/bash

# --- CONFIGURATION ---
GUAC_VERSION="1.6.0"
MYSQL_CONN_VERSION="9.6.0"
MIGRATION_TOOL_VER="1.0.10"
DB_NAME="guac_db"
DB_USER="guac_user"
DB_PASS="password" # Hier dein Passwort anpassen

echo "Starting Apache Guacamole 1.6.0 installation for Ubuntu 24.04..."
cd ~

# 1. System Updates & Dependencies
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential libcairo2-dev libjpeg-turbo8-dev \
    libpng-dev libtool-bin libossp-uuid-dev libvncserver-dev \
    freerdp2-dev libssh2-1-dev libtelnet-dev libwebsockets-dev \
    libpulse-dev libvorbis-dev libwebp-dev libssl-dev \
    libpango1.0-dev libswscale-dev libavcodec-dev libavutil-dev \
    libavformat-dev wget

# 2. Building Guacamole Server
wget https://downloads.apache.org/guacamole/${GUAC_VERSION}/source/guacamole-server-${GUAC_VERSION}.tar.gz
tar -xvf guacamole-server-${GUAC_VERSION}.tar.gz
cd guacamole-server-${GUAC_VERSION}
./configure --with-systemd-dir=/etc/systemd/system --enable-allow-freerdp-snapshots
make -j$(nproc)
sudo make install
sudo ldconfig
cd ..

# 3. Library Path Fix
echo "/usr/local/lib" | sudo tee /etc/ld.so.conf.d/guacamole.conf
sudo ldconfig

# 4. Starting Guacamole Daemon
sudo systemctl start guacd.service
sudo systemctl enable guacd.service

# 5. Create directory structure
sudo mkdir -p /etc/guacamole/extensions
sudo mkdir -p /etc/guacamole/lib

# 6. Installing Apache Tomcat
sudo apt update
sudo apt install -y tomcat10 tomcat10-admin tomcat10-common tomcat10-user

# 7. Getting and Installing Guacamole Client & Migration Tool for Tomcat 10
cd ~
wget https://downloads.apache.org/guacamole/${GUAC_VERSION}/binary/guacamole-${GUAC_VERSION}.war
wget https://dlcdn.apache.org/tomcat/jakartaee-migration/v${MIGRATION_TOOL_VER}/binaries/jakartaee-migration-${MIGRATION_TOOL_VER}-bin.tar.gz

tar -xvf jakartaee-migration-${MIGRATION_TOOL_VER}-bin.tar.gz
cd ~/jakartaee-migration-1.0.10-bin/jakartaee-migration-1.0.10/lib/

# Converting from Javax to Jakarta (Tomcat 10 Fix)
java -jar apache-jakartaee-migration-${MIGRATION_TOOL_VER}/lib/jakartaee-migration-${MIGRATION_TOOL_VER}.jar guacamole-${GUAC_VERSION}.war guacamole-jakarta.war

sudo mv guacamole-jakarta.war /var/lib/tomcat10/webapps/guacamole.war

# 8. Database Setup
sudo apt install -y mariadb-server

sudo mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};"
sudo mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
sudo mysql -e "GRANT SELECT,INSERT,UPDATE,DELETE ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# 9. JDBC Extension & Connector
cd ~
wget https://downloads.apache.org/guacamole/${GUAC_VERSION}/binary/guacamole-auth-jdbc-${GUAC_VERSION}.tar.gz

tar -xf guacamole-auth-jdbc-${GUAC_VERSION}.tar.gz
sudo cp guacamole-auth-jdbc-${GUAC_VERSION}/mysql/guacamole-auth-jdbc-mysql-${GUAC_VERSION}.jar /etc/guacamole/extensions/

# Schema Import
cat ~/guacamole-auth-jdbc-${GUAC_VERSION}/mysql/schema/*.sql | sudo mysql ${DB_NAME}

# MySQL Connector
cd ~
wget https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-j-${MYSQL_CONN_VERSION}.tar.gz
tar -xf mysql-connector-j-${MYSQL_CONN_VERSION}.tar.gz
sudo cp mysql-connector-j-${MYSQL_CONN_VERSION}/mysql-connector-j-${MYSQL_CONN_VERSION}.jar /etc/guacamole/lib/

# 10. Creating Guacamole Properties
sudo bash -c "cat > /etc/guacamole/guacamole.properties <<EOF
# MySQL properties
mysql-hostname: 127.0.0.1
mysql-port: 3306
mysql-database: ${DB_NAME}
mysql-username: ${DB_USER}
mysql-password: ${DB_PASS}

guacd-hostname: localhost
guacd-port: 4822
EOF"

# 11. Permissions & Reboot
sudo systemctl daemon-reload
sudo systemctl enable --now guacd tomcat10 mariadb
sudo systemctl restart guacd tomcat10 mariadb

# 12. Cleaning archive files
sudo rm -r ~/*tar.gz

echo "----------------------------------------------------------"
echo "Installation completed!"
echo "URL: http://$(hostname -I | awk '{print $1}'):8080/guacamole"
echo "Login: guacadmin / guacadmin"
echo "----------------------------------------------------------"

