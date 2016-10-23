#!/bin/bash
# This script automatically upgrades a nextcloud installation and creates a backup of all important data before doing so
# Copyright (c) 2015 Pascal Wichmann

nextcloudPath="/srv/http/nextcloud/" # change to fit path of you nextcloud installation
nextcloudDataPath="/srv/webdata/nextcloud/" # change to fit path of your nextcloud data directory
backupDir="/backup" # change to fit path where your backup should be placed
backupVersions=5
mysqlBackup=false  # to enable mysql backup, your user needs to have a valid mysql client configuration (i.e. .my.cnf) in order to authenticate; it may be possible to authenticate interactively, however, the easiest way is to configure the mysql client correctly
mysqlBackup_database="nextcloud"
webUser="www-data"
phpPath="/usr/bin/php"

if [ "$1" == "-h" ] || [ "$1" == "" ]; then
  echo "Usage: nextcloudUpgrade.sh version"
  echo " version: You need to specify the version which should be installed (i.e. 8.2.2)"
  echo "Script written by Pascal Wichmann, Copyright (c) 2016"
  exit 0
fi

# check if temporary directory exists (Indicating a running process of this upgrade script)
if [ -d "/tmp/nextcloudUpgrade" ]; then
  echo "Temporary directory /tmp/nextcloudUpgrade is already existing. Remove it  and start the script again, but first make sure that there is NO OTHER INSTANCE of this script running."
  exit 0
fi

# validate backup versions parameter
if ! [ -z $(echo $backupVersions | tr -d 0-9) ] || [ -z "$backupVersions" ]; then  # check that the versions parameter for backups is a valid integer
  echo "The specified backup versions parameter is invalid."
  exit 0
fi

# TODO: create a dedicated script for backup which is executed separately (to have the ability to create automated nextcloud backups withouth upgrade)

echo "Creating backup"

# move old backups
backupVersions=$((backupVersions-1))  # decrement backup versions count (indexing begins with 0)
# delete oldest backup (if exists)
rm -rf ${backupDir}/backup.${backupVersions} &> /dev/null
backupVersions=$((backupVersions-1))  # decrement backup versions count once again (oldest backup has already been deleted)

while [ $backupVersions -ge 0 ]
do
  mv ${backupDir}/backup.${backupVersions} ${backupDir}/backup.$((backupVersions+1)) &> /dev/null
  backupVersions=$((backupVersions-1))
done

# create directories for newest backup (and parents if backupDir does not exist yet)
mkdir -p ${backupDir}/backup.0/files

# create backup of files
rsync -a ${nextcloudPath} ${backupDir}/backup.0/files
rsync -a ${nextcloudDataPath} ${backupDir}/backup.0/data

# create backup of database (if enabled)
if [ $mysqlBackup = true ]; then
  mysqldump --databases ${mysqlBackup_database} > ${backupDir}/backup.0/db.sql
fi

echo "backup finished"
echo "starting nextcloud upgrade"

# create temporary directory
mkdir /tmp/nextcloudUpgrade
cd /tmp/nextcloudUpgrade

# download nextcloud archive and extract it
curl https://download.nextcloud.com/server/releases/nextcloud-${1}.tar.bz2 | tar -xj

# turn nextcloud maintenance mode on
sudo -u $webUser $phpPath ${nextcloudPath}occ maintenance:mode --on

# move new files
rsync -a nextcloud/ $nextcloudPath

# set correct permissions on new files
chown -R $webUser:$webUser $nextcloudPath

# database upgrade
sudo -u $webUser $phpPath ${nextcloudPath}occ upgrade

# turn maintenance mode off
sudo -u $webUser $phpPath ${nextcloudPath}occ maintenance:mode --off

# remove temporary nextcloud upgrade directory
cd
rm -rf /tmp/nextcloudUpgrade

echo "finished nextcloud upgrade"
