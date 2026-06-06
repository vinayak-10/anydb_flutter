#!/bin/bash

flutter build web --release --dart-define-from-file=secrets.json --wasm

firebase deploy --only hosting
