
Function Get-Folder(){
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms")|Out-Null

    $foldername = New-Object System.Windows.Forms.FolderBrowserDialog
    $foldername.Description = "Select a folder (Suggestion: *:\SIM\)"
    $foldername.rootfolder = "MyComputer"

    if($foldername.ShowDialog() -eq "OK")
    {
        $folder += $foldername.SelectedPath
    }
    return $folder
}

function Download-File($svnPath, $localPath){
 # Build SVN URL
 [string]$svnUrl = $svnServer + $svnPath
 $repoUri = New-Object SharpSvn.SvnUriTarget($svnUrl)

 Write-Host "$repoUri..." -ForegroundColor Green -NoNewline

 # create the FileStream and StreamWriter objects
 $fs = New-Object IO.FileStream($localPath, $mode, $access, $sharing)

 $res = $svnClient.Write($repoUri, $fs)

 if ($res -eq "True"){
  Write-Host "Done" -ForegroundColor Green
 }else{
  Write-Warning "Failed"
 }
 $fs.Dispose()
}

Function Cond-Create-Folder($svnLocalPath){
    Write-Host "Creating directory $svnLocalPath" -ForegroundColor Green
try{
	[boolean] $stat = $svnClient.CreateDirectory([string]$svnLocalPath)
	if($stat -eq "False"){
        Write-Host "Diectory Couln't be created"
	}
	else{
		Write-Host "Directory successfully created"
	}
}
catch{ 
	New-Item -ItemType Directory -Force -Path $svnLocalPath | Out-Null
    Write-Host "Directory successfully created"
}
}

function Compare-Hashtable{
     [CmdletBinding()]
    param (
    [Parameter(Mandatory = $true)]
    [Hashtable]$Left,

    [Parameter(Mandatory = $true)]
    [Hashtable]$Right,
    [string[]] $path,
    [boolean] $trackpath = $True
)
#write-host "Path received as: $path"
function New-Result($Path, $LValue, $RValue) {
    New-Object -Type PSObject -Property @{
        path    = $Path -join '\'
#        key     = $key
        lvalue = $LValue
        rvalue = $RValue
#        side   = $Side
    }
}
$flag=0

$Left.Keys | ForEach-Object {
if(!($_ -match 'Comment')){
    $NewPath = $Path + $_
    if ($trackpath ) {
    }

    if ($Left.ContainsKey($_) -and !$Right.ContainsKey($_)) {
        New-Result $NewPath $Left[$_] $Null
        $flag=1
    }
    else {
        if ($Left[$_] -is [hashtable] -and $Right[$_] -is [hashtable] ) {
            Compare-Hashtable $Left[$_] $Right[$_] $NewPath
        }
        else {
            $LValue, $RValue = $Left[$_], $Right[$_]
            if ($LValue -ne $RValue) {
                New-Result $NewPath $LValue $RValue
                $flag=1
            }
         }

    }
    }
}
$Right.Keys | ForEach-Object {
if(!($_ -match 'Comment')){
    $NewPath = $Path + $_
    if (!$Left.ContainsKey($_) -and $Right.ContainsKey($_)) {
        New-Result $NewPath $Null $Right[$_]
        $flag=1
		}
    }
}
if($flag -eq 1){return New-Result}
}

