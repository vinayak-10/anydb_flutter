#!/bin/bash

flutter clean
flutter pub get
flutter build apk --release --dart-define-from-file=secrets.json
