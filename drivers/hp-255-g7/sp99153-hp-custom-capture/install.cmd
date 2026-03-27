If "%log%"=="" set log=c:\system.sav\logs\CEPS
If Exist %FCC_LOG_FOLDER% set log=%FCC_LOG_FOLDER%
If NOT Exist %log% md %log%
SET MY_LOG=%log%\Fusiondriver.log
SET CMDLog=%log%\cmdline.txt
SET errflg=0

SET block=%~dp0

echo %cd% >> "%MY_LOG%"
echo.>> "%MY_LOG%"
pushd "%block%"
echo %cd% >> "%MY_LOG%"
echo.>> "%MY_LOG%"

@echo %date% %time%  ******************** >> "%MY_LOG%"
@echo %date% %time%    HSA Fusion Driver  >> "%MY_LOG%"
@echo %date% %time%  ******************** >> "%MY_LOG%"
echo.>> "%MY_LOG%"
@echo %date% %time%  Running %0 from "%block%" >> "%MY_LOG%"
echo.>> "%MY_LOG%"

:Install_INF

PNPUTIL.exe /add-driver hpcustomcapdriver.inf /install >> "%MY_LOG%" 2>&1
@echo %date% %time%  hpcustomcapdriver install result : Error Level "%errorlevel%"  Error Flag "%errflg%" >> "%MY_LOG%"
If %Errorlevel% NEQ 0 (set errflg=%Errorlevel%)
@echo %date% %time%  BASE - ErrorLevel "%errorlevel%"  Error Flag "%errflg%" >> "%MY_LOG%"
If %errflg% EQU 259 (set errflg=0)
@echo %date% %time%  BASE - ErrorLevel "%errorlevel%  Error Flag "%errflg%" >> "%MY_LOG%"

If Exist %FCC_LOG_FOLDER% @echo PNPUTIL.exe /add-driver hpcustomcapdriver.inf /install >> "%CMDLog%"
echo.>> "%MY_LOG%"

@echo %date% %time%  END - Error Level %errorlevel%  Error Flag "%errflg%" >> "%MY_LOG%"

echo.>> "%MY_LOG%"
echo.>> "%MY_LOG%"

:END_OF_SCRIPT

echo %cd% >> "%MY_LOG%"
echo.>> "%MY_LOG%"
popd
echo %cd% >> "%MY_LOG%"
echo.>> "%MY_LOG%"



exit /b %errflg%