function summary_notify(){
$svnpath = $args[0]
$localDir= $args[1]

[string] $svnServer  = $svnpath
[System.Uri] $svnUri = $svnpath
[System.Uri] $localUri = $localDir
[int]$summary_flag=1
try{
    $status_args = New-Object 'System.Collections.ObjectModel.Collection[SharpSvn.SvnStatusEventArgs ]'
    [boolean] $stat_b=$svnclient.GetStatus([string]$localDir, [ref] $status_args)
    if($status_args.Modified -eq "True"){
		[string]$e=$status_args.ChangeList
        Write-Host "Modified"
    }

    $logItems = New-Object 'System.Collections.ObjectModel.Collection[SharpSvn.SvnLogEventArgs]'
    [boolean] $lstat = $svnClient.GetLog([string]$localDir, [ref]$logItems)
    
	[int] $toRev = $logItems[0].Revision
    $repoFrom = New-Object SharpSvn.SvnUriTarget($svnUri, $clogrev)
    $repoTo = New-Object SharpSvn.SvnUriTarget($svnUri, $toRev)

	$list =  New-Object 'System.Collections.ObjectModel.Collection[SharpSvn.SvnDiffSummaryEventArgs]'       
    [boolean] $dstat= $svnClient.GetDiffSummary($repoFrom,$repoTo,[ref] $list)

    $log_content = New-Object 'System.Collections.Generic.List[String]'
    $myarray = "Rev   : Action    : Author    : Date                       : Path"

    if ($lstat -eq "True"){
		if($list.Count -gt 0){      
			Write-Host -ForegroundColor Green $myarray | Format-List
			[int]$r=0  
			while($logItems[$r].Revision -gt $clogrev){
				ForEach($x in $logItems[$r].ChangedPaths){
					$k=' '*(8-$x.Action.ToString().Length)
					$l=' '*(8-$logItems[$r].Author.ToString().Split('@')[0].Length)
					$m=' '*(25-$logItems[$r].Time.ToString().Length)
					$n = ' '*(4-$logItems[$r].Revision.ToString().Length)
					Write-Host -ForegroundColor Yellow $logItems[$r].Revision $n ':' $x.Action $k ':' $logItems[$r].Author $l ':' $logItems[$r].Time.ToString() $m ':'$x.Path       
				}
				$r++
			}
		}
		Write-Host ""
    }
    else{
        Write-Host -ForegroundColor Yellow " GetDiffSummary >>> FALSE"
        Write-Host "No change" -ForegroundColor Green
    }
}
catch{
    if(($_.Exception.InnerException.Message -match 'Locked') -or ($_.Exception.InnerException.Message -match 'cleanup')){
			[boolean] $cleanupstat = $svnClient.CleanUp([string]$localDir)
			if($cleanupstat -eq 'True'){
                Write-Host "Cleaning up to fetch summary"
				summary_notify $svnpath	$localDir
				}
		}
    else{
	Write-Host 'Error while writing the summary'
    Write-Host $_.Exception.Message
    Write-Host $_.Exception.InnerException.Message
    Write-Host " "
    $summary_flag=0
   }
}	
return $summary_flag
}

