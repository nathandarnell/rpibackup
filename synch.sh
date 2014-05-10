#!/bin/bash
## Saves me a few keystrokes
function Synch {
            echo "Synching with GitHub..."
            echo ""
            git reset --hard
            git pull origin "$2"
            chmod +x rpibackup.sh synch.sh
  }

function Run {
            echo "Running the backup..."
            echo ""
            ./rpibackup.sh
  }

function Error {
                echo "Usage : $0 [COMMAND] [BRANCH]"
                echo "Commands:"
                echo "s - synch with GitHub and change file permissions"
                echo "r - run rpibackup.sh"
                echo "a - synch with GitHub, change file permissions, and run rpibackup.sh"
                exit
  }

        if [ ! $# -eq 2 ] && [ ! "$1" == r ]
        then
          Error
        fi

case "$1" in
      s)
        Synch "$@"
      ;;
      r)
        Run
      ;;
      a)
        Synch "$@"
        Run
      ;;
      *)
        Error
      ;;
esac

