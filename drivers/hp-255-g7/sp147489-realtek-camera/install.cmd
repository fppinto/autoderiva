REM ==============================================================
REM         Driver deliverable installation V1.19
REM ==============================================================

@Setlocal EnableExtensions
@ECHO OFF
REM ==============================================================
REM   2019 Copyright Compal Electronics, Inc. All right reserved
REM ==============================================================
REM %Description of deliverable%
SETLOCAL EnableDelayedExpansion
if exist "c:\System.sav\logs" (SET "APP_LOG=c:\system.sav\logs\%~n0.log") else (SET "APP_LOG=%~n0.log")
if defined FCC_LOG_FOLDER (SET "APP_LOG=%FCC_LOG_FOLDER%\%~n0.log")
ECHO+ >> %APP_LOG%
ECHO ############################################################# >> %APP_LOG%
ECHO  [%DATE%]                                                     >> %APP_LOG%
ECHO  [%TIME%] Beginning of the %~nx0                              >> %APP_LOG%
ECHO ############################################################# >> %APP_LOG%

REM ------------------- Script Entry ------------------------
:INSTALL_Driver
set list[0]=%0
set list[1]=%1
set list[2]=%2
set list[3]=%3
set list[4]=%4
set list[5]=%5
set list[6]=%6
set list[7]=%7
set list[8]=%8
set list[9]=%9

set flg=0
set ER=
set n=1
set arg=*.inf
set appxArg=
set appxP=0
set appxCommand=
set appxCommandP=
set appxCommandL=
set appxCommandD=
set ppkgArg=
set ppkgCommand=
set ppkgCommandP=

For /d %%i in ("%~dp0*") DO ( 
	set val=0
	For /L %%j IN (!n!,1,!n!) DO (
		set temp=!list[%%j]:~0,6!
		if /I !temp!==/ppkg: (
			for /f "tokens=2 delims=:" %%k in ("!list[%%j]!") do set ppkgArg=%%k
			set ppkgArg=!ppkgArg:~1,-1!
		)		

		if /I !temp!==/appx: (
			for /f "tokens=2 delims=:" %%k in ("!list[%%j]!") do set appxArg=%%k
			set appxArg=!appxArg:~1,-1!
		) else (
			set temp=!list[%%j]:~-4!
			if !temp!==.inf set list[%%j]=!list[%%j]:~0,-4!
			if "!list[%%j]!"=="" ( set arg=*.inf) else ( set arg=!list[%%j]!.inf)
		)
	)

	set tempf=!%%i!
	set tempf=!tempf:~-5!
	set tempf6=!tempf:~-3!
	if /I NOT !tempf!==\APPX ( 
        if /I NOT !tempf!==\PPKG (
			if /I NOT !tempf6!==\F6 (
				if NOT exist "%%i\!arg!" (set arg=*.inf) else (set /a n+=1)

				echo [%TIME%] Pnputil.exe /add-driver "%%i\!arg!" /subdirs /install >> %APP_LOG%
				Pnputil.exe /add-driver "%%i\!arg!" /subdirs /install >status.log
				set ER=!ERRORLEVEL!
				if !ER! == 0 echo ========== %%i INF install success. ERRORLEVEL=!ER! ========== >> %APP_LOG% & set val=1
				if !ER! == 14 echo ========== %%i INF install success. ERRORLEVEL=!ER! ========== >> %APP_LOG% & set val=1
				if !ER! == 3010 echo ========== %%i INF install success. ERRORLEVEL=!ER! ========== >> %APP_LOG% & set val=1
				if !ER! == 259 echo ========== %%i INF Driver package is up-to-date. ERRORLEVEL=!ER! ========== >> %APP_LOG% & set val=1
				if !val!==0 echo ========== %%i INF install failed. ERRORLEVEL=!ER! ========== >> %APP_LOG%
				if !val!==0 ECHO ERRRORLEVEL=!ER! >> status.log & set flg=1
				if !val!==0 ( type status.log >> fail.log ) else ( type status.log >> %APP_LOG% )
				ECHO+ >> %APP_LOG%
			)
		)
	)
)
if !flg!==1 GOTO RESULTFAILED
if NOT "!appxArg!"=="" goto INSTALL_APPX
if NOT "!ppkgArg!"=="" goto INSTALL_PPKG
if "!appxArg!"=="" goto END

:INSTALL_APPX
set val=0
set flg=0
set ER=
for /f "tokens=1,* delims=," %%a in ("!appxArg!") do (
	if !appxP!==0 ( 
		set appxCommandP="%~dp0APPX\%%a"
	) else (
		set appxCommandD=!appxCommandD! /dependencypackagepath:"%~dp0APPX\%%a"
	)
	set appxP=1
	set appxArg=%%b
	if Not "!appxArg!"=="" GOTO INSTALL_APPX	
)

FOR /r "%cd%\APPX" %%j in (*.xml) DO (
	set appxCommandL="%%j"
)

echo [%TIME%] DISM.exe /Online /Add-ProvisionedAppxPackage /PackagePath:!appxCommandP! /Region="All" /LicensePath:!appxCommandL!!appxCommandD! >> %APP_LOG%
DISM.exe /Online /Add-ProvisionedAppxPackage /PackagePath:!appxCommandP! /Region="All" /LicensePath:!appxCommandL!!appxCommandD! >status.log
set ER=!ERRORLEVEL!
if !ER! == 0 echo ========== APPX install success. ERRORLEVEL=!ER! ========== >> %APP_LOG% & set val=1
if !val!==0 echo ========== APPX install failed. ERRORLEVEL=!ER! ========== >> %APP_LOG%
if !val!==0 ECHO ERRRORLEVEL=!ER! >> status.log & set flg=1
if !val!==0 type status.log >> fail.log
ECHO+ >> %APP_LOG%
if !flg!==1 GOTO RESULTFAILED
GOTO END

:INSTALL_PPKG
set val=0
set flg=0
set ER=
for /f "tokens=1,* delims=," %%a in ("!ppkgArg!") do (
		set ppkgCommandP="%~dp0PPKG\%%a"
	if Not "!appxArg!"=="" GOTO INSTALL_PPKG	
)

echo [%TIME%] DISM.exe /Online /Add-ProvisioningPackage /PackagePath:!ppkgCommandP! /Region="All">> %APP_LOG%
DISM.exe /Online /Add-ProvisioningPackage /PackagePath:!ppkgCommandP! /Region="All">status.log
set ER=!ERRORLEVEL!
if !errorlevel! == 0 echo ========== PPKG install success. ERRORLEVEL=!ER! ========== >> %APP_LOG% & set val=1
if !val!==0 echo ========== PPKG install failed. ERRORLEVEL=!ER! ========== >> %APP_LOG%
if !val!==0 ECHO ERRRORLEVEL=!ER! >> status.log & set flg=1
if !val!==0 type status.log >> fail.log
ECHO+ >> %APP_LOG%
if !flg!==1 GOTO RESULTFAILED
GOTO END

:RESULTFAILED
ECHO+ >> %APP_LOG%
ECHO ////////////////////////////////////////////////////////////// >> %APP_LOG%
ECHO //////              DRIVER INSTALL FAIL                 ////// >> %APP_LOG%
ECHO ////////////////////////////////////////////////////////////// >> %APP_LOG%
for /f "delims=" %%j in (fail.log) do echo %%j >>%APP_LOG%
ECHO ////////////////////////////////////////////////////////////// >> %APP_LOG%
del fail.log

:END
del status.log
EXIT /B !ER!
Endlocal

:: Release note
:: v1.10 2018/04/20
:: 1. Delete a blank in log file
::
::
::
::
