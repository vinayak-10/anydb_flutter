#!/bin/bash

rclone copy build/app/outputs/flutter-apk/app-release.apk "gdrive:RKM Indore App/apks/flutter_apk/" --drive-shared-with-me
