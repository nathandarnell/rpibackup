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
                              ## Add any services and the script will shut them down if they are running
SERVICESDIR=/etc/init.d       ## Point to where all the services are located to look for them and start and stop them.  May be another location that works better for this...
SUBDIR=RaspberryPi2_backups   ## Setting up backup directories
DIR=/media/1TB/$SUBDIR        ## Change to where you want the backups to be stored
KEEPDAILY=7                   ## How many daily (7 = 7 daily backups kept at one time), weekly, and monthly backups to keep
KEEPWEEKLY=28                 ## As of now, this needs to be in days (4 weeks = 28 days = 4 backups kept for the weekly backup)
KEEPMONTHLY=90                ## So does this (3 months = 90 days = 3 monthly backups kept)
INCREMENTALBACKUPS=1          ## Set this to 0 if you want to disable incremental backups or make it 1 to enable them
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"  ## Prevents errors when running as a cron job
##################################################################
## /CONFIGURE
##################################################################

##################################################################
## SET VARIABLES
##################################################################
OFILE="$DIR/backup_$(date +%Y%m%d_%H%M%S)"      # Create a filename with datestamp for our current backup (without .img suffix)
OFILEFINAL=$OFILE.daily.img   # Create final filename, with suffix
OFILEFINALWEEKLY=${OFILEFINAL/daily./weekly.}   # Create final weekly filename, with suffix
OFILEFINALMONTHLY=${OFILEFINAL/daily./monthly.}  # Create final monthly filename, with suffix
##################################################################
## /SET VARIABLES
##################################################################

##################################################################
## Consolodate the parts of WriteBackupToDisk and 
## WeeklyMonthlyBackups that look for old or too many backups
## and removes them verbosely
##################################################################
function PurgeOldBackups {
echo ""
echo "$FUNCNAME"
echo ""
## See what kind of backup to purge and change the value of $KEEPTIME to the appropriate value
if [[ $1 = daily ]]; then
  KEEPTIME=$KEEPDAILY
  KEEPTYPE=daily.img
elif [[ $1 = weekly ]]; then
  KEEPTIME=$KEEPWEEKLY
  KEEPTYPE=weekly.img
elif [[ $1 = monthly ]]; then
  KEEPTIME=$KEEPMONTHLY
  KEEPTYPE=monthly.img
elif [[ $1 = delta ]]; then
  KEEPTIME=$KEEPDAILY
  KEEPTYPE=img.delta
else
  return 1
fi
## Remove old selected backups beyond $KEEPTIME based on age
echo "Looking for backups older than $KEEPTIME days..."
if [[ "$(find $DIR -maxdepth 1 -name "*$KEEPTYPE" -mtime +"$KEEPTIME" | wc -l)" -ge "1" ]]; then
  echo "Found backups older than $KEEPTIME days!"
  echo "Deleting the backups older than $KEEPTIME days:"
  find $DIR -maxdepth 1 -name "*$KEEPTYPE" -mtime +"$KEEPTIME"
  find $DIR -maxdepth 1 -name "*$KEEPTYPE" -mtime +"$KEEPTIME" -exec rm {} \;
  ListBackups "$1"
else
  echo "There were no backups older than $KEEPTIME days to delete."
  ListBackups "$1"
fi
## Only run this for dailys and deltas
if [[ $1 = daily ]] || [[ $1 = delta ]]; then
  ## Remove selected backups if there are more than $KEEPTIME in the $DIR based on count
  echo ""
  echo "Looking for more daily backups than $KEEPTIME..."
  if [[ "$(find $DIR -maxdepth 1 -name "*$KEEPTYPE" | wc -l)" -gt "$KEEPTIME" ]]; then
    echo "There are more than $KEEPTIME daily backups!"
    echo "Removing backups so there are only $KEEPTIME daily backups..."
    ## This should find the selected backups in $DIR and delete them if there are more than $KEEPTIME
    echo "Deleting:"
    find "$DIR" -maxdepth 1 -type f -name \*$KEEPTYPE | sort -n -t _ -k 3 | head -n -$KEEPTIME | xargs
    find "$DIR" -maxdepth 1 -type f -name \*$KEEPTYPE | sort -n -t _ -k 3 | head -n -$KEEPTIME | xargs rm -f
    ListBackups "$1"
  else
    echo "There were no backups older than $KEEPTIME days, or more in number than $KEEPTIME to delete."
  fi
else
return
fi
}


