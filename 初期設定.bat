@echo off
setlocal enabledelayedexpansion

:: ---------------------------------------------------
:: 1. 管理者権限チェック ＆ 強制昇格
:: ---------------------------------------------------
openfiles >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] 管理者権限に昇格しています...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: カレントディレクトリを実行ファイルの場所に固定
cd /d "%~dp0"

echo ===================================================
echo      Unified Admin Pro: クライアント環境設定ツール
echo ===================================================

:: ---------------------------------------------------
:: 2. UAC (ユーザーアカウント制御) の無効化
:: ---------------------------------------------------
echo [1/8] UAC を無効化中...
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "ConsentPromptBehaviorAdmin" /t REG_DWORD /d 0 /f >nul
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "PromptOnSecureDesktop" /t REG_DWORD /d 0 /f >nul

:: ---------------------------------------------------
:: 3. タスクスケジューラへの自動実行登録
:: ---------------------------------------------------
echo [2/8] スタートアップ登録中...
set "TASK_NAME=ApexNodeHealthCheck"
schtasks /delete /tn "%TASK_NAME%" /f >nul 2>&1
schtasks /create /tn "%TASK_NAME%" /tr "'%~f0'" /sc onlogon /rl highest /f >nul

:: ---------------------------------------------------
:: 4. 管理者ユーザー (admin) の作成
:: ---------------------------------------------------
echo [3/8] 管理者ユーザー (admin) を構成中...
net user admin Apexadmin /add >nul 2>&1
net localgroup Administrators admin /add >nul 2>&1
net localgroup 管理者 admin /add >nul 2>&1

:: ---------------------------------------------------
:: 5. Python インストール (存在しない場合のみ)
:: ---------------------------------------------------
echo [4/8] Python 環境を確認中...
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] Pythonが見つかりません。自動インストールを開始します...
    set "PY_URL=https://www.python.org/ftp/python/3.11.5/python-3.11.5-amd64.exe"
    set "PY_EXE=%TEMP%\python_installer.exe"
    curl -L -o "!PY_EXE!" "!PY_URL!"
    
    echo [INFO] インストール実行中...
    start /wait "" "!PY_EXE!" /quiet InstallAllUsers=1 PrependPath=1 Include_test=0
    del "!PY_EXE!"
    
    :: インストール直後のパス反映
    set "PATH=%PATH%;C:\Program Files\Python311\;C:\Program Files\Python311\Scripts\"
)

:: ---------------------------------------------------
:: 6. リモートアクセス (WinRM) 設定
:: ---------------------------------------------------
echo [5/8] リモートアクセス設定中...
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "LocalAccountTokenFilterPolicy" /t REG_DWORD /d 1 /f >nul
powershell -Command "Set-Service WinRM -StartupType Automatic; Enable-PSRemoting -Force -SkipNetworkProfileCheck" >nul 2>&1

:: ---------------------------------------------------
:: 7. ファイアウォール ＆ サービス
:: ---------------------------------------------------
echo [6/8] サービス ＆ ファイアウォール構成中...
sc config RemoteRegistry start= auto >nul
net start RemoteRegistry >nul 2>&1
netsh advfirewall firewall add rule name="WinRM_HTTP" dir=in action=allow protocol=TCP localport=5985 >nul 2>&1

:: ---------------------------------------------------
:: 8. 電源設定 ＆ ネットワーク
:: ---------------------------------------------------
echo [7/8] スリープ無効化...
powercfg /x -monitor-timeout-ac 0
powercfg /x -standby-timeout-ac 0
powershell -Command "Set-NetConnectionProfile -NetworkCategory Private" >nul 2>&1

:: ---------------------------------------------------
:: 9. ライブラリインストール
:: ---------------------------------------------------
echo [8/8] Python ライブラリ更新中...
:: パスが通っていない可能性を考慮しフルパスで試行
"C:\Program Files\Python311\python.exe" -m pip install --upgrade pip >nul 2>&1
"C:\Program Files\Python311\python.exe" -m pip install psutil wakeonlan >nul 2>&1

echo ===================================================
echo   完了しました。再起動後に設定が完全に反映されます。
echo ===================================================
pause
exit /b