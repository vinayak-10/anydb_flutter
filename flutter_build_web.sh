#!/bin/bash

flutter build web --release --dart-define-from-file=secrets.json

firebase deploy --only hosting