function Update-Folder(){
[OutputType([System.Collections.Hashtable])]
 
    [string]$localfolder=$args[0]
    [string]$svnpath=$args[2]
    [string]$dir=$args[1]
	$ini = $args[3]
    $localDir=$localfolder+$dir
    [int]$success_flag=1
    Write-Host "updating folder: $localDir"
    Write-Host "for repo path : $svnpath"
    $path= $localDir.SubString(0,$localDir.LastIndexOf('\')+1)

    $s=$dir.Split('\')
    [string]$s=$s[$s.Count-1]
    $ss=$s+" :"
    Write-Host -NoNewLine $ss -ForeGroundColor Green       
    $f1=0
	try{
        [SharpSvn.SvnWorkingCopyVersion]$wc_ver=$null
        [boolean]$wc_s=$workingcopyClient.GetVersion($localDir,[ref]$wc_ver)
        $Rev_start=$wc_ver.Start
        $Rev_end=$wc_ver.End
        [int]$clogrev= $Rev_start
        
        $logItems = New-Object 'System.Collections.ObjectModel.Collection[SharpSvn.SvnLogEventArgs]'
        [boolean] $lstat = $svnClient.GetLog([string]$localDir, [ref]$logItems)

        if($ini.Directories[$s] -match 'Head Revision'){
        	    [int] $toRev = $logItems[0].Revision
        }
        else{
        if($ini.Directories[$s] -match "^[\d\.]+$"){ 
             [int]$toRev= $ini.Directories[$s]
             }
        }

        Write-Host 'Working copy Revision number :' $clogrev
        if($clogrev -ne $toRev){
			$dict = New-Object 'System.Collections.Generic.Dictionary[string,[SharpSvn.SvnUpdateResult]]'
			$res  = New-Object -TypeName SharpSvn.SvnUpdateResult -ArgumentList $dict, 0
            $update_args = New-Object SharpSvn.SvnUpdateArgs
            $update_args.Revision=$toRev

			[boolean] $stat = $svnClient.Update([string]$localDir,$update_args, [ref]$res)
			if ($stat -eq "True"){
#				if($clogrev -lt $res.Revision){
					Write-Host "Updating to Revision : "   -ForegroundColor Green -NoNewLine
					Write-Host $res.Revision
					$clogrev_new= $res.Revision
#					$ini.Directories[$s] = $clogrev_new
					$fl=summary_notify $svnPath $localDir
#				}
   			}
        }
        if($clogrev -eq $toRev){
    			Write-Host "Directory : Already Updated "
                $f1=1
			}
		}
    catch{
		if($error[0].FullyQualifiedErrorId -eq "SvnAuthenticationException"){
			[PSCredential] $C = Get-Credential -Message "Credentials are required for access to $svnServer" -UserName ($ENV:UserName + "@" + $ENV:UserDomain)
			If([string]::IsNullOrEmpty($C)){
				Write-Verbose "Aborted by user"
				Exit
				}
			else{
				Write-Host "Credentials available"
				}
			Write-Host ''
			$svnClient.Authentication.DefaultCredentials = New-Object System.Net.NetworkCredential($C.Username, $C.Password)
			$svnClient.Authentication.add_SslServerTrustHandlers({
			$_.AcceptedFailures = $_.Failures
			$_.Save = $True
			})
            Write-Host "Updating again"
            Write-Host " "
            Update-folder $localfolder $dir $svnpath
        }
		if(($_.Exception.InnerException.Message -match 'Locked') -or ($_.Exception.InnerException.Message -match 'cleanup')){
			[boolean] $cleanupstat = $svnClient.CleanUp([string]$localDir)
			if($cleanupstat -eq 'True'){
				Write-Host "CleanUp done. Attempting update again..."
                Write-Host " "
				Update-folder $localfolder $dir $svnpath $ini
                $success_flag=1
				}
			}
        else{
             Write-Host " Access Denied" -ForeGroundColor Green
             Write-Host $_.Exception.InnerException.Message
#             Write-Host $_.Exception.Message
             Write-Host $error[0].FullyQualifiedErrorId
             Write-Host " "
             $success_flag=0
             }
        }
    Write-Host " "

	if($fl -eq 0){
	$success_flag=0
	}
    return $ini
}

function check_folder(){
[cmdletbinding()]
     [string]$svnLocalPath = $args[0]
     [System.Uri]$svnUrlPath = $args[1]
     $ini = $args[2]
     $server = $args[3]
     $s=$svnLocalPath.Split('\')
     $s=$s[$s.Count-1]
     $j=0
     foreach($y in $ini.Exclude.Keys){
        if($y -match $s){
        $r=$ini.Exclude[$y] -match '[0-9]'
        $yval=$Matches[0]
        if($yval -eq 1){
             $flag_i=3
             $j=1
             }
             }
     }
    if($j -eq 0){
	if(!(test-path $svnLocalPath)){
	    $flag_i=0
	}
	else{
	    [System.Uri]$uri= $svnClient.GetUriFromWorkingCopy($svnLocalPath)
       	if([string]::IsNullOrEmpty($uri)){
	    	$flag_i=1
	    }
	    else {
			if($ini.Repository[$server] -match $uri.Host){

			}
			else{
			Write-Host 'Relocating the repository from : ' $uri.AbsoluteUri ' to ' $svnUrlPath  
			Relocate_repo $uri.AbsoluteUri $svnUrlPath $svnLocalPath
			}
		    $flag_i=2
	    }
	}
    }
	return [int]$flag_i
 }

function Checkout-Folder(){

[string]$localfolder=$args[1]
[string]$svnUrl=$args[0]
[string] $dir=$args[2]
$ini=$args[3]

$localDir=$localfolder+$dir

 # Build SVN URL
[int]$sucess_flag=1

$repoUri = New-Object SharpSvn.SvnUriTarget($svnUrl)
try{
 Write-Host "checking out:" -ForegroundColor Green
Write-Host "Source URL : " $repoUri
Write-Host "Destination : " $localDir
$progress_args = New-Object 'System.Collections.ObjectModel.Collection[SharpSvn.SvnProgressEventArgs]'
$checkout_args= New-Object SharpSvn.SvnCheckOutArgs

#$checkout_args.Progress+=$progress_args
[boolean] $res = $svnClient.CheckOut($repoUri, $localDir,$checkout_args)
if ($res -eq "True"){
	Write-Host "Updated to Revision: " $res -ForegroundColor Yellow
	Write-Host "Done" -ForegroundColor Green
	Write-Host " "
}
	
$s=$dir.Split('\')
$logItems = New-Object 'System.Collections.ObjectModel.Collection[SharpSvn.SvnLogEventArgs]'
[boolean] $lstat = $svnClient.GetLog([string]$localDir, [ref]$logItems)
if($lstat -eq "True"){
[int] $toRev = $logItems[0].Revision
$test2log= $s[$s.count-1]+ "-" + [string]$toRev

[int]$done=0
[int]$check=0
if($ini.Directories[$s] -match '\d'){$ini.Directories[$s] = $toRev}
elseif($ini.Directories[$s] -match 'Head Revision'){}
}
}
catch{
    if($error[0].FullyQualifiedErrorId -eq "SvnAuthenticationException"){
      [PSCredential] $C = Get-Credential -Message "Credentials are required for access to $svnServer" -UserName ($ENV:UserName + "@" + $ENV:UserDomain)
       If([string]::IsNullOrEmpty($C)){
          Write-Verbose "Aborted by user"
          Exit
        }
      else{
          Write-Host "Credentials available"
         }
       Write-Host ''
     $svnClient.Authentication.DefaultCredentials = New-Object System.Net.NetworkCredential($C.Username, $C.Password)
     $svnClient.Authentication.add_SslServerTrustHandlers({
			$_.AcceptedFailures = $_.Failures
			$_.Save = $True
			})
	 Checkout-Folder $svnUrl $localfolder $dir $ini
    }
	else{
		Write-Warning "Authentication error"
		Write-Host $_.Exception.InnerException.Message
		Write-Host ""
		}
	}
	return $ini
}

function Get-IniContent (){
    $FilePath =$args[0]
    $CommentChar = @("#")
    $ini = @{}
    switch -regex -file $FilePath
    {
        "^\[(.+)\]" # Section
        {
            $section = $matches[1]
            $ini[$section] = @{}
            $CommentCount = 0
        }
        
        "(.+?)\s*=(.*)" # Key
        {
            $name,$val = $matches[1..2]
            if(!($name -match "[$CommentChar]")){

            if($name -match '\w+ \w+'){$name =$matches[0]}
            elseif($name -match '\S+'){$name=$Matches[0]}

            if($val -match '\w+ \w+'){$value =$matches[0]}
            elseif($val -match '\S+'){$value=$Matches[0]}
            else{$value=$val}

            $ini[$section][$name] = $value
            }
        }
        "^([$($CommentChar -join '')].*)$"
        {
            $value = $matches[1]
            $CommentCount++
            $name = "Comment" + $CommentCount
            $ini[$section][$name] = $value
        }
    }
    return $ini
}

function update-IniFile(){
    $InputObject=$args[0]
    $FilePath =$args[1]
    $flag=$args[2]
    $ini=Get-IniContent $FilePath
    $n= Compare-Hashtable $InputObject $ini
    if(!($n.Count -eq 0)){
    $outFile=Get-Content -Path $FilePath
    foreach ($k in $InputObject.keys){
                    $nn = Compare-Hashtable $InputObject[$k] $ini[$k]
                    if(!($nn.Count -eq 0)){
                    $LineSection = Select-String $FilePath -Pattern "\[$k\]" | Select-Object -ExpandProperty 'LineNumber'
                    Foreach ($kkeys in ($InputObject[$k].keys)){
			            if($kkeys -match '\\'){	$ini_x=$kkeys.Replace('\','_') }
                        else{ $ini_x = $kkeys }
                        for($i=$LineSection;$i -lt $LineSection+$InputObject[$k].Count; $i++){
                            if(($outFile[$i] -match '#') -and ($ini_x -match 'Comment')){$outFile[$i]=“$($InputObject[$k][$kkeys])”}
                            elseif($outFile[$i].Replace('\','_') -match $ini_x){
                                $outFile[$i]=“$kkeys=$($InputObject[$k][$kkeys])”
                                }
                            }
                         }
                    }
        }
    Set-Content -Path $FilePath -Value $outFile
    }
}

function Checkout_settings(){

[string]$localfolder=$args[1]
[string]$svnUrl=$args[0]
[int]$flag=1

$export_args = New-Object 'System.Collections.ObjectModel.Collection[SharpSvn.SvnExportArgs ]'
$repoUri = New-Object SharpSvn.SvnUriTarget($svnUrl)

try{
Write-Host "checking out:" -ForegroundColor Green
Write-Host "Source URL : " $repoUri
Write-Host "Destination : " $localFolder
#$status_args = New-Object 'System.Collections.ObjectModel.Collection[SharpSvn.SvnCheckOutArgs ]'
[boolean] $res = $svnClient.Export($repoUri, $localfolder)
if ($res -eq "True"){
	Write-Host "Exported Succesful "
	Write-Host "Done" -ForegroundColor Green
	Write-Host " "
}
}
catch{
    if($error[0].FullyQualifiedErrorId -eq "SvnAuthenticationException"){
      [PSCredential] $C = Get-Credential -Message "Credentials are required for access to $svnServer" -UserName ($ENV:UserName + "@" + $ENV:UserDomain)
       If([string]::IsNullOrEmpty($C)){
          Write-Verbose "Aborted by user"
          Exit
        }
      else{
          Write-Host "Credentials available"
         }
        Write-Host ''
        $svnClient.Authentication.DefaultCredentials = New-Object System.Net.NetworkCredential($C.Username, $C.Password)
        $svnClient.Authentication.add_SslServerTrustHandlers({
		$_.AcceptedFailures = $_.Failures
		$_.Save = $True
		})
	 Checkout_settings $svnUrl $localfolder
    }
	else{
		Write-Warning "Authentication error"
		Write-Host $_.Exception.InnerException.Message
		Write-Host ""
        $flag=0
		}
	}
return $flag
}

function Relocate_repo(){ 
# Relocate_repo $uri.AbsoluteUri $ini.Repository.server $svnLocalPath
    [System.Uri]$fromUri = $args[0]
    [System.Uri]$toUri = $args[1]
	[String]$path = $args[2]
	[boolean] $res = $svnClient.Relocate($path, $fromUri, $toUri)
	if ($res -eq "True"){
		Write-Host "Relocation done " $res -ForegroundColor Yellow
		Write-Host " "
	}
}

function check_repair_Ini(){
[cmdletbinding()]
$ini=$args[0]
$ini_server=$args[1]
$n= Compare-Hashtable $ini_server $ini
if(!($n.Count -eq 0)){
$ini1=$ini

Write-Host -ForegroundColor Green "Checking setting file ..."
$r= $n -match 'Repository'
$flag=0
if(!($r.Count -eq 0)){
foreach($i in $r){
	if($i.lvalue -eq $null){Write-Host 'key' $i.path ': not present in server setup file'}
	elseif($i.rvalue -eq $null){Write-Host 'key' $i.path ': not present in local setup file'}
	else{
		if(!($i.lvalue -eq $i.$rvalue)){
			Write-Warning 'server address mismatch found'
			Write-Host 'local setup file server address' $i.rvalue
			Write-Host 'server setup file server address' $i.lvalue
			$flag=1
		}
	}
}
$ini.Repository=$ini_server.Repository
}

$r2=$n -match 'Directories'
if(!($r2.Count -eq 0)){
foreach($j in $r2){
	if($j.lvalue -eq $null){Write-Host $j.path ' not present in server setup file'}
	else{
        if($j.rvalue -eq $null){
            Write-Host $j.path ' not present in local setup file'
            Write-Host 'Fixing by getting value from server setup file'
            $ini.Directories[$j.path.Split('\')[1]]=$j.lvalue
            }
		elseif(!(($j.rvalue -match 'Head Revision') -or ($j.rvalue -match '^[\d\.]+$'))){
			Write-Host -ForegroundColor Green 'Values mismatch : ' $j.path ':' $j.rvalue
			Write-Host 'Revision reverted back to Head Revision'
			$ini.Directories[$j.path.Split('\')[1]]='Head Revision'
		    }
		}
	}
}
Write-Host ""
$r3=$n -match 'Repo Structure'
if(!($r3.Count -eq 0)){
    $ini.'Repo Structure'=$ini_server.'Repo Structure'
}

$r4=$n -match 'Exclude'
if(!($r4.Count -eq 0)){
foreach($i in $r4){
    if($i.rvalue -eq $null){Write-Host $i.path ' not present in local setup file'}
	else{
		if(!($i.rvalue -match '^[\d\.]+$')){
			Write-Warning 'Values mismatch : ' $j.path ':' $j.$rvalue
			Write-Host 'Value updated to 0'
			$ini.Directories[$j.path.Split('\')[1]]=$j.lvalue
			}
		}
	}
}
}
return $ini     
}

function display_intro(){
$ver=$args[0]
$svnServer=$args[1]
Write-Host 'Powershell version : ' $ver.Version
Write-Host '--------------------------'
Write-Host ''
Write-Host '-------------------------------------------------------------------------------'
Write-Host '          Automated repository installation and updation tool '
Write-Host '         Repository : ' $svnServer
Write-Host '--------------------------------------------------------------------------------'
$d=Get-Date -Format g
Write-Host $d
Write-Host ''
}

#--------------------------------------------------------------------------------------------------------------------------
#-----------------------------------------------MAIN PROGRAM---------------------------------------------------------------

$ver=Get-Host | Select-Object Version

[string] $svnCheckoutRootPath= Get-Location;
[string]$CurrentDir = $svnCheckoutRootPath

# -------------------------------------------------------------------------------------------------
Write-Verbose $PSScriptRoot
# Setup Variables
$mode = [System.IO.FileMode]::Create
$access = [System.IO.FileAccess]::Write
$sharing = [IO.FileShare]::Read

#___________________________________________________________________________________
[string]$svnServer  = Specify server address
#___________________________________________________________________________________

[string] $svnDLLPath  = "SharpSvn.dll"
# Create SharpSVN Client Object
Add-Type -Path $svnDLLPath
$svnClient = New-Object SharpSvn.SvnClient
# Create SharpSVN WorkingCopy Client Object
$workingcopyClient=New-Object SharpSvn.SvnWorkingCopyClient

#-------------Reading setting file----------------------------------
$logfile = $svnCheckoutRootPath +'\log.txt'
$Global:inifilepath = $svnCheckoutRootPath +'\setting.cfg'
$tempinifilepath = $svnCheckoutRootPath +'\settings_tmp.cfg'
$svnURL_setup = $svnServer+'dev/ps_sharpsvn/settings.cfg'

if([System.IO.File]::Exists($inifilepath)){
$ini_host=Get-IniContent $inifilepath
if([System.IO.File]::Exists($tempinifilepath)){Remove-Item $tempinifilepath -Force}
$flag_checkout = Checkout_settings $svnURL_setup $tempinifilepath
if($flag_checkout -eq 1){
$ini_server = Get-IniContent $tempinifilepath
$ini=check_repair_Ini  $ini_host $ini_server
Remove-Item $tempinifilepath -Force
}
elseif($flag_checkout -eq 0){
Write-Host -ForegroundColor Green "Check network, Unable to connect to repository"
$ini=$ini_host
}
}
else{
$flag_checkout=Checkout_settings $svnURL_setup $inifilepath
$ini=Get-IniContent $inifilepath
}

if($ini.Count -eq 0){
Write-Host "Settings file not found"
Write-Host "Contact Administrator"
break
}

display_intro $ver $svnServer

#$logUIBindItems = New-Object 'System.Collections.ObjectModel.Collection[SharpSvn.UI.SvnUIBindArgs]'
#$svnUI== New-Object SharpSvn.SvnUI.Bind($svnClient, [ref]$logUIBindItems)

$flag = New-Object 'System.Collections.Generic.List[Int]'
$localpath = New-Object 'System.Collections.Generic.List[String]'
$suffix = New-Object 'System.Collections.Generic.List[String]'
$server_suffix = New-Object 'System.Collections.Generic.List[String]'

#loop to check_folder whether it needs update, installation or checkout
# and to assign ordered repository addresses and local addresses to variable suffix and server_suffix
foreach($x0 in $ini.Directories.Keys){
if(!($x0 -match 'Comment')){
    $suff='\'+$x0
if($x0 -match '\\'){ $x_d=$x0.Split('\')[1]} else{$x_d=$x0}
    foreach($y in $ini.'Repo Structure'.Keys){
        if(!($y -match 'Comment')){
            if($ini.'Repo Structure'[$y] -match [regex]::Escape($x_d)){
                [string]$svnLocalPath=$svnCheckoutRootPath + $suff
                $localpath.add($svnLocalPath)
                $suffix.Add('\'+$x0)
                $rr=$ini.'Repo Structure'[$y] -match '\S+'
                $yval=$Matches[0]         
                $server_suffix.Add($yval)    
                foreach($rep in $ini.Repository.Keys){
                  if(!($rep -match 'Comment') -and ($yval.Split('_')[0] -like $rep.Split(' ')[0])){
                    $svnServer=$ini.Repository[$rep]
                    $rep_server=$rep
                }
                }
                [System.Uri] $svnUrl = $svnServer + $yval
#                Write-Host $svnUrl
#                Write-Host $svnLocalPath
                $x_c=check_folder $svnLocalPath $svnUrl $ini $rep_server   
                $flag.add($x_c)
            }
        }
    }
}
}
Write-Host ''
[int]$install_success_flag=0
#loop to do the required action as per the flag obtained in above loop
for ([int]$i=0; $i -lt $suffix.Count;$i++ ){
    foreach($rep in $ini.Repository.Keys){
      if(!($rep -match 'Comment') -and ($rep.Split(' ')[0] -like $server_suffix[$i].Split('_')[0])){$svnServer=$ini.Repository[$rep]
   }
    }
    [int]$xi=0
	[System.Uri] $svnUrl = $svnServer + $server_suffix[$i]
	switch($flag[$i]){
	0 #folder to be created and checked out
    {
    Write-Host '--------------------------------------------------------------------------------'
		Cond-Create-Folder $localpath[$i]
		$ini1=Checkout-Folder $svnUrl $svnCheckoutRootPath $suffix[$i] $ini
		$ini=$ini1
	}
	1 #folder already present and to be checkout
    {
    Write-Host '--------------------------------------------------------------------------------'
		$ini1=Checkout-Folder $svnUrl $svnCheckoutRootPath $suffix[$i] $ini
		$ini=$ini1
    }
   	2 # folder only to be updated
    {
    Write-Host '--------------------------------------------------------------------------------'
	$ini1=Update-Folder $CurrentDir $suffix[$i] $svnUrl $ini
    $ini=$ini1
    }
    3 # folders excluded
    {
	Write-Host 'Excluded from update :' $suffix[$i]
    }
   }
$install_success_flag=$install_success_flag+$xi
}
$flag_write=1
update-IniFile $ini $inifilepath $flag_write 

$simRepoInstallerPath=$svnCheckoutRootPath + "dev\ps_sharpsvn"
$simRepoUpdater = $simRepoInstallerPath+"\delete_prev.exe" 
#Write-Host $simRepoInstallerPath
if($ini.'Self-Update'['flag'] -match '1') {
Start-Process -FilePath $simRepoUpdater -ArgumentList "$simRepoInstallerPath $svnCheckoutRootPath"
}

Write-Host -NoNewLine 'Press any key to continue...';
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
