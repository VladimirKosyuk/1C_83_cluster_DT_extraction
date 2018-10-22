#Скрипт удаления старых бекапов для скрипта бекапа 1С 8.3 серверной версии на основе RAS.exe
#
# ДАТА: 22 октября 2018 года	

$confg = "$PSScriptRoot\1cBackupConfig"+('.txt')
$globallog = "$PSScriptRoot\1cArchRemLog"+('.log')

#-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#Краткое функциональное описание:
<# 
-Использует переменную destination из файла 1cBackupConfig, который должен находиться в том же месте, что и скрипт
-Проверяет доступность файла конфига 
-Оставляет все бекапы за текущий месяц и по одному за каждый предидущий месяц
-Удаляет только бекапы 1С и SQL и только во всех дочерних директориях хранилища бекапов, указанного в 1cBackupConfig
-Создает лог удаления, который находится в том же месте, что и скрипт.
#>

try

{
    $values = (Get-Content $confg).Replace( '\', '\\') | ConvertFrom-StringData 
    $destination = $values.destination
   
}

catch

{   
    Write-Host "No config file has been found" -ForegroundColor RED
    Write-Output $Error[0].Exception.Message
    Write-Host "Script terminated with error." -ForegroundColor Yellow
    Write-Output ("FATAL ERROR - Config file is accessible check not passed  "+(Get-Date)) | Out-File "$globallog" -Append
    Break 
}

Write-Output ("Cleaning started  "+(Get-Date)) | Out-File "$globallog" -Append

try

{
  $Dirs = Get-ChildItem $destination -Recurse| where {$_.PSIscontainer} | Select-Object  Select-Object -ExpandProperty "FullName" 

    FOREACH ($dir in $dirs) {

    Get-ChildItem $dir| where {(((($_.LastWriteTime).month) -lt ((get-date).Month))) -and ($_.name -like "*.dt" -or $_.name -like "*.bak" -or $_.name -like "*.backup")} | 

    Group-Object -property {$_.LastWriteTime.Month} |

        Foreach {

	        $_.Group | Group {$_.LastWriteTime.Date.ToString("MMyyyy")} | Where {$_.Count -gt 1} | Foreach {

		    $rem  = $_.Group | Sort LastWriteTime

		    if($rem[0].LastWriteTime.Date.ToString("dd") -eq "01") {

			    $rem | Where {$_.LastWriteTime.Date.ToString("dd") -ne "01"} | rm -Force -Recurse -Verbose 4>&1 |Out-File "$globallog" -Append
		    }

		    else {$rem | Sort -Descending | Select -Skip 1 | rm -Force -Recurse -Verbose 4>&1 |Out-File "$globallog" -Append}

            }
        }

    }
}

catch

{
    Write-Host "Cannot remove old archives!" -ForegroundColor Red
    Write-Output $Error[0].Exception.Message
    Write-Output "FATAL ERROR - Removing old archives failed" | Out-File "$globallog" -Append
    Break 
}


Write-Output ("Cleaning finished  "+(Get-Date)) | Out-File "$globallog" -Append
