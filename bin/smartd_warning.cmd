@echo off
::
:: smartd warning script
::
:: Home page of code is: http://www.smartmontools.org
::
:: Copyright (C) 2012-22 Christian Franke
::
:: SPDX-License-Identifier: GPL-2.0-or-later
::
:: $Id: smartd_warning.cmd 5428 2022-12-31 15:55:43Z chrfranke $
::

verify other 2>nul
setlocal enableextensions enabledelayedexpansion
if errorlevel 1 goto UNSUPPORTED
set err=

:: Change to script directory (not necessary if run from smartd service)
cd /d %~dp0
if errorlevel 1 goto ERROR

:: Detect accidental use of '-M exec /path/to/smartd_warning.cmd'
if not "!SMARTD_SUBJECT!" == "" (
  echo smartd_warning.cmd: SMARTD_SUBJECT is already set - possible recursion
  goto ERROR
)

:: Parse options
set dryrun=
if "%1" == "--dryrun" (
  set dryrun=--dryrun
  shift
)
if not "!dryrun!" == "" echo cd /d !cd!

if not "%1" == "" (
  echo smartd warning message script
  echo.
  echo Usage:
  echo set SMARTD_MAILER='Path to external script, empty for "blat"'
  echo set SMARTD_ADDRESS='Space separated mail addresses, empty if none'
  echo set SMARTD_MESSAGE='Error Message'
  echo set SMARTD_FAILTYPE='Type of failure, "EMailTest" for tests'
  echo set SMARTD_TFIRST='Date of first message sent, empty if none'
  echo :: set SMARTD_TFIRSTEPOCH='time_t format of above'
  echo set SMARTD_PREVCNT='Number of previous messages, 0 if none'
  echo set SMARTD_NEXTDAYS='Number of days until next message, empty if none'
  echo set SMARTD_DEVICEINFO='Device identify information'
  echo :: set SMARTD_DEVICE='Device name'
  echo :: set SMARTD_DEVICESTRING='Annotated device name'
  echo :: set SMARTD_DEVICETYPE='Device type from -d directive, "auto" if none'

  echo smartd_warning.cmd [--dryrun]
  goto ERROR
)

if "!SMARTD_ADDRESS!!SMARTD_MAILER!" == "" (
  echo smartd_warning.cmd: SMARTD_ADDRESS or SMARTD_MAILER must be set
  goto ERROR
)

:: USERDNSDOMAIN may be unset if running as service
if "!USERDNSDOMAIN!" == "" (
  for /f "delims== tokens=2 usebackq" %%d in (`wmic PATH Win32_Computersystem WHERE "PartOfDomain=TRUE" GET Domain /VALUE ^<nul 2^>nul`) do set USERDNSDOMAIN=%%~d
)
:: Remove possible trailing \r appended by above command (requires %...%)
set USERDNSDOMAIN=%USERDNSDOMAIN%

:: Format subject
set SMARTD_SUBJECT=SMART error (!SMARTD_FAILTYPE!) detected on host: !COMPUTERNAME!

:: Temp file for message
if not "!TMP!" == "" set SMARTD_FULLMSGFILE=!TMP!\smartd_warning-!RANDOM!.txt
if     "!TMP!" == "" set SMARTD_FULLMSGFILE=smartd_warning-!RANDOM!.txt

:: Format message
(
  echo This message was generated by the smartd service running on:
  echo.
  echo.   host name:  !COMPUTERNAME!
  if not "!USERDNSDOMAIN!" == "" echo.   DNS domain: !USERDNSDOMAIN!
  if     "!USERDNSDOMAIN!" == "" echo.   DNS domain: [Empty]
  if not "!USERDOMAIN!"    == "" echo.   Win domain: !USERDOMAIN!
  echo.
  echo The following warning/error was logged by the smartd service:
  echo.
  if not "!SMARTD_MESSAGE!" == "" echo !SMARTD_MESSAGE!
  if     "!SMARTD_MESSAGE!" == "" echo [SMARTD_MESSAGE]
  echo.
  echo Device info:
  if not "!SMARTD_DEVICEINFO!" == "" echo !SMARTD_DEVICEINFO!
  if     "!SMARTD_DEVICEINFO!" == "" echo [SMARTD_DEVICEINFO]
  echo.
  echo For details see the event log or log file of smartd.
  if not "!SMARTD_FAILTYPE!" == "EmailTest" (
    echo.
    echo You can also use the smartctl utility for further investigation.
    if not "!SMARTD_PREVCNT!" == "0" echo The original message about this issue was sent at !SMARTD_TFIRST!
    if "!SMARTD_NEXTDAYS!" == "" (
      echo No additional messages about this problem will be sent.
    ) else ( if "!SMARTD_NEXTDAYS!" == "0" (
      echo Another message will be sent upon next check if the problem persists.
    ) else ( if "!SMARTD_NEXTDAYS!" == "1" (
      echo Another message will be sent in 24 hours if the problem persists.
    ) else (
      echo Another message will be sent in !SMARTD_NEXTDAYS! days if the problem persists.
    )))
  )
) > "!SMARTD_FULLMSGFILE!"
if errorlevel 1 goto ERROR

