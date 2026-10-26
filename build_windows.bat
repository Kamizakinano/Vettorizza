@echo off
REM Crea dist\Vettorizza\Vettorizza.exe (serve Python 3.10+ installato da python.org)
setlocal
cd /d "%~dp0"
if not exist .venv (
    py -3 -m venv .venv || python -m venv .venv || goto :error
)
call .venv\Scripts\activate.bat || goto :error
python -m pip install --upgrade pip || goto :error
pip install -r requirements-dev.txt || goto :error
python -m pytest -q || goto :error
pyinstaller --noconfirm Vettorizza.spec || goto :error
echo.
echo Fatto! Il programma e' in: dist\Vettorizza\Vettorizza.exe
pause
exit /b 0
:error
echo.
echo Si e' verificato un errore durante la creazione del programma.
pause
exit /b 1
