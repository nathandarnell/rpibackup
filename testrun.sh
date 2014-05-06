#!/bin/bash
## Original Author: RonB123123
## Created: Sept 24, 2008
## From http://ubuntuforums.org/showthread.php?t=928475
## Also includes some code from various other sources
## Changed by Nathan Darnell
## Adapted by me to work on my RPi systems and be more flexible

##################################################################
## CONFIGURE
##################################################################
SERVICES="avahi-daemon deluge-daemon cron bubbleupnpserver fail2ban minidlna nginx nullmailer monitorix"    ## Declare what services to stop and start
SUBDIR=RaspberryPi2_backups   ## Setting up backup directories
DIR=/media/1TB/$SUBDIR  ## Change to where you want the backups to be stored
KEEPDAILY=7       ## How many daily (7 = 7 daily backups kept at one time), weekly, and monthly backups to keep
KEEPWEEKLY=28     ## As of now, this needs to be in days (4 weeks = 28 days = 4 backups kept for the weekly backup)
KEEPMONTHLY=90    ## So does this (3 months = 90 days = 3 monthly backups kept)
TESTRUN=1         ## Set this to "0" if you want to write to the disk.  CHange it to do a test run to just use "TOUCH" and clean up after itself.
##################################################################
## /CONFIGURE
##################################################################

OFILE="$DIR/backup_$(date +%Y%m%d_%H%M%S)"      # Create a filename with datestamp for our current backup (without .img suffix)
OFILEFINAL=$OFILE.daily.img   # Create final filename, with suffix
OFILEFINALWEEKLY=${OFILEFINAL/daily./weekly.}   # Create final weekly filename, with suffix
OFILEFINALMONTHLY=${OFILEFINAL/daily./monthly.}  # Create final monthly filename, with suffix

function InitialSetup {
      ## Screen clear
      clear

      ## Start the backup
      echo -e "Starting RaspberryPi backup process!"
      echo ""

      ## First check if pv package is installed, if not, install it first
      PACKAGESTATUS=$(dpkg -s pv | grep Status);

      if [[ $PACKAGESTATUS == S* ]]
      then
            echo -e "Package 'pv' is installed"
            echo ""
      else
            echo -e "Package 'pv' is NOT installed"
            echo -e "Installing package 'pv' + 'pv dialog'. Please wait..."
            echo ""
            sudo apt-get -y install pv
      fi

      ## Check if backup directory exists
      if [ ! -d "$DIR" ];   
      then
            echo -e "Backup directory $DIR doesn't exist, creating it now!"
            sudo mkdir $DIR
      fi
}



##################################################################
##List all the files with ".img" in $DIR
##Then list all files without ".img"
##################################################################
function ListBackups {
      echo ""
      echo -e "Last backups on HDD:"
      sudo find $DIR -maxdepth 1 -name "*.img"
      echo ""
      echo -e "Failed backups on HDD:"
      sudo find $DIR/ -maxdepth 1 -mindepth 1 ! -name "*.img"
      echo ""
}



##################################################################
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
      echo -e "Checking if there is enough diskspace for one more backup..."      
      if [ ${SOURCEDISKSPACE} -ge ${DESTDISKSPACE} ]; then
            echo "Not enough disk space on source ($DESTDISKSPACE) for backup, need $SOURCEDISKSPACE"
            exit 1
            else
            echo "There is enough disk space on source ($DESTDISKSPACE) for backup, we need $SOURCEDISKSPACE."
      fi
}



##################################################################
## Turn on and off the services listed in $SERVICES
##################################################################
function DeclaredServices {
      
      case "$1" in
      stop)
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
      ;;

      start)
      ##Restart the stopped services
            for service in $SERVICES
            do
                  echo "Starting $service..."
                  sudo /etc/init.d/$service start
            done 
      ;;
      esac
}