##################################################################
## Make the delta file for the daily backup to reduce disk space usage
##################################################################
function MakeIncrementalBackup {
echo ""
echo "$FUNCNAME"
echo ""
if [[ ! $INCREMENTALBACKUPS == 0 ]]; then
  ## Check if there is a weekly backup to use as the base for the delta file
  if [[ -s "$(find "$DIR" -maxdepth 1 -name "*weekly.img" | sort -rn | head -1)" ]]; then
    ## Base the delta on the most resent weekly backup
    DELTAORIG="$(find "$DIR" -maxdepth 1 -name "*weekly.img" | sort -rn | head -1)"
  else
  find "$DIR" -maxdepth 1 -name "*weekly.img" ## Test
  find "$DIR" -maxdepth 1 -name "*weekly.img" | sort -rn | head -1 ## Test
    echo "There are no weekly backups to base the delta on.  Something must have gone wrong..."
    return 1 ## I think this means there was an error??
  fi
  
  ## Make a delta of the daily backup using the weekly backup (??) as the original
  ## Whatever weekly backup is the most recent, that is what all the daily incrementals are going to be based on
  echo "Making an incremental backup based on the most recent weekly backup which is:"
  echo "$DELTAORIG"
  echo "This should take about 30 minutes and it is now $(date +"%T")"
  DELTASTARTTIME=$(date +%s)
  xdelta3 -e -s "$DELTAORIG" "$OFILEFINAL" "$OFILEFINAL".delta
  DELTAENDTIME=$(date +%s)
  echo "The incremental backup is finished!"
  echo "The time is now $(date +"%T") and it took $(((DELTAENDTIME - DELTASTARTTIME) / 60)) minutes to make!"
  ## Now that the delta has been made, delete the fullsize daily backup
  echo "Deleting the fullsize daily backup:"
  echo "$OFILEFINAL"
  rm -f "$OFILEFINAL" 
## Remove old delta backups beyond $KEEPDAILY
PurgeOldBackups delta
## List all the delta backups

else
  return
fi
}


