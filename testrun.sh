#!/bin/bash
## Original Author: RonB123123
## Created: Sept 24, 2008
## From http://ubuntuforums.org/showthread.php?t=928475
## Also includes some code from various other sources
## Changed by Nathan Darnell
## Adapted by me to work on my RPi systems and be more flexible (I hope!)

##################################################################
## CONFIGURE
##################################################################
SERVICES="  avahi-daemon
            deluge-daemon 
            cron 
            bubbleupnpserver 
            fail2ban 
            minidlna 
            nginx 
            nullmailer 
            monitorix"        ## Declare what services to stop and start
SUBDIR=RaspberryPi2_backups   ## Setting up backup directories
DIR=/media/1TB/$SUBDIR        ## Change to where you want the backups to be stored
KEEPDAILY=7                   ## How many daily (7 = 7 daily backups kept at one time), weekly, and monthly backups to keep
KEEPWEEKLY=28                 ## As of now, this needs to be in days (4 weeks = 28 days = 4 backups kept for the weekly backup)
KEEPMONTHLY=90                ## So does this (3 months = 90 days = 3 monthly backups kept)
TESTRUN=1                     ## Set this to "0" if you want to write to the disk.  Change it to do a test run to just use "TOUCH" and clean up after itself.
TESTRUNPERM=1                 ## Set this to "0" if you don't want to leave the TestRun files on the disk, but delete them (Leaving the files can be useful for testing the weekly and monthly backups)
##################################################################
## /CONFIGURE
##################################################################

OFILE="$DIR/backup_$(date +%Y%m%d_%H%M%S)"      # Create a filename with datestamp for our current backup (without .img suffix)
OFILEFINAL=$OFILE.daily.img   # Create final filename, with suffix
OFILEFINALWEEKLY=${OFILEFINAL/daily./weekly.}   # Create final weekly filename, with suffix
OFILEFINALMONTHLY=${OFILEFINAL/daily./monthly.}  # Create final monthly filename, with suffix

function InitialSetup {
      echo ""
      echo "$FUNCNAME"
      echo ""
      ## Screen clear
      clear

      ## Start the backup
      echo "Starting RaspberryPi backup process!"
      echo ""

      ## First check if pv package is installed, if not, install it first
      PACKAGESTATUS=$(dpkg -s pv | grep Status);

      if [[ $PACKAGESTATUS == S* ]]
      then
            echo "Package 'pv' is installed"
            echo ""
      else
            echo "Package 'pv' is NOT installed"
            echo "Installing package 'pv' + 'pv dialog'. Please wait..."
            echo ""
            apt-get -y install pv
      fi

      ## Check if backup directory exists
      if [ ! -d "$DIR" ];   
      then
            echo "Backup directory $DIR doesn't exist, creating it now!"
            mkdir $DIR
      fi
}



##################################################################
##List all the files with ".img" in $DIR
##Then list all files without ".img"
##################################################################
function ListBackups {
      echo ""
      echo "$FUNCNAME"
      echo ""
      echo "Last backups on HDD:"
      find $DIR -maxdepth 1 -name "*.img"
      echo ""
      echo "Failed backups on HDD:"
      find $DIR/ -maxdepth 1 -mindepth 1 ! -name "*.img"
      echo ""
}



##################################################################
## Borrowed and adapted from http://hustoknow.blogspot.com/2011/01/bash-script-to-check-disk-space.html
##################################################################
function CheckDiskSpace {
      echo ""
      echo "$FUNCNAME"
      echo ""
      ## No need to check diskspace if we're not writing real files!
      if [ "$TESTRUN" == "0" ]
      then
      # Extract the disk space percentage capacity -- df dumps things out, sed strips the first line,
      # awk grabs the fourth column (Free), and cut removes the trailing G.
      DESTDISKSPACE=$(df -H $DIR | sed '1d' | awk '{print $4}' | cut -d'G' -f1)
      # Extract the source (SD Card) disk space percentage capacity -- df dumps things out, sed strips the first line,
      # awk grabs the second column (Size), and cut removes the trailing G.
      SOURCEDISKSPACE=$(df -H / | sed '1d' | awk '{print $2}' | cut -d'G' -f1)

      # Disk capacity check
      echo "Checking if there is enough diskspace for one more backup..."      
      if [ ${SOURCEDISKSPACE} -ge ${DESTDISKSPACE} ]; then
            echo "Not enough disk space on source ($DESTDISKSPACE) for backup, need $SOURCEDISKSPACE"
            exit 1
            else
            echo "There is enough disk space on source ($DESTDISKSPACE) for backup, we need $SOURCEDISKSPACE."
      fi
      else
            echo "Not going to check diskspace since we're only TOUCHing files here..."
      fi
}



