rpibackup
=========
This is my attempt to prevent what happened to me not long ago: losing all the data on my Raspberry Pi's SD Card and having to start over.

Function
--------
I chose to DD the entire SD Card to an IMG file over rsync because I wanted to make restoring an SD Card as easy as possible.

It makes a daily backup when it is run, looks for a weekly backup and if it finds one that is over seven days old or doesn't find one, copies this daily backup to a weekly backup, then repeats the same process for a monthly backup using 30 days as the increment.

It will then use the most recent weekly backup to make an incremental backup between the just-made daily and that weekly.  This reduces the size of the daily backups from 16GB (the size of my SD cards) to 10-50 MB (depending on how much of my system I've changed in the week).  

I thought about using rsynch to keep browsable versions of my file system, but my main goal is to be able to DD a backup to a new SD card a quickly get running again.  The incremental backup can be turned off if you choose as it does add about 30 minutes to the backup and restore process-making it about an hour total for backups and about the same for restores.

Future
------
At this point the script works well enough for normal use, but there a few changes to make in the future:
* Make the restore backup more intuitive and work better
* Clean the code overall for readability and consistancy
* Work out some of the logic problems in the script (e.g., the making of an incremental backup if the weekly backup is brand new)
