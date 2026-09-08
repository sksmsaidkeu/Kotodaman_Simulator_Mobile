@echo off
robocopy "android\app" "D:\backup\kotodaman-mobile-keystore" kotodaman-release-key.jks
robocopy "android" "D:\backup\kotodaman-mobile-keystore" key.properties
