rpibackup
=========
This is my attempt to prevent wha happened to me a few days ago: losing all the data on my Raspberry Pi's SD Card and having to start over.

I chose to DD the entire SD Card to an IMG file over rsync because I wanted to make restoring an SD Card as easy as possible.

Future
======
I might add some functions to make this do incremental rsync backups as well to make it more useful and robust, but I want to get the main functionality nailed down first.
