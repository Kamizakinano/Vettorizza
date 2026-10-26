@echo off
REM Avvia Vettorizza dal codice sorgente (senza creare l'eseguibile)
cd /d "%~dp0"
if not exist .venv (
    py -3 -m venv .venv || python -m venv .venv
    call .venv\Scripts\activate.bat
    pip install -r requirements.txt
) else (
    call .venv\Scripts\activate.bat
)
start "" pythonw -m vettorizza
