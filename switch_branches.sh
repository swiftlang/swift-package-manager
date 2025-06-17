#!/bin/bash

checkout() {
  echo "Checking out $1"
  git reset --hard $1
}

{
  export SLEEP_TIME=2

  while :
  do
    checkout origin/main
    sleep $SLEEP_TIME

    checkout f0a5106f3449c22ec27df3776b819d039de5877d
    sleep $SLEEP_TIME
  done
}
