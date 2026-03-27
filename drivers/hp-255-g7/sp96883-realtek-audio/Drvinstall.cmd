@echo off
SETLOCAL ENABLEDELAYEDEXPANSION

for /f "tokens=1,2,3,4,5 delims=&\" %%a in ('wmic path Win32_PnPEntity get PNPDeviceID') do (
	if "[%%a]"=="[HDAUDIO]" if "[%%b]"=="[FUNC_01]" if "[%%c]"=="[VEN_10EC]" if "[%%d]"=="[DEV_0236]" set "sub=%%e" & set ssid=!sub:~-4!
)
for %%s IN (84AC 84AD 84AE 84AF) DO (
	if !ssid!==%%s (
		echo SSID is !ssid!
		cd RTK_SR_SYN
		"Setup.exe" /s /z[-rpC:\system.sav\logs\RHDSetup.log]
		echo The driver install successfully.
		GOTO FINISH
	)
)

for %%s IN (867F 867E) DO (
	if !ssid!==%%s (
		echo SSID is !ssid!
		cd RTK_SR
		"Setup.exe" /s /z[-rpC:\system.sav\logs\RHDSetup.log]
		echo The driver install successfully.
		GOTO FINISH
	)
)

:FINISH
exit /b 0 
