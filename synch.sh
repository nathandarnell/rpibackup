#!bin/bash
## Saves me a few keystrokes
if [ $# -lt 2 ]
then
        echo "Usage : $0 [COMMAND] [BRANCH]"
        echo "Commands:"
        echo "s - synch with GitHub and change file permissions"
        echo "r - run rpibackup.sh"
        echo "a - synch with GitHub, change file permissions, and run rpibackup.sh"
        exit
fi
      
case "$1" in
      s)
            echo "Synching with GitHub..."
            echo ""
            git reset --hard
            git pull origin "$2"
            chmod +x rpibackup.sh synch.sh
      ;;
      r)
            ./rpibackup.sh
            echo "The Weekly backups are:"
            echo ""
            find "$DIR" -maxdepth 1 -name '*weekly.img' | sort
      ;;
      a)
            s
            r
      ;;
      *)
        echo "Usage : $0 [COMMAND] [BRANCH]"
        echo "Commands:"
        echo "s - synch with GitHub and change file permissions"
        echo "r - run rpibackup.sh"
        echo "a - synch with GitHub, change file permissions, and run rpibackup.sh"
        exit
      ;;
esac