##################################################################
## Turn on and off the services listed in $SERVICES
##################################################################
function DeclaredServices {
      echo ""
      echo "$FUNCNAME"
      echo ""
      
      case "$1" in
      stop)
      ## Quit the declared services
      for service in $SERVICES
      do
            if (pgrep -f "$service" > /dev/null)
                  then
                        echo "Stopping $service..."
                        /etc/init.d/"$service" stop
                  ## Try replacing ps grep with pgrep and see if it works...  Old IF is below...
                  ##if (ps ax | grep -v grep | grep "$service" > /dev/null)
                  ##
                        if (pgrep -f "$service" > /dev/null)
                        then
                                    echo "$service not stopped!"
                                    break
                        fi
                  fi

      done 
      ;;

      start)
      ##Restart the stopped services
            for service in $SERVICES
            do
                  echo "Starting $service..."
                  /etc/init.d/"$service" start
            done 
      ;;
      esac
}



##################################################################
## Begin the backup process, should take about 20 minutes from a 16GB Class 10 SD card to HDD and double that over Samba
##################################################################
function WriteBackupToDisk {
      echo ""
      echo "$FUNCNAME"
      echo ""
      # First sync disks
      sync; sync
      echo ""
      echo "Backing up SD card to .IMG file on HDD"
      ## Write the image to the drive
      SDSIZE=$(blockdev --getsize64 /dev/mmcblk0);
      pv -tpreb /dev/mmcblk0 -s "$SDSIZE" | dd of="$OFILE" bs=1M conv=sync,noerror iflag=fullblock
      ## Finalize the backup
      mv "$OFILE" "$OFILEFINAL"
      echo ""
      echo "RaspberryPI backup process completed! The Backup file is: $OFILEFINAL"
      echo "Looking for backups older than $KEEPDAILY days"
## TODO: make this IF statement actually go after files older than 7 days as well as more than 7 in number
      if [ "$(find $DIR -maxdepth 1 -name "*.daily.img" | wc -l)" -ge "$KEEPDAILY" ]; then
            echo "Removing backups older than $KEEPDAILY days"
            find $DIR -maxdepth 1 -name "*.daily.img" -exec rm {} \;
            ListBackups
      else
            echo "There were no backups older than $KEEPDAILY days to delete"
      fi
      find $DIR -maxdepth 1 -name "*.daily.img" -mtime +$KEEPDAILY -exec ls {} \; ## Is there a problem with using "ls" here?

      echo "If any backups older than $KEEPDAILY days were found, they were deleted"
      
      ## Make the weekly and monthly backups
      WeeklyMonthlyBackups
      
      ListBackups
}



