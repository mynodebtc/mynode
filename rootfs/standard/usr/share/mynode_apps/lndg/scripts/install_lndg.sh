#!/bin/bash
set -x
set -e


# Helpful variables to add:
#   VERSION?
#   DOWNLOAD PATH TO TAR.GZ?
#   PATH TO SD CARD FOLDER
#   PATH TO DATA DRIVE FOLDER
#

echo "INSTALLING LNDG SCRIPT - START"

echo "====== User Info ======"
whoami
id

echo "====== ENV DATA ======"
env

echo "====== CURRENT FOLDER DATA ======"
pwd
ls -lsa


echo "====== SLEEPING A BIT ======"
sleep 3s


echo "INSTALLING LNDG SCRIPT - END"