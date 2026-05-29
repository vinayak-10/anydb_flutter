; anydb Windows Desktop Installer Compilation Script
; Target Platform: Windows 10/11 x64 (64-bit)
; Packaging System: NSIS (Nullsoft Scriptable Install System)

!include "MUI2.nsh"
!include "x64.nsh"

; =============================================================================
; 1. Application & Version Definitions
; =============================================================================
!define APP_NAME "anydb"
!define APP_PUBLISHER "anydb"
!define APP_VERSION "1.0.0"
!define APP_EXE "anydb_flutter.exe"

; Relative path to build bundle output directory from workspace folder
!define BUNDLE_DIR "..\build_win\runner"

Name "${APP_NAME}"
OutFile "..\build_win\${APP_NAME}_installer_x64.exe"
InstallDir "$PROGRAMFILES64\${APP_NAME}"
InstallDirRegKey HKLM "Software\${APP_NAME}" "InstallDir"

RequestExecutionLevel admin

; =============================================================================
; 2. MUI Appearance Configurations
; =============================================================================
!define MUI_ABORTWARNING

; Enforce premium installer branding and visual style
!define MUI_ICON "runner\resources\app_icon.ico"
!define MUI_UNICON "${NSISDIR}\Contrib\Graphics\Icons\modern-uninstall.ico"

!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_BITMAP "${NSISDIR}\Contrib\Graphics\Header\nsis3-metro.bmp"
!define MUI_WELCOMEFINISHPAGE_BITMAP "${NSISDIR}\Contrib\Graphics\Wizard\nsis3-metro.bmp"

; =============================================================================
; 3. Installer Dialog Pages
; =============================================================================
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES

; Finish page allows user to launch the application immediately
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Launch anydb now"
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

; =============================================================================
; 4. Installation Script Section
; =============================================================================
Section "Install"
  ; Enforce 64-bit OS compatibility
  ${If} ${RunningX64}
    DetailPrint "Enforcing 64-bit OS environment requirements... Passed."
  ${Else}
    MessageBox MB_OK|MB_ICONSTOP "This application requires a 64-bit Windows Operating System. Installation aborted."
    Abort
  ${EndIf}

  ; Set output path to installation directory
  SetOutPath "$INSTDIR"

  ; Pack compiled runner executable
  File "${BUNDLE_DIR}\${APP_EXE}"

  ; Pack core Flutter engine and natively compiled plugin libraries
  File "${BUNDLE_DIR}\flutter_windows.dll"
  File "${BUNDLE_DIR}\share_plus_plugin.dll"
  File "${BUNDLE_DIR}\sqlite3.dll"
  File "${BUNDLE_DIR}\sqlite3_flutter_libs_plugin.dll"
  File "${BUNDLE_DIR}\url_launcher_windows_plugin.dll"

  ; Pack full asset tree recursively (fonts, icons, shaders, compiled Dart kernel)
  SetOutPath "$INSTDIR\data"
  File /r "${BUNDLE_DIR}\data\*"

  ; Restore active directory to installation root
  SetOutPath "$INSTDIR"

  ; Write registration entries for Windows "Apps & Features" Add/Remove menu
  WriteRegStr HKLM "Software\${APP_NAME}" "InstallDir" "$INSTDIR"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "DisplayIcon" '"$INSTDIR\${APP_EXE}"'
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "Publisher" "${APP_PUBLISHER}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "DisplayVersion" "${APP_VERSION}"
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "NoRepair" 1

  ; Generate the uninstaller binary
  WriteUninstaller "$INSTDIR\uninstall.exe"

  ; Create system shortcuts
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\Uninstall.lnk" "$INSTDIR\uninstall.exe" "" "$INSTDIR\uninstall.exe" 0
  CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0
SectionEnd

; =============================================================================
; 5. Uninstallation Script Section
; =============================================================================
Section "Uninstall"
  ; Remove Desktop and Start Menu Shortcuts
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\Uninstall.lnk"
  RMDir "$SMPROGRAMS\${APP_NAME}"
  Delete "$DESKTOP\${APP_NAME}.lnk"

  ; Remove program binaries and libraries
  Delete "$INSTDIR\${APP_EXE}"
  Delete "$INSTDIR\flutter_windows.dll"
  Delete "$INSTDIR\share_plus_plugin.dll"
  Delete "$INSTDIR\sqlite3.dll"
  Delete "$INSTDIR\sqlite3_flutter_libs_plugin.dll"
  Delete "$INSTDIR\url_launcher_windows_plugin.dll"
  Delete "$INSTDIR\uninstall.exe"

  ; Remove full asset directories recursively
  RMDir /r "$INSTDIR\data"
  RMDir "$INSTDIR"

  ; Clear uninstallation registry credentials
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}"
  DeleteRegKey HKLM "Software\${APP_NAME}"
SectionEnd