## Adapted from: http://stackoverflow.com/a/15808052
function RestoreIncrementalBackup {
## Xdelta3 usage https://code.google.com/p/xdelta/wiki/CommandLineSyntax
## Check if a deltafile was passed
if [[ -z "$1" ]]; then
## If no deltafile was passed then get the user to select one
	DELTAFILES=($(find "$DIR" -maxdepth 1 -type f -name '*.delta'))

	PROMPT="Please select a file:"

	PS3="$PROMPT"
	select DELTAFILE in "${DELTAFILES[@]}" "Quit" ; do 
		if (( REPLY == 1 + ${#DELTAFILES[@]} )) ; then
        	exit

		elif (( REPLY > 0 && REPLY <= ${#DELTAFILES[@]} )) ; then
			echo  "You picked $DELTAFILE which is file $REPLY"
			##                   ^                        ^
			## The selected deltafile      The selected option
## TODO fix this code!
			xdelta3 -d -v -s  $DELTAFILE remadebackup_20140508_222319.daily.img
			break

		else
			echo "Invalid option. Try another one."
		fi
	done

## If a delta file was passed then try to rebuild the .IMG file with it
else
xdelta3 -d -v -s  $DELTAFILE remadebackup_20140508_222319.daily.img

fi
}


##################################################################
## Check for PV to give a status bar for the writing and
## check for xdelta3 to do incremental backups (if selected) and
## check for $DIR to write the backups to
##################################################################
function InitialSetup {
## Screen clear
clear

## Start the backup
echo "Starting RaspberryPi backup process!"

## First check if pv package is installed, if not, install it
echo "Checking to see if 'PV' is installed..."
PACKAGESTATUS=$(dpkg -s pv | grep Status);
if [[ $PACKAGESTATUS == S* ]]; then
  echo "Package 'PV' is installed"
else
  echo "Package 'PV' is NOT installed"
  echo "Installing package 'PV'. Please wait..."
  apt-get -y install pv
fi

## First check if Xdelta3 is installed, if not, install it
if [[ $INCREMENTALBACKUPS == 1 ]]; then
  echo "Checking to see if 'Xdelta3' is installed..."
  PACKAGESTATUS=$(dpkg -s xdelta3 | grep Status);
  if [[ $PACKAGESTATUS == S* ]]; then
    echo "Package 'Xdelta3' is installed"
  else
    echo "Package 'Xdelta3' is NOT installed"
    echo "Installing package 'Xdelta3'..."
    apt-get -y install xdelta3
  fi
fi

## Check if backup directory exists
echo "Checking for the backup directory $DIR..."
if [[ ! -d "$DIR" ]]; then
  echo "Backup directory $DIR doesn't exist, creating it now!"
  mkdir $DIR
else
  echo "$DIR does exist!"
fi
}


##################################################################
## List all the files with ".img" in $DIR
## Lists all the files with "img.delta in $DIR
## Then list all files without ".img"
##################################################################
function ListBackups {

LISTBACKUPINPUT=$1
if [[ $# -eq 0 ]] ; then
  return 1
else
  case "$LISTBACKUPINPUT" in
    daily)
      echo "The Daily backups are:"
      find "$DIR" -maxdepth 1 -name '*daily.img' | sort
    ;;
    weekly)
      echo "The Weekly backups are:"
      find "$DIR" -maxdepth 1 -name '*weekly.img' | sort
    ;;
    monthly)
      echo "The Monthly backups are:"
      find "$DIR" -maxdepth 1 -name '*monthly.img' | sort
    ;;
    delta)
      echo "The Delta backups are:"
      find "$DIR" -maxdepth 1 -name '*img.delta' | sort
    ;;
    failed)
      echo "The Failed backups are:"
      find "$DIR" -maxdepth 1 -mindepth 1 ! -name "*.img*" | sort
    ;;
  esac
fi
}

##################################################################
## Borrowed and adapted from http://hustoknow.blogspot.com/2011/01/bash-script-to-check-disk-space.html
##################################################################
function CheckDiskSpace {
echo ""
echo "$FUNCNAME"
echo ""

# Extract the disk space percentage capacity -- df dumps things out, sed strips the first line,
# awk grabs the fourth column (Free), and cut removes the trailing G.
DESTDISKSPACE="$(df -H $DIR | sed '1d' | awk '{print $4}' | cut -d'G' -f1)"
# Extract the source (SD Card) disk space percentage capacity -- df dumps things out, sed strips the first line,
# awk grabs the second column (Size), and cut removes the trailing G.
SOURCEDISKSPACE="$(df -H / | sed '1d' | awk '{print $2}' | cut -d'G' -f1)"

# Disk capacity check
echo "Checking if there is enough diskspace for one more backup..."      
if [[ "$SOURCEDISKSPACE" -ge "$DESTDISKSPACE" ]]; then
  echo "Not enough disk space on source ($DESTDISKSPACE GB) for backup, need $SOURCEDISKSPACE GB."
  exit 1
else
  echo "There is enough disk space on source ($DESTDISKSPACE GB) for backup, we need $SOURCEDISKSPACE GB."
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
      if [[ -n "$(find "$SERVICESDIR" -maxdepth 1 -name "$service")" ]]; then
        echo "Stopping $service..."
        /etc/init.d/"$service" stop
        ## Try replacing ps grep with pgrep and see if it works...  Old IF is below...
        ##if (ps ax | grep -v grep | grep "$service" > /dev/null)
        ##
        if (pgrep -f "$service" > /dev/null); then
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
      if [[ -n "$(find "$SERVICESDIR" -maxdepth 1 -name "$service")" ]]; then
			  echo "Starting $service..."
			  /etc/init.d/"$service" start
		  fi
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
echo "Backing up SD card to .IMG file on HDD"

## Write the image to the drive
SDSIZE=$(blockdev --getsize64 /dev/mmcblk0);
pv -tpreb /dev/mmcblk0 -s "$SDSIZE" | dd of="$OFILE" bs=1M conv=sync,noerror iflag=fullblock

## Finalize the backup if it completed or else it leaves a file without the 
## appropriate extension behind so it can be found and deleted later
mv "$OFILE" "$OFILEFINAL"
echo "RaspberryPI backup process completed!"
echo "The Backup file is: $OFILEFINAL"
ListBackups daily

}



##################################################################
## Make weekly and monthly backups
##################################################################
function WeeklyMonthlyBackups {
  echo ""      
  echo "$FUNCNAME"
  echo ""
  echo "Checking for weekly backups..."
  if [[ -n "$(find $DIR -maxdepth 1 -name '*weekly.img')" ]]; then 
    echo ""
    echo "Weekly backups were found. Checking if a new one is needed..."
## compare the weekly backups older than 7 days against the total weekly backups
    if [[ "$(find $DIR -maxdepth 1 -name "*weekly.img" -mtime +7 | wc -l)" -lt "$(find $DIR -maxdepth 1 -name "*weekly.img" | wc -l)" ]]; then
      echo "None are older than 7 days" 
    else
      echo "Need a new weekly backup.  Making it now..."
      CheckDiskSpace
      pv "$OFILEFINAL" > "$OFILEFINALWEEKLY"	## pv gives the user some feedback
    fi
  else
    echo "No weekly backups found so I am making the first one..."
    CheckDiskSpace
    pv "$OFILEFINAL" > "$OFILEFINALWEEKLY"
  fi

## Remove old weekly backups
PurgeOldBackups weekly

## Make monthly backup
echo ""
echo "Checking for monthly backups..."
if [[ -n "$(find $DIR -maxdepth 1 -name '*monthly.img')" ]]; then 
  echo "Monthly backups were found. Checking if a new one is needed..."
    if [[ "$(find $DIR -maxdepth 1 -name "*monthly.img" -mtime +30 | wc -l)" -lt "$(find $DIR -maxdepth 1 -name "*monthly.img" | wc -l)" ]]; then
      echo "None are older than 30 days.  Not making a new one." 
    else
      echo "Need a new monthly backup.  Making it now..."
      CheckDiskSpace
      pv "$OFILEFINAL" > "$OFILEFINALMONTHLY"  ## pv gives the user some feedback
    fi 
else
  echo "No monthly backups found so I am making the first one..."
  CheckDiskSpace
  pv "$OFILEFINAL" > "$OFILEFINALMONTHLY"
fi
## Remove old monthly backups beyond $KEEPMONTHLY
PurgeOldBackups monthly

}

##################################################################
## PROGRAM START
##################################################################

## Begin the program and keep track of how many seconds it takes...
## From http://stackoverflow.com/questions/16908084/linux-bash-script-to-calculate-time-elapsed
STARTTIME=$(date +%s)

## See if a parameter was passed to do RestoreBackup
if [[ ! -z "$1" ]]; then
  ## A parameter was passed so parse the command line for arguments
	
	## See if there are more than one arguments
	if [[ $# -lt 2 ]]; then
	## Check if the argument passed can be used and suppress the system errors
		FLAGS=:r
		while getopts $FLAGS FLAG
		do
    			case $FLAG in
        		r  )
        			#RestoreBackup
        			echo "RestoreBackup"
        		;;
        		*  )    echo "Missing a valid argument. Quitting."
        			exit 1
        		;;
    			esac
		done
	else
	## More than one argument so try and parse them as well
		FLAGS=:r:
		while getopts $FLAGS FLAG
		do
    			case $FLAG in
        		r  )
        			## Check if the command line includes a delta file to 
        			## use and pass it to the RestoreBackup function
        			echo "RestoreBackup $OPTARG"
        		;;
        		*  )    echo "Missing a valid argument. Quitting."
        		;;
    			esac
		done	
	fi

	
## If no arguments were passed, run the script as normal
else
  InitialSetup
  DeclaredServices stop
  WriteBackupToDisk
  DeclaredServices start
  ## Remove old daily backups beyond $KEEPDAILY
  PurgeOldBackups daily
  WeeklyMonthlyBackups
  MakeIncrementalBackup
fi

##Figure out how many minutes the backup took...
ENDTIME=$(date +%s)
ELAPSEDTIME=$((ENDTIME - STARTTIME))
echo "It took $((ELAPSEDTIME / 60)) minutes to complete this backup!"
##################################################################
## PROGRAM END
##################################################################