##################################################################
## Make weekly and monthly backups
##################################################################
function WeeklyMonthlyBackups {
      WEEKLYBACKUPNAMES=$(find $DIR -maxdepth 1 -name '*weekly.img')
      OLDWEEKLYBACKUPNAMES=$(find $DIR -maxdepth 1 -name '*weekly.img' -mtime +7)
      echo ""      
      echo "$FUNCNAME"
      echo ""

      echo "Checking for weekly backups"
      if [ -n "$(find $DIR -maxdepth 1 -name '*weekly.img')" ]; then 
            echo "Weekly backups were found. Checking if a new one is needed..."


## compare the weekly backups older than 7 days against the total weekly backups
            if [ "$(find $DIR -maxdepth 1 -name "*weekly.img" -mtime +7 | wc -l)" -lt "$(find $DIR -maxdepth 1 -name "*weekly.img" | wc -l)" ]
            then
                  echo "None are older than 7 days" 
                  
                  echo "MY BEST BET AT WEEKLY BACKUP NAMES" 
                  echo "$WEEKLYBACKUPNAMES" 
                   
                  echo "MY BEST BET AT old WEEKLY BACKUP NAMES" 
                  echo "$OLDWEEKLYBACKUPNAMES" 
            else
                  echo "Need a new weekly backup.  Making it now..."
                  CheckDiskSpace
                  pv "$OFILEFINAL" > "$OFILEFINALWEEKLY"	## pv gives the user some feedback
                  find $DIR -maxdepth 1 -name "*weekly.img" -mtime +$KEEPWEEKLY -exec rm {} \;	## Remove any weekly backups that are too old
            fi
      else
            echo "No weekly backups found so I am making the first one..."
            CheckDiskSpace
            pv "$OFILEFINAL" > "$OFILEFINALWEEKLY"
      fi
      ## Make monthly backup
      echo "Checking for monthly backups"
      if [ -n "$(find $DIR -maxdepth 1 -name '*monthly.img')" ]; then 
           echo "Monthly backups were found. Checking if a new one is needed..."

            if [ "$(find $DIR -maxdepth 1 -name "*monthly.img" -mtime +30 | wc -l)" -lt "$(find $DIR -maxdepth 1 -name "*monthly.img" | wc -l)" ]
            then
                  echo "None are older than 30 days" 
            else
                  echo "Need a new monthly backup.  Making it now..."
                  CheckDiskSpace
                  pv "$OFILEFINAL" > "$OFILEFINALMONTHLY"  ## pv gives the user some feedback
                  find $DIR -maxdepth 1 -name "*monthly.img" -mtime +$KEEPMONTHLY -exec rm {} \; ## Remove any monthly backups that are too old
            fi 
      else
            echo "No monthly backups found so I am making the first one..."
            CheckDiskSpace
            pv "$OFILEFINAL" > "$OFILEFINALMONTHLY"
      fi
}



##################################################################
## Does a test run of the write with TOUCH and cleans up after itself
##################################################################
function TestRun {
      echo ""
      echo "$FUNCNAME"
      echo ""
      echo "Doing a test run of backing up SD card to .IMG file on HDD..."
      touch "$OFILE"
      mv "$OFILE" "$OFILEFINAL"
      echo ""
      echo "RaspberryPI backup process completed! The Backup file is: $OFILEFINAL"
      echo ""
      echo "The daily backups are:"
      DAILYBACKUPNAMES=$(find $DIR -maxdepth 1 -name "*.daily.img")
      echo "$DAILYBACKUPNAMES"
      
      
      ## Remove old daily backups beyond $KEEPDAILY
      echo ""
      echo "Looking for backups older than $KEEPDAILY days..."

      if [ "$(find $DIR -maxdepth 1 -name "*.daily.img" -mtime +"$KEEPDAILY" | wc -l)" -ge "1" ]; then
            echo "Removing backups older than $KEEPDAILY days..."
            find $DIR -maxdepth 1 -name "*.daily.img" -mtime +"$KEEPDAILY" -exec echo Removing old backups: {} \; -exec rm {} \;
            ListBackups
      else
            echo ""
            echo "There were no backups older than $KEEPDAILY days to delete"
      fi
      
      
      ## Remove daily backups if there are more than $KEEPDAILY in the $DIR
      echo ""
      echo "Looking for more daily backups than $KEEPDAILY..."

      if [ "$(find $DIR -maxdepth 1 -name "*.daily.img" | wc -l)" -gt "$KEEPDAILY" ]; then
            echo "Removing backups so there are only $KEEPDAILY daily backups..."
            
            ## This should find daily backups in the $DIR and delete them if there are more than $KEEPDAILY
            find "$DIR" -maxdepth 1 -type f -name \*daily.img | sort -n -t _ -k 3 | head -n -$KEEPDAILY | xargs rm -f
            
            
            ListBackups
      else
            echo "There were no backups older than $KEEPDAILY days to delete or more in number than $KEEPDAILY"
      fi
      
      
      
     
      WeeklyMonthlyBackups
      
      ListBackups

      ## Delete the empty files that were made
      if [ $TESTRUNPERM == 0 ]; then
            echo "Cleaning up after myself by deleting the files that were just made"
            rm -f "$OFILE" "$OFILEFINAL" "$OFILEFINALWEEKLY" "$OFILEFINALMONTHLY"
      fi
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


