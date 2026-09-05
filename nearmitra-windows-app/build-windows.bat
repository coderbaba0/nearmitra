@echo off
set GOOS=windows
set GOARCH=amd64
go build -ldflags="-H windowsgui -s -w" -o NearMitra.exe .
