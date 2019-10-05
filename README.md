# PS_SharpSVN
SharpSVN based PowerShell Code for automated repository installation, updation and self-updation for Windows


============      AUTOMATED REPOSITORY INSTALLATION AND UPDATION TOOL    ====================

The tool provides a binary distribution for repository checkup and update.
It sets up a pre-configured complete environment with convenient startup options.

Features : 
1. Automated checkout and update feature
2. Working directory check
3. Cleans up the directory in case working directory requires clean up or repo is locked.
4. Automated check for this tool update in repository and replacing.

Base - PowerShell
Dependancy : SharpSVN.dll

=========== USER'S GUIDE =======

For first time:
Create a new folder where the repositories are needed to be checked out.
Put 'Installer' exe inside the folder. Run
If required, the popup will ask for the Authentication. 

To remove any folder from getting new updates, configure the settings.txt file
Under section 'Exclude:', mention the name of folder to be excluded from update. 

========== DEVELOPER'S GUIDE ===

source code is present in .ps1 files.
Functions list :
1. Get-Folder
2. Download-File
3. Cond-Create-Folder
4. summary_notify
5. Update-Folder
6. check_folder
7. Checkout-Folder
8. Delete_prev

Ps1 To Exe to convert .ps1 scripts to EXE 