if not "!dryrun!" == "" (
  echo !SMARTD_FULLMSGFILE!:
  type "!SMARTD_FULLMSGFILE!"
  echo --EOF--
)

:: Check first address
set first=
for /f "tokens=1*" %%a in ("!SMARTD_ADDRESS!") do (set first=%%a)
set wtssend=
if "!first!" == "console"   set wtssend=-c
if "!first!" == "active"    set wtssend=-a
if "!first!" == "connected" set wtssend=-s

if not "!wtssend!" == "" (
  :: Show Message box(es) via WTSSendMessage()
  if not "!dryrun!" == "" (
    echo call .\wtssendmsg !wtssend! "!SMARTD_SUBJECT!" - ^< "!SMARTD_FULLMSGFILE!"
  ) else (
    call .\wtssendmsg !wtssend! "!SMARTD_SUBJECT!" - < "!SMARTD_FULLMSGFILE!"
    if errorlevel 1 set err=t
  )
  :: Remove first address
  for /f "tokens=1*" %%a in ("!SMARTD_ADDRESS!") do (set SMARTD_ADDRESS=%%b)
)

:: Make comma separated address list
set SMARTD_ADDRCSV=
if not "!SMARTD_ADDRESS!" == "" set SMARTD_ADDRCSV=!SMARTD_ADDRESS: =,!

:: Default mailer is smartd_mailer.ps1 (if configured) or blat.exe
if not "!SMARTD_ADDRESS!" == "" if "!SMARTD_MAILER!" == "" (
  if not exist smartd_mailer.conf.ps1 set SMARTD_MAILER=blat
)

:: Get mailer extension
set ext=
for /f "delims=" %%f in ("!SMARTD_MAILER!") do (set ext=%%~xf)

:: Send mail or run command
if "!ext!" == ".ps1" (

  :: Run PowerShell script
  if not "!dryrun!" == "" (
    set esc=^^
    echo PowerShell -NoProfile -ExecutionPolicy Bypass -Command !esc!^& '!SMARTD_MAILER!' ^<nul
  ) else (
    PowerShell -NoProfile -ExecutionPolicy Bypass -Command ^& '!SMARTD_MAILER!' <nul
    if errorlevel 1 set err=t
  )

) else ( if not "!SMARTD_ADDRCSV!" == "" (

  :: Send mail
  if "!SMARTD_MAILER!" == "" (

    :: Use smartd_mailer.ps1
    if not "!dryrun!" == "" (
      echo PowerShell -NoProfile -ExecutionPolicy Bypass -Command .\smartd_mailer.ps1 ^<nul
      echo ==========
    )
    PowerShell -NoProfile -ExecutionPolicy Bypass -Command .\smartd_mailer.ps1 !dryrun! <nul
    if errorlevel 1 set err=t
    if not "!dryrun!" == "" echo ==========

  ) else (

    :: Use blat mailer or compatible
    if not "!dryrun!" == "" (
      echo call "!SMARTD_MAILER!" - -q -subject "!SMARTD_SUBJECT!" -to "!SMARTD_ADDRCSV!" ^< "!SMARTD_FULLMSGFILE!"
    ) else (
      call "!SMARTD_MAILER!" - -q -subject "!SMARTD_SUBJECT!" -to "!SMARTD_ADDRCSV!" < "!SMARTD_FULLMSGFILE!"
      if errorlevel 1 set err=t
    )

  )

) else ( if not "!SMARTD_MAILER!" == "" (

  :: Run command
  if not "!dryrun!" == "" (
    echo call "!SMARTD_MAILER!" ^<nul
  ) else (
    call "!SMARTD_MAILER!" <nul
    if errorlevel 1 set err=t
  )

)))

del "!SMARTD_FULLMSGFILE!" >nul 2>nul

if not "!err!" == "" goto ERROR
endlocal
exit /b 0

:ERROR
endlocal
exit /b 1
