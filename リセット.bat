@echo off
setlocal enabledelayedexpansion

:: 1. 管理者権限チェック
openfiles >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

echo ===================================================
echo      環境リセットツール (Pythonは削除しません)
echo ===================================================

:: 2. UAC の復元
echo [1/6] UAC を有効に戻しています...
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "ConsentPromptBehaviorAdmin" /t REG_DWORD /d 5 /f >nul
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "PromptOnSecureDesktop" /t REG_DWORD /d 1 /f >nul

:: 3. タスク削除
echo [2/6] 自動実行タスクを削除中...
schtasks /delete /tn "ApexNodeHealthCheck" /f >nul 2>&1

:: 4. ユーザー削除
echo [3/6] 管理者ユーザー (admin) を削除中...
net user admin /delete >nul 2>&1

:: 5. リモート設定解除
echo [4/6] リモート管理設定を解除中...
reg delete "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "LocalAccountTokenFilterPolicy" /f >nul 2>&1
powershell -Command "Disable-PSRemoting -Force; Stop-Service WinRM; Set-Service WinRM -StartupType Disabled" >nul 2>&1
netsh advfirewall firewall delete rule name="WinRM_HTTP" >nul 2>&1

:: 6. 電源設定リセット
echo [5/6] 電源設定をデフォルトに復元中...
powercfg /restoredefaultschemes >nul

echo [6/6] 設定のクリーンアップ完了。
echo ===================================================
echo   リセット完了。再起動を推奨します。
echo ===================================================
pause
exit /b