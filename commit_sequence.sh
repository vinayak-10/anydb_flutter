#!/bin/bash

read -p "Commit message: " MSG

git add . && git commit -m "$MSG"
git push && git push local-server dev

git checkout master && git merge dev
git push && git push local-server master

git checkout dev
