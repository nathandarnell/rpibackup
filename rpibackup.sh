#!/bin/bash
## Original Author: RonB123123
## Created: Sept 24, 2008
## From http://ubuntuforums.org/showthread.php?t=928475
## Also includes some code from various other sources
## Changed by Nathan Darnell
## Adapted by me to work on my RPi systems and be more flexible
## Comments welcome as I am more of a Google-r than a programmer
## TODO: save to a logfile, change to all functions, 

SERVICES="avahi-daemon deluge-daemon cron bubbleupnpserver fail2ban minidlna nginx nullmailer monitorix"    ## Declare what services to stop and start
SUBDIR=$HOSTNAME_backups   ## Setting up backup directories
DIR=/media/1TB/$SUBDIR  ## Change to where you want the backups to be stored
KEEPDAILY=7       ## How many daily (7 = 7 daily backups kept at one time), weekly, and monthly backups to keep
KEEPWEEKLY=28     ## As of now, this needs to be in days (4 weeks = 28 days = 4 backups kept for the weekly backup)
KEEPMONTHLY=90    ## So does this (3 months = 90 days = 3 monthly backups kept)

## Setting up echo fonts
red='\e[0;31m'
green='\e[0;32m'
cyan='\e[0;36m'
yellow='\e[1;33m'
purple='\e[0;35m'
NC='\e[0m' #No Color
bold=`tput bold`
normal=`tput sgr0`

##List all the files with ".img" in $DIR
##Then list all files without ".img"
##################################################################
function ListBackups {
      echo ""
      echo -e "${purple}Last backups on HDD:${NC}"
      sudo find $DIR -maxdepth 1 -name "*.img" -exec ls {} \;
      echo ""
      echo -e "${purple}Failed backups on HDD:${NC}"
      sudo find $DIR/ -maxdepth 1 -mindepth 1 ! -name "*.img"
      echo ""
}

## Borrowed and adapted from http://hustoknow.blogspot.com/2011/01/bash-script-to-check-disk-space.html
##################################################################
function CheckDiskSpace {
      # Extract the disk space percentage capacity -- df dumps things out, sed strips the first line,
      # awk grabs the fourth column (Free), and cut removes the trailing G.
      DESTDISKSPACE=$(df -H $DIR | sed '1d' | awk '{print $4}' | cut -d'G' -f1)
      # Extract the source (SD Card) disk space percentage capacity -- df dumps things out, sed strips the first line,
      # awk grabs the second column (Size), and cut removes the trailing G.
      SOURCEDISKSPACE=$(df -H / | sed '1d' | awk '{print $2}' | cut -d'G' -f1)

      # Disk capacity check
      echo -e "${green}${bold}Checking if there is enough diskspace for one more backup...${NC}${normal}"      
      if [ ${SOURCEDISKSPACE} -ge ${DESTDISKSPACE} ]; then
            echo "Not enough disk space on source ($DESTDISKSPACE) for backup, need $SOURCEDISKSPACE"
            exit 1
            else
            echo "There is enough disk space on source ($DESTDISKSPACE) for backup, we need $SOURCEDISKSPACE."
      fi
}

## Screen clear
clear

## Start the backup
echo -e "${green}${bold}Starting RaspberryPi backup process!${NC}${normal}"
echo ""

## First check if pv package is installed, if not, install it first
PACKAGESTATUS=`dpkg -s pv | grep Status`;

if [[ $PACKAGESTATUS == S* ]]
   then
      echo -e "${cyan}${bold}Package 'pv' is installed${NC}${normal}"
      echo ""
   else
      echo -e "${yellow}${bold}Package 'pv' is NOT installed${NC}${normal}"
      echo -e "${yellow}${bold}Installing package 'pv' + 'pv dialog'. Please wait...${NC}${normal}"
      echo ""
      sudo apt-get -y install pv
fi

CheckDiskSpace

# Check if backup directory exists
if [ ! -d "$DIR" ];   
   then
      echo -e "${yellow}${bold}Backup directory $DIR doesn't exist, creating it now!${NC}${normal}"
      sudo mkdir $DIR
fi

# Create a filename with datestamp for our current backup (without .img suffix)
OFILE="$DIR/backup_$(date +%Y%m%d_%H%M%S)"

# Create final filename, with suffix
OFILEFINAL=$OFILE.img