##################################################################
## Begin the backup process, should take about 20 minutes from a 16GB Class 10 SD card to HDD and double that over Samba
##################################################################
function WriteBackupToDisk {
      # First sync disks
      sync; sync
      echo ""
      echo -e "Backing up SD card to .IMG file on HDD"
      ## Write the image to the drive
      SDSIZE=$(sudo blockdev --getsize64 /dev/mmcblk0);
      sudo pv -tpreb /dev/mmcblk0 -s $SDSIZE | dd of=$OFILE bs=1M conv=sync,noerror iflag=fullblock
      ## Finalize the backup
      sudo mv $OFILE $OFILEFINAL
      echo ""
      echo -e "RaspberryPI backup process completed! The Backup file is: $OFILEFINAL"
      echo -e "Looking for backups older than $KEEPDAILY days"
## TODO: make this IF statement actually go after files older than 7 days as well as more than 7 in number
      if [ "$(find $DIR -maxdepth 1 -name "*.daily.img" | wc -l)" -ge "$KEEPDAILY" ]; then
            echo -e "Removing backups older than $KEEPDAILY days"
            sudo find $DIR -maxdepth 1 -name "*.daily.img" -exec rm {} \;
            ListBackups
      else
            echo -e "There were no backups older than $KEEPDAILY days to delete"
      fi
      sudo find $DIR -maxdepth 1 -name "*.daily.img" -mtime +$KEEPDAILY -exec ls {} \; ## Is there a problem with using "ls" here?

      echo -e "If any backups older than $KEEPDAILY days were found, they were deleted"
      
      ## Make the weekly and monthly backups
      WeeklyMonthlyBackups
}



##################################################################
## Make weekly and monthly backups
##################################################################
function WeeklyMonthlyBackups {
      ## Make weekly backup
      echo -e "Checking for weekly backups"
      if [[ ! -f $DIR/*.weekly.img ]]; then 
            echo -e "No weekly backups found so I am making the first one..."
            CheckDiskSpace
            sudo pv $OFILEFINAL > $OFILEFINALWEEKLY
      else
            echo -e "Weekly backups were found. Checking if a new one is needed..."
            if test $(find $DIR/*.weekly.img -mtime -7)
            then
                  echo -e "None are older than 7 days" 
            else
                  echo -e "Need a new weekly backup.  Making it now..."
                  CheckDiskSpace
                  sudo pv $OFILEFINAL > $OFILEFINALWEEKLY	## pv gives the user some feedback
                  sudo find $DIR -maxdepth 1 -name "*weekly.img" -mtime +$KEEPWEEKLY -exec rm {} \;	## Remove any weekly backups that are too old
            fi
      fi
      ## Make monthly backup
      echo -e "Checking for monthly backups"
      if [[ ! -f $DIR/*.monthly.img ]]; then 
            echo -e "No monthly backups found so I am making the first one..."
            CheckDiskSpace
            sudo pv $OFILEFINAL > $OFILEFINALMONTHLY
      else
            echo -e "Monthly backups were found. Checking if a new one is needed..."
            if test $(find $DIR/*.monthly.img -mtime -30)
            then
                  echo -e "None are older than 30 days" 
            else
                  echo -e "Need a new monthly backup.  Making it now..."
                  CheckDiskSpace
                  sudo pv $OFILEFINAL > $OFILEFINALMONTHLY
                  sudo find $DIR -maxdepth 1 -name "*monthly.img" -mtime +$KEEPMONTHLY -exec rm {} \;
            fi
      fi
      ListBackups

}



##################################################################
## Does a test run of the write with TOUCH and cleans up after itself
##################################################################
function TestRun {
      echo ""
      echo -e "Doing a test run of backing up SD card to .IMG file on HDD"
      touch $OFILE 

      sudo pv $OFILE > $OFILEFINAL
      echo ""
      echo -e "RaspberryPI backup process completed! The Backup file is: $OFILEFINAL"
      echo -e "Looking for backups older than $KEEPDAILY days"
## TODO: make this IF statement actually go after files older than 7 days as well as more than 7 in number
      if [ "$(find $DIR -maxdepth 1 -name "*.daily.img" | wc -l)" -ge "$KEEPDAILY" ]; then
            echo -e "Removing backups older than $KEEPDAILY days"
            sudo find $DIR -maxdepth 1 -name "*.daily.img" -exec rm {} \;
            ListBackups
      else
            echo -e "There were no backups older than $KEEPDAILY days to delete"
      fi
      sudo find $DIR -maxdepth 1 -name "*.daily.img" -mtime +$KEEPDAILY -exec ls {} \; ## Is there a problem with using "ls" here?

      echo -e "If any backups older than $KEEPDAILY days were found, they were deleted"
     
      WeeklyMonthlyBackups
      
      ListBackups
      
      echo "Cleaning up after myself by deleting the files that were just made"
      
      sudo rm -f $OFILE $OFILEFINAL $OFILEFINALWEEKLY $OFILEFINALMONTHLY
}

InitialSetup

DeclaredServices stop

## Check the TESTRUN variable and write to the disk or don't. Each returns a "0" for success and "1" for failure
if [ $TESTRUN == 0 ] 
then
      WriteBackupToDisk
else
      TestRun
fi

DeclaredServices start


