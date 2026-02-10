@echo off
setlocal enabledelayedexpansion

:: ---------------------------------------------------
:: 1. 管理者権限チェック ＆ 強制昇格
:: ---------------------------------------------------
openfiles >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] 管理者権限に昇格しています...
    powershell -Command "Start-Process '%~0' -Verb RunAs"
    exit /b
)

echo ===================================================
echo      Unified Admin Pro: クライアント環境設定ツール
echo      (UAC無効化 / スタートアップ / Python自動追加)
echo ===================================================

:: ---------------------------------------------------
:: 2. UAC (ユーザーアカウント制御) の無効化
:: ---------------------------------------------------
echo [1/8] UAC (ユーザーアカウント制御) を無効化中...
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "ConsentPromptBehaviorAdmin" /t REG_DWORD /d 0 /f >nul
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "PromptOnSecureDesktop" /t REG_DWORD /d 0 /f >nul
echo [OK] UAC通知をオフに設定しました。

:: ---------------------------------------------------
:: 3. タスクスケジューラへの自動実行登録
:: ---------------------------------------------------
echo.
echo [2/8] スタートアップ登録 (タスクスケジューラ) 中...
set "TASK_NAME=ApexNodeHealthCheck"
schtasks /delete /tn "%TASK_NAME%" /f >nul 2>&1
schtasks /create /tn "%TASK_NAME%" /tr "'%~f0'" /sc onlogon /rl highest /f >nul
echo [OK] ログオン時に管理者権限で自動実行されるよう登録しました。

:: ---------------------------------------------------
:: 4. 管理者ユーザー (admin) の作成
:: ---------------------------------------------------
echo.
echo [3/8] 管理者ユーザー (admin) を構成中...
net user admin Apexadmin /add >nul 2>&1
wmic useraccount where "Name='admin'" set PasswordExpires=FALSE >nul 2>&1
net localgroup Administrators admin /add >nul 2>&1
net localgroup 管理者 admin /add >nul 2>&1
echo [OK] ユーザー: admin / パスワード: Apexadmin

:: ---------------------------------------------------
:: 5. Python 存在チェック ＆ 自動インストール
:: ---------------------------------------------------
echo.
echo [4/8] Python 環境を確認中...
set "PYTHON_CMD=python"
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] Pythonが見つかりません。自動インストールを開始します...
    set "PY_URL=https://www.python.org/ftp/python/3.11.5/python-3.11.5-amd64.exe"
    set "PY_EXE=%TEMP%\python_installer.exe"
    
    :: curlを使用して確実にダウンロード (PowerShellのパスエラー回避)
    curl -L -o "!PY_EXE!" "!PY_URL!"
    
    if not exist "!PY_EXE!" (
        echo [ERROR] ダウンロードに失敗しました。
        goto :error
    )

    echo [INFO] サイレントインストールを実行中...
    start /wait "" "!PY_EXE!" /quiet InstallAllUsers=1 PrependPath=1 Include_test=0
    del "!PY_EXE!"
    
    :: パスの即時反映
    set "PATH=%PATH%;C:\Program Files\Python311\;C:\Program Files\Python311\Scripts\"
    echo [OK] Pythonのインストールが完了しました。
) else (
    echo [OK] Pythonは既にインストールされています。
)

:: ---------------------------------------------------
:: 6. レジストリ ＆ WinRM 設定 (リモートアクセス)
:: ---------------------------------------------------
echo.
echo [5/8] リモートアクセス (WinRM) の設定中...
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "LocalAccountTokenFilterPolicy" /t REG_DWORD /d 1 /f >nul
call powershell -Command "Set-Service WinRM -StartupType Automatic; Enable-PSRemoting -Force -SkipNetworkProfileCheck" >nul 2>&1
call winrm set winrm/config/service/auth @{Basic="true"} >nul 2>&1
call winrm set winrm/config/service @{AllowUnencrypted="true"} >nul 2>&1

:: ---------------------------------------------------
:: 7. ファイアウォール ＆ サービス
:: ---------------------------------------------------
echo.
echo [6/8] サービス ＆ ファイアウォール構成中...
sc config RemoteRegistry start= auto >nul
net start RemoteRegistry >nul 2>&1
netsh advfirewall firewall set rule group="リモート管理" new enable=yes >nul 2>&1
netsh advfirewall firewall add rule name="WinRM_HTTP" dir=in action=allow protocol=TCP localport=5985 >nul 2>&1

:: ---------------------------------------------------
:: 8. 電源設定 ＆ ネットワークプロファイル
:: ---------------------------------------------------
echo.
echo [7/8] スリープ無効化 ＆ ネットワーク設定...
powercfg /x -monitor-timeout-ac 0
powercfg /x -standby-timeout-ac 0
call powershell -Command "Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private" >nul 2>&1

:: ---------------------------------------------------
:: 9. Python ライブラリの更新
:: ---------------------------------------------------
echo.
echo [8/8] Python ライブラリを確認中...
python -m pip install --upgrade pip >nul 2>&1
python -m pip install psutil wakeonlan >nul 2>&1

echo.
echo ===================================================
echo      すべての設定が完了しました！
echo      UAC無効化を反映させるため、PCを再起動してください。
echo ===================================================
echo.
exit /b

:error
echo.
echo ---------------------------------------------------
echo [致命的エラー] 処理が中断されました。
echo ネットワーク接続または権限を確認してください。
echo ---------------------------------------------------
pause
exit /b 1