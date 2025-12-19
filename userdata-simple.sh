#!/bin/bash

# Simple user_data script that downloads and executes the full Zabbix installation script
# This approach bypasses the 16KB user_data size limit

# Variables from Terraform
MYSQL_ROOT_PASSWORD="${mysql_root_password}"
ZABBIX_DB_PASSWORD="${zabbix_db_password}"

# Logging
exec > >(tee -a /var/log/zabbix-bootstrap.log)
exec 2>&1

echo "[$(date)] Starting Zabbix installation bootstrap..."

# Create the installation script directly on the instance
cat > /tmp/install-zabbix.sh << 'SCRIPT_EOF'
#!/bin/bash

# Zabbix 7.0 Automated Installation Script for Amazon Linux 2023
# This script automates the complete Zabbix installation process

# Variables from parameters
MYSQL_ROOT_PASSWORD="$1"
ZABBIX_DB_PASSWORD="$2"

# Installation markers directory
INSTALL_DIR="/opt/zabbix-install"
MARKERS_DIR="$INSTALL_DIR/markers"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/zabbix-install.log
}

# Create marker file for completed steps
create_marker() {
    mkdir -p "$MARKERS_DIR"
    touch "$MARKERS_DIR/$1"
    log "✓ Created marker: $1"
}

# Check if step is already completed
is_completed() {
    [[ -f "$MARKERS_DIR/$1" ]]
}

# Error handling - do not exit on error, handle gracefully
set +e
exec > >(tee -a /var/log/zabbix-install.log)
exec 2>&1

# Check if installation is already completed
if is_completed "installation_complete"; then
    log "Zabbix installation already completed. Exiting."
    exit 0
fi

log "Starting Zabbix 7.0 installation process..."

# Create installation directory
mkdir -p "$INSTALL_DIR" "$MARKERS_DIR"

# Update system
log "Updating system packages..."
dnf update -y

# 1. Install Zabbix repository
if ! is_completed "zabbix_repo"; then
    log "Installing Zabbix 7.0 repository..."
    if rpm -Uvh https://repo.zabbix.com/zabbix/7.0/amazonlinux/2023/x86_64/zabbix-release-latest-7.0.amzn2023.noarch.rpm; then
        dnf clean all && dnf makecache
        create_marker "zabbix_repo"
    else
        log "ERROR: Failed to install Zabbix repository"
        exit 1
    fi
else
    log "Zabbix repository already installed"
fi

# 2. Install packages
if ! is_completed "packages_installed"; then
    log "Installing required packages..."
    if dnf install -y zabbix-server-mysql zabbix-web-mysql zabbix-apache-conf zabbix-sql-scripts zabbix-agent \
                     php php-fpm php-cli php-gd php-bcmath php-mbstring php-xml php-ldap php-mysqlnd php-pdo php-curl php-zip \
                     httpd \
                     https://dev.mysql.com/get/mysql80-community-release-el9-1.noarch.rpm && \
       dnf install -y --nogpgcheck mysql-community-server mysql-community-client; then
        create_marker "packages_installed"
    else
        log "ERROR: Failed to install packages"
        exit 1
    fi
else
    log "Packages already installed"
fi

# 3. Start MySQL service
if ! is_completed "mysql_started"; then
    log "Starting MySQL service..."
    if systemctl start mysqld && systemctl enable mysqld; then
        create_marker "mysql_started"
        sleep 5
    else
        log "ERROR: Failed to start MySQL service"
        exit 1
    fi
else
    log "MySQL service already running"
fi

# 4. Configure MySQL root password and security
if ! is_completed "mysql_configured"; then
    log "Configuring MySQL security..."

    # Check if password is already set
    if mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1;" &>/dev/null; then
        log "MySQL root password already set"
        create_marker "mysql_configured"
    else
        # Method 1: Try without password
        if mysql -u root -e "
            ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
            DELETE FROM mysql.user WHERE User='';
            DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
            DROP DATABASE IF EXISTS test;
            DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
            FLUSH PRIVILEGES;
        " &>/dev/null; then
            log "✓ MySQL configured without initial password"
            create_marker "mysql_configured"
        else
            # Method 2: Try with temporary password
            TEMP_PASSWORD=$(sudo grep 'temporary password' /var/log/mysqld.log 2>/dev/null | awk '{print $NF}' | tail -1)
            if [[ -n "$TEMP_PASSWORD" ]] && mysql -u root -p"$TEMP_PASSWORD" --connect-expired-password -e "
                ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
                DELETE FROM mysql.user WHERE User='';
                DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
                DROP DATABASE IF EXISTS test;
                DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
                FLUSH PRIVILEGES;
            " &>/dev/null; then
                log "✓ MySQL configured with temporary password"
                create_marker "mysql_configured"
            else
                # Method 3: Use skip-grant-tables
                systemctl stop mysqld
                mysqld_safe --skip-grant-tables --skip-networking &
                MYSQLD_PID=$!
                sleep 5

                if mysql -u root -e "
                    FLUSH PRIVILEGES;
                    ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
                    DELETE FROM mysql.user WHERE User='';
                    DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
                    DROP DATABASE IF EXISTS test;
                    DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
                    FLUSH PRIVILEGES;
                " &>/dev/null; then
                    kill $MYSQLD_PID &>/dev/null
                    killall mysqld &>/dev/null
                    sleep 2
                    systemctl start mysqld
                    sleep 3
                    log "✓ MySQL configured with skip-grant-tables"
                    create_marker "mysql_configured"
                else
                    log "ERROR: All MySQL configuration methods failed"
                    exit 1
                fi
            fi
        fi
    fi

    # Final verification
    if ! mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1;" &>/dev/null; then
        log "ERROR: MySQL root password verification failed"
        exit 1
    fi