# Create final weekly filename, with suffix
OFILEFINALWEEKLY=$OFILEFINAL.weekly.img

# Create final monthly filename, with suffix
OFILEFINALMONTHLY=$OFILEFINAL.monthly.img

# First sync disks
sync; sync

## Quit the declared services
for service in $SERVICES
do
echo "Stopping $service..."
sudo /etc/init.d/$service stop
if (ps ax | grep -v grep | grep $service > /dev/null)
then
echo "$service not stopped!"
break
fi
done 

# Begin the backup process, should take about 20 minutes from a 16GB Class 10 SD card to HDD and double that over Samba
echo ""
echo -e "${green}${bold}Backing up SD card to img file on HDD${NC}${normal}"
SDSIZE=`sudo blockdev --getsize64 /dev/mmcblk0`;
sudo pv -tpreb /dev/mmcblk0 -s $SDSIZE | dd of=$OFILE bs=1M conv=sync,noerror iflag=fullblock

# Wait for DD to finish and catch result
RESULT=$?

##Restart the stopped services
for service in $SERVICES
do
echo "Starting $service..."
sudo /etc/init.d/$service start
done 

# If command has completed successfully do weekly and monthly backups, if not, delete created files
if [ $RESULT = 0 ];
   then
     sudo mv $OFILE $OFILEFINAL
      echo ""
      echo -e "${green}${bold}RaspberryPI backup process completed! The Backup file is: $OFILEFINAL${NC}${normal}"
      echo -e "${yellow}Looking for backups older than $KEEPDAILY days${NC}"
## TODO: make this a IF statement to provide better feedback
      sudo find $DIR -maxdepth 1 -name "*.img" -mtime +$KEEPDAILY -exec ls {} \; ## Is there a problem with using "ls" here?
      echo -e "${yellow}Removing backups older than $KEEPDAILY days${NC}"
      sudo find $DIR -maxdepth 1 -name "*.img" -mtime +$KEEPDAILY -exec rm {} \;
      echo -e "${cyan}If any backups older than $KEEPDAILY days were found, they were deleted${NC}"
      
      ## Make weekly backup
      echo -e "${yellow}Checking for weekly backups${NC}"
      if [[ ! -f $DIR*.weekly.img ]]; then 
            echo -e "${yellow}No weekly backups found so I am making the first one...${NC}"
            CheckDiskSpace
            sudo pv $OFILEFINAL > $OFILEFINALWEEKLY
      else
            echo -e "${yellow}Weekly backups were found. Checking if a new one is needed...${NC}"
            if test $(find $DIR/*.weekly.img -mtime -7)
            then
                  echo -e "${yellow}None are older than 7 days${NC}" 
            else
                  echo -e "${yellow}Need a new weekly backup.  Making it now...${NC}"
                  CheckDiskSpace
                  sudo pv $OFILEFINAL > $OFILEFINALWEEKLY	## pv gives the user some feedback
                  sudo find $DIR -maxdepth 1 -name "*weekly.img" -mtime +$KEEPWEEKLY -exec rm {} \;	## Remove any weekly backups that are too old
            fi
      fi
      ## Make monthly backup
      echo -e "${yellow}Checking for monthly backups${NC}"
      if [[ ! -f $DIR*.monthly.img ]]; then 
            echo -e "${yellow}No monthly backups found so I am making the first one...${NC}"
            CheckDiskSpace
            sudo pv $OFILEFINAL > $OFILEFINALMONTHLY
      else
            echo -e "${yellow}Monthly backups were found. Checking if a new one is needed...${NC}"
            if test $(find $DIR/*.monthly.img -mtime -30)
            then
                  echo -e "${yellow}None are older than 30 days${NC}" 
            else
                  echo -e "${yellow}Need a new monthly backup.  Making it now...${NC}"
                  CheckDiskSpace
                  sudo pv $OFILEFINAL > $OFILEFINALMONTHLY
                  sudo find $DIR -maxdepth 1 -name "*monthly.img" -mtime +$KEEPMONTHLY -exec rm {} \;
            fi
      fi
      ListBackups
      exit 0
# Else remove attempted backup file
   else
      echo ""
      echo -e "${red}${bold}Backup failed!${NC}${normal}"
      sudo rm -f $OFILE
      ListBackups
      echo -e "${red}${bold}RaspberryPI backup process failed!${NC}${normal}"
      exit 1
fi