else
    log "MySQL already configured"
fi

# 5. Create Zabbix database and import schema
if ! is_completed "zabbix_db_setup"; then
    log "Setting up Zabbix database..."
    if mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "
        CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
        CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '$ZABBIX_DB_PASSWORD';
        GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
        SET GLOBAL log_bin_trust_function_creators = 1;
        FLUSH PRIVILEGES;
    " &>/dev/null; then
        log "✓ Zabbix database created"

        log "Importing Zabbix schema (this may take a few minutes)..."
        if zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql -u zabbix -p"$ZABBIX_DB_PASSWORD" zabbix; then
            mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SET GLOBAL log_bin_trust_function_creators = 0;" || true
            log "✓ Zabbix schema imported successfully"
            create_marker "zabbix_db_setup"
        else
            log "ERROR: Failed to import Zabbix schema"
            exit 1
        fi
    else
        log "ERROR: Failed to create Zabbix database"
        exit 1
    fi
else
    log "Zabbix database already setup"
fi

# 6. Configure Zabbix and PHP
if ! is_completed "configured"; then
    log "Configuring Zabbix server and PHP..."

    # Configure Zabbix server
    sed -i "s/^# DBPassword=.*/DBPassword=$ZABBIX_DB_PASSWORD/" /etc/zabbix/zabbix_server.conf
    sed -i "s/^# DBHost=.*/DBHost=localhost/" /etc/zabbix/zabbix_server.conf
    sed -i "s/^DBName=zabbix/DBName=zabbix/" /etc/zabbix/zabbix_server.conf
    sed -i "s/^DBUser=zabbix/DBUser=zabbix/" /etc/zabbix/zabbix_server.conf

    # Configure PHP
    PHP_INI="/etc/php.ini"
    sed -i 's/max_execution_time = .*/max_execution_time = 300/' $PHP_INI
    sed -i 's/memory_limit = .*/memory_limit = 128M/' $PHP_INI
    sed -i 's/post_max_size = .*/post_max_size = 16M/' $PHP_INI
    sed -i 's/upload_max_filesize = .*/upload_max_filesize = 2M/' $PHP_INI
    sed -i 's/max_input_time = .*/max_input_time = 300/' $PHP_INI
    sed -i 's/max_input_vars = .*/max_input_vars = 10000/' $PHP_INI
    sed -i 's/;date.timezone =.*/date.timezone = Asia\/Seoul/' $PHP_INI

    create_marker "configured"
    log "✓ Configuration completed"
else
    log "Already configured"
fi

# 7. Start and enable services
if ! is_completed "services_started"; then
    log "Starting services..."

    services="httpd php-fpm zabbix-server zabbix-agent"
    for service in $services; do
        if systemctl restart "$service" && systemctl enable "$service"; then
            log "✓ $service started successfully"
        else
            log "✗ Failed to start $service"
            systemctl status "$service" --no-pager
        fi
    done

    sleep 10
    create_marker "services_started"
else
    log "Services already started"
fi

# 8. Final verification and completion
log "Performing final verification..."
services="httpd php-fpm zabbix-server zabbix-agent mysqld"
for service in $services; do
    if systemctl is-active "$service" >/dev/null 2>&1; then
        log "✓ $service is running"
    else
        log "✗ $service is not running"
    fi
done

# Verify database tables
TABLE_COUNT=$(mysql -u zabbix -p"$ZABBIX_DB_PASSWORD" zabbix -e "SHOW TABLES;" 2>/dev/null | wc -l)
ACTUAL_COUNT=$((TABLE_COUNT - 1))
log "Database tables created: $ACTUAL_COUNT"

# Create installation info
cat > /home/ec2-user/zabbix-install-info.txt << EOF
Zabbix 7.0 Installation Completed at: $(date)
===================================================

Web Interface: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)/zabbix

Initial Login Credentials:
- Username: Admin
- Password: zabbix

Database Information:
- MySQL Root Password: $MYSQL_ROOT_PASSWORD
- Zabbix DB Password: $ZABBIX_DB_PASSWORD
- Database Tables: $ACTUAL_COUNT

Services Status:
$(for svc in $services; do echo "- $svc: $(systemctl is-active $svc)"; done)

Installation Log: /var/log/zabbix-install.log
Installation Markers: $MARKERS_DIR

Next Steps:
1. Access the web interface using the URL above
2. Complete the initial setup wizard
3. Change the default admin password
4. Configure monitoring targets
EOF

create_marker "installation_complete"

log "🎉 Zabbix 7.0 installation completed successfully!"
log "🌐 Web interface: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)/zabbix"

echo "========================================="
echo "✅ ZABBIX 7.0 INSTALLATION SUCCESSFUL ✅"
echo "========================================="
SCRIPT_EOF

# Make the script executable
chmod +x /tmp/install-zabbix.sh

# Execute the installation script with parameters
echo "[$(date)] Executing Zabbix installation script..."
/tmp/install-zabbix.sh "$MYSQL_ROOT_PASSWORD" "$ZABBIX_DB_PASSWORD"

echo "[$(date)] Bootstrap completed."