#Скрипт бекапа 1С 8.3 серверной версии на основе RAS.exe
#
# ДАТА: 11 октября 2018 года										   
 
#-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#Краткое функциональное описание:
<# 

-Хранит переменные в файле 1cBackupConfig, который должен находиться в том же месте, что и скрипт
-Проверяет условия для своего выполнения, пытается исправить, если условия не выполняются 
-Удаляет бекапы, которые старше 3 месяцев из хранилища
-Делает выгрузку всех баз серверной версии 1С 8.3 в .dt, у которых не указано в описании no_backup
-Проверяет успешность выполнения бекапов, если не успешно - шлет на почту письмо
-Создает лог для каждой базы с результатом выполнения бекапа и глобальный лог с подробным отчетом о выполнении, который находится в том же месте, что и скрипт.

#>
#-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#Для успешного выполнения скрипта необходимо:
<# 

Powersheel версии 4
Ragent.exe, запущенный как служба
RAS.exe, запущенный как служба
Доступность источника и хранилища бекапов
Запуск скрипта от имени администратора(для регистрации и запуска служб)
Powersheel ExecutionPolicy Unrestricted

#>
#-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#Порядок выполнения скрипта: 
<# 

-Задаем кодировку
-Считываем переменные из файла, если его нет или он недоступен - останавливаем скрипт
-Проверяем версию Powersheel, если она ниже 4 - останавливаем скрипт
-Проверяем запущенную службу Ragent, если она не запущена - пробуем запустить, если не получается - останавливаем скрипт
-Проверяем службу RAS - если она найдена, но не запущена, пробуем запустить, если она не найдена - пробуем зарегистрировать, если не получается запустить и\или зарегистрировать - останавливаем скрипт
-Проверяем доступность хранилища бекапов, если недоступно - пытаемся создать папку по указанному в переменных адресу, если не получается - останавливаем скрипт
-Очищаем архивы старше 3 месяцев, если не получается - пишем в глобальный лог и продолжаем выполнять скрипт
-Последовательно для каждой базы кластера, у которой нет описания no_backup, блокируем регламентные задания, блокируем сеансы, пробуем выполнить бекап, ждем, пока все файлы временных логов не будут заполнены или пройдет 2 часа и включаем регламенентные задания
-Проверяем выполненные бекапы на успешность, если во всех логах нет сообщения об успешном бекапе, не найдено временных логов, найдены ошибки в логах или часть\все не выполнены - пробуем отправить письмо с указанием имени сервера, типом ошибки и логами бекапа баз, которые не смогли забекапиться, либо с глобальным логом, если временные логи не обнаружены

#>
#-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

#Устанавливаем кодировку
ipconfig |Out-Null
[Console]:: outputEncoding = [System.Text.Encoding]::GetEncoding('cp866')

#-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#Задаем путь к файлу с переменными
$confg = "$PSScriptRoot\1cBackupConfig"+('.txt')
#задаем путь к глобальному логу скрипта
$globallog = "$PSScriptRoot\1cBackupLog"+('.log')

#Здесь мы считываем файл с переменными
try

{
    $values = (Get-Content $confg).Replace( '\', '\\') | ConvertFrom-StringData 
    #указываем путь к RAS.exe
    $env:Path = $values.path
    #указываем ip adress и порт для RAS.exe
    $IpAddressAndPort = $values.IpAddressAndPort
    #указываем логин и пароль администратора для баз данных
    $userName = $values.userName
    $password = $values.password
    #задаем путь к хранилищу бекапов
    $destination = $values.destination
    #указываем список лиц для оповещения
    $recipients = $values.recipients
    #указываем логин для отправки почты
    $SmtpLogin = $values.SmtpLogin
    #указываем пароль для отправки почты
    $SmtpPassword = $values.SmtpPassword
}

catch

{   
    Write-Host "No config file has been found" -ForegroundColor RED
    Write-Output $Error[0].Exception.Message
    Write-Host "Script terminated with error." -ForegroundColor Yellow
    Write-Output ("FATAL ERROR - Config file is accessible check not passed  "+(Get-Date)) | Out-File "$globallog" -Append
    Break 
}


#-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#Объявляем функции:

#Проверяем версию Powersheel
$PoshVerCheck = {

if ($host.version | select major | where-object {($_.major -cge "4")})

{Write-Host "PowerShell version is applicable" -ForegroundColor Green}

Else 

{
    Write-Host "Need to update powershell version at least to major 4!" -ForegroundColor RED
    Write-Host "Script terminated with error." -ForegroundColor Yellow
    Write-Output ("FATAL ERROR - PowerShell version check not passed "+(Get-Date)) | Out-File "$globallog" -Append
    Break 
}

}

#Проверяем службу Ragent
$RagentCheck = {

if ($RagentSrvc = Get-WmiObject win32_service | Where-Object{($_.Name -like '*1C*' -and $_.Name -notlike 'pgsql*') -and ($_.PathName -like '*ragent.exe*')})

{

If ($RagentSrvc.State -match "Running") {Write-Host "Ragent.exe service is running" -ForegroundColor Green}

else

{

try

{
    Write-Host "Ragent.exe service is not running, trying to start service" -ForegroundColor Red
    Start-Service -name $RagentSrvc.name
    Write-Host "Ragent.exe service is running" -ForegroundColor Green
    Write-Output "WARNING - Ragent.exe service has been pushed to run" | Out-File "$globallog" -Append
}

catch

{ 
    Write-Host "Cannot start Ragent.exe service!" -ForegroundColor Red
    Write-Output $Error[0].Exception.Message
    Write-Host "Script terminated with error." -ForegroundColor Yellow
    Write-Output ("FATAL ERROR - Ragent.exe service is running check not passed "+(Get-Date)) | Out-File "$globallog" -Append
    Break 
}

}

}

else

{
    Write-Host "Ragent.exe service not found!" -ForegroundColor Red
    Write-Host "Script terminated with error." -ForegroundColor Yellow
    Write-Output ("FATAL ERROR - Ragent.exe service is found check not passed "+(Get-Date)) | Out-File "$globallog" -Append
    Break
}

}

#Проверяем службу RAS
$RasCheck = {

if ($RacSrvc = Get-WmiObject win32_service | Where-Object{($_.Name -like '*1C*' -and $_.Name -notlike 'pgsql*') -and ($_.PathName -like '*ras.exe*')})

{

If ($RacSrvc.State -match "Running") {Write-Host "RAS.exe service already registered and running" -ForegroundColor Green}

else

{

try

{
    Write-Host "RAS.exe service has been found but not running, trying to start service" -ForegroundColor Red
    Start-Service -name $RacSrvc.name -ErrorAction Stop
    Write-Host "RAS.exe service is running" -ForegroundColor Green
    Write-Output "WARNING - RAS.exe service has been pushed to run" | Out-File "$globallog" -Append
}

catch

{ 
    Write-Host "Cannot start RAS.exe service!" -ForegroundColor Red
    Write-Output $Error[0].Exception.Message 
    Write-Host "Script terminated with error." -ForegroundColor Yellow
    Write-Output ("FATAL ERROR - RAS.exe service is running check not passed "+(Get-Date)) | Out-File "$globallog" -Append
    Break
}

}

}

else 

{

    Write-Host "RAS.exe not found, trying to register" -ForegroundColor Red

try

{
    New-Service -Name "1C:Enterprise 8.3 Remote Server" -BinaryPathName "$env:Path\ras.exe cluster --service --port=1545 $IpAddressAndPort" -DependsOn "1C:Enterprise 8.3 Server Agent" -DisplayName "1C_RAS" -StartupType Automatic -Description "This is for 1C backup" -ErrorAction Stop| Out-Null
    Start-Service -name "1C:Enterprise 8.3 Remote Server" -ErrorAction Stop
    Write-Host "RAS.exe has been registered and running" -ForegroundColor Green
    Write-Output "WARNING - RAS.exe has been registered and pushed to run" | Out-File "$globallog" -Append
}

catch

{
    Write-Host "Cannot register RAS.exe service!" -ForegroundColor Red
    Write-Output $Error[0].Exception.Message 
    Write-Host "Script terminated with error." -ForegroundColor Yellow
    Write-Output ("FATAL ERROR - RAS.exe is registered check not passed "+(Get-Date)) | Out-File "$globallog" -Append
    Break
}

}
 
}

#Проверяем доступность хранилища бекапов
$DestCheck = {

try

{
    #проверяем доступность хранилища бекапов, создаем папку для логов
    Get-ChildItem $destination -ErrorAction Stop | Out-Null
    Write-Host "Destination path $destination is reachable" -ForegroundColor Green
    #создадим папку для логов
    new-item $destination -name log -type directory -force | Out-Null
 }
 
catch

{

    Write-Host "Destination path $destination is unreachable, trying to create folder" -ForegroundColor Red 

try

{
    #пытаемся создать папку хранилища бекапов и папку логов
    new-item (Split-Path $destination -Qualifier) -name (Split-Path $destination -leaf) -type directory -force -ErrorAction Stop |Out-Null
    Write-Host "Destination folder has been created" -ForegroundColor Green
    #создадим папку для логов
    new-item $destination -name log -type directory -force | Out-Null
    Write-Output "WARNING - Destination folder has been not found and was created" | Out-File "$globallog" -Append
}

catch

{
    Write-Host "Cannot create destination folder!" -ForegroundColor Red
    Write-Output $Error[0].Exception.Message
    Write-Host "Script terminated with error." -ForegroundColor Yellow
    Write-Output ("FATAL ERROR - Destination folder create check not passed "+(Get-Date)) | Out-File "$globallog" -Append
    Break
}
 
}

}

#Очищаем архивы старше 3 месяцев
$RemOldArch = {

$datetime = (Get-Date).AddDays(-92) 
#получаем список файл в хранилище бекапов
								
																   
															 
																					  
														

try

{
    $BackupList = ls -r $destination
    #делаем выборку по полученным файлам
    $BackupList | Where-Object {$datetime -gt $_.LastWriteTime} |
    #процесс удаления файлов c логированием в отчет
    rm -recurse -Verbose 4>&1 |Out-File "$globallog" -Append
}

catch

{
    Write-Host "Cannot remove old archives!" -ForegroundColor Red
    Write-Output $Error[0].Exception.Message
    Write-Output "WARNING - Removing old archives failed" | Out-File "$globallog" -Append}
}

#Выполняем бекап
$DoBackup = {

#ф-ция нужна для работы скрипта, переводит вывод RAC.exe в объекты, написана Александром Королевым
function RacOutToObject($rac_out) {

$objectList = @()  
$object     = New-Object -TypeName PSObject      

	FOREACH ($line in $rac_out) {    

		#Write-Host "raw: _ $line _"

		if (([string]::IsNullOrEmpty($line))) {
		 	$objectList += $object
			$object     = New-Object -TypeName PSObject      
		}

		# Remove the whitespace at the beginning on the line
        	$line = $line -replace '^\s+', ''
   
		$keyvalue = $line -split ':'
	
		$key     = $keyvalue[0] -replace '^\s+', ''
		$value   = $keyvalue[1] -replace '^\s+', ''

		$key	 = $key.trim()
		$value   = $value.trim()

		if (-not ([string]::IsNullOrEmpty($key))) {
		    $object | Add-Member -Type NoteProperty -Name $key -Value $value
	        }
						
        }

	return $objectList
}

$Cluster = RacOutToObject(rac.exe cluster list)
$cluster_uuid = $Cluster[0].cluster
$cluster_host = $Cluster[0].host
$cluster_port = $Cluster[0].port
$infobases    = RacOutToObject(rac.exe infobase summary list --cluster=$cluster_uuid) 

#удаляем старые временные логи бекапа
ls -r $destination\log | rm -recurse

FOREACH ($infobase in $infobases) {
    #задаем служебные переменные
    $infobase_uuid = $infobase.infobase
    $infobase_name = $infobase.name
    $infobase_descr = $infobase.descr
    $sessions = RacOutToObject(rac.exe session list --cluster=$cluster_uuid --infobase=$infobase_uuid)

        if($infobase_descr -match "no_backup") {continue}

#блокируем регламентные задания
Write-Host "Starting scheduled-jobs deny for $infobase_name"
rac.exe infobase update --infobase=$infobase_uuid --infobase-user=$userName --infobase-pwd=$password --cluster=$cluster_uuid --scheduled-jobs-deny=on

#блокируем сеансы
FOREACH ($session in $sessions) {

    $session_uuid = $session.session
    $sessionsUsr = $session | Select-Object -ExpandProperty "user-name"
    Write-Host "Terminate $sessionsUsr session in $infobase_name" 
    rac.exe session terminate --cluster=$cluster_uuid --session=$session_uuid
}

#задаем служебные переменные для выполнения бекапа и создаем директории для каждой из копируемых баз
$BackupDate = Get-Date -format yyyy-M-dd 
New-Item -ItemType directory -Path "$destination\$infobase_name\" -ErrorAction SilentlyContinue |out-null
$1cStart = Split-Path $env:Path -parent | Split-Path -Parent
Write-Host "Starting backup $infobase_name on ${cluster_host}:${cluster_port}" -ForegroundColor Yellow
Write-Output ("Starting backup $infobase_name "+(Get-Date -Format T)) | Out-File "$globallog" -Append

#здесь мы пробуем выполнить бекап
try

{& $1cStart\common\1cestart.exe config /S"${cluster_host}:${cluster_port}\$infobase_name" /N"$userName" /P"$password" /WA- /DumpIB"$destination\$infobase_name\$BackupDate.dt" /Out "$destination\log\$infobase_name.log" -append}

catch

{
    Write-Host "Cannot backup $infobase_name on ${cluster_host}:${cluster_port}" -ForegroundColor RED
    Write-Output $Error[0].Exception.Message | Out-File "$globallog" -Append
    Write-Output ("ERROR - backup $infobase_name "+(Get-Date -Format T)) | Out-File "$globallog" -Append
}
 
}

#ожидаем окончание бекапа, но не дольше 120 минут и включаем регламентные задания
$startDate = Get-Date

FOREACH ($infobase in $infobases) {

$infobase_uuid = $infobase.infobase
$infobase_name = $infobase.name
do {start-sleep -s 300}
until (((Get-ChildItem -Path $destination\log |where {$_.Length -gt 0} |select name |Out-String) -eq (Get-ChildItem -Path $destination\log | select name |Out-String) -eq "true") -or ((Get-Date).CompareTo($startDate.AddMinutes(120)) -eq "1"))
Write-Host "Starting scheduled-jobs allow for $infobase_name"
rac.exe infobase update --infobase=$infobase_uuid --infobase-user=$userName --infobase-pwd=$password --cluster=$cluster_uuid --scheduled-jobs-deny=off
Write-Host "Backup $infobase_name is finished on ${cluster_host}:${cluster_port}" -ForegroundColor Green
Write-Output ("Backup $infobase_name is finished "+(Get-Date -Format T)) | Out-File "$globallog" -Append
}
#здесь мы проверяем выполнение бекапа

#ф-ция для отправки письма
Function SendEmialOnError ($recipients, $body) {

    #задаем тему письма для отчета по почте
    $EmailSubj = (Get-WmiObject -Class Win32_ComputerSystem |Select-Object -ExpandProperty "name")+" 1C backup error"
    #задаем логин\пароль для отправки почты
    $secpasswd = ConvertTo-SecureString $SmtpPassword -AsPlainText -Force
    $mycreds = New-Object System.Management.Automation.PSCredential ($SmtpLogin, $secpasswd)
    #указываем параметры отправки почты
    $EmailParam = @{
                    SmtpServer = 'smtp.gmail.com'
                    Port = 587
                    UseSsl = $true
                    Credential  = $mycreds
                    From = $SmtpLogin
                    To = $recipients -split ','
                    Subject = $EmailSubj
                    Attachments = $MailReport
                    Body = $Body
}
#отправляем почту
Write-Host "Sending email to $recipients"

try

{
    Send-MailMessage @EmailParam -Encoding ([System.Text.Encoding]::UTF8) -ErrorAction Stop
    Write-Host "Email has been sent" -ForegroundColor Green
    Write-Output ("Email has been sent "+(Get-Date -Format T)) | Out-File "$globallog" -Append
}

catch

{
    Write-Host "Cannot send email!" -ForegroundColor Red
    Write-Output $Error[0].Exception.Message
    Write-Output ("ERROR - Email not sent "+(Get-Date -Format T)) | Out-File "$globallog" -Append
}

}

#проверяем выполненные бекапы
$TempLogs = Get-ChildItem $destination\log
#получаем логи с ошибками
try
 
{$GetBkpErr = Get-Content ($TempLogs| Select-Object -ExpandProperty "fullname") | where {(($_ -match "error") -or ($_ -match "Ошибка")) -or ($_ -notmatch "Выгрузка информационной базы успешно завершена")} |select PSPath}

catch

{
#здесь  отправить письмо админам с задачей проверки бекапов, причина -  не найдено логов бекапа
    $MailReport = $globallog
    $body =  "Backup logs not found, see global log"
    Write-Host $body -ForegroundColor RED
    Write-Output ("ERROR - no temporary logs have been found, sending email to $recipients "+(Get-Date -Format T)) | Out-File "$globallog" -Append
    SendEmialOnError $recipients $body
    Break
}

#проверяем условие - все логи должны быть не нулевого размера
if (($TempLogs.Count) -eq (($TempLogs | where-object {$_.Length -gt 0}).count)) 
#проверяем логи на наличие ошибок
{
#ищем во всех ненулевых логах сообщения об ошибках
if ($GetBkpErr) 

{   #здесь  отправить письмо админам с задачей проверки бекапов, причина -  во время выполнения бекапа найдены ошибки
    $MailReport = $GetBkpErr | Select-Object -ExpandProperty "PSPath"
    $body =  "Backup errors found, need to check $destination\log"
    Write-Host $body -ForegroundColor RED
    Write-Output ("ERROR - errors found in logs, sending email to $recipients "+(Get-Date -Format T)) | Out-File "$globallog" -Append
    SendEmialOnError $recipients $body
} 

Else 

{
    Write-Host "All infobases have been backuped successfully on ${cluster_host}:${cluster_port}" -ForegroundColor Yellow
    Write-Output ("SUCCESS - Backup finished on ${cluster_host}:${cluster_port} "+(Get-Date -Format T)) | Out-File "$globallog" -Append
} 

}

Else 
# если (список всех баз кластера) входит в множество (списка папок бекапа с ненулевыми файлами .dt с именем $BackupDate) то все хорошо. если нет, то отправить письмо админам с задачей проверки бекапов, причина -  Не для всех баз кластера был выполнен бекап
{

Write-Host "Zero sized logs have been found, starting archives check" -ForegroundColor RED

if (($infobases |where {$_.descr -notmatch '"no_backup"'} | Select-Object -ExpandProperty "name"| Out-String) -contains (get-childitem $destination -Recurse | Where-Object {(-Not $_.PSIscontainer -and $_.Length -gt 0) -and ($_.Name -match "$BackupDate"+('.dt')) } | Select-Object -ExpandProperty "fullname" | split-path -parent | split-path -leaf| Out-String))

{
    write-host "All current backups found" -ForegroundColor Green
    Write-Output ("WARNING - non-zero sized logs check not passed, but all current backups have been found "+(Get-Date -Format T)) | Out-File "$globallog" -Append
}

else

{   #здесь  отправить письмо админам с задачей проверки бекапов, причина -  Во время выполнения бекапа найдены ошибки
    $MailReport = $TempLogs | where-object {$_.Length -eq 0} | Select-Object -ExpandProperty "fullname"
    $body =  "Missing some of current backups, need to check $destination"
    Write-Host $body -ForegroundColor RED
    Write-Output ("ERROR - missing some of current backups, sending email to $recipients "+(Get-Date -Format T)) | Out-File "$globallog" -Append
    SendEmialOnError $recipients $body
}

} 

}

#-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#Выполняем скрипт, при этом, если одна из ф-ций не нужна, можно заккоментировать строку и это не повлияет на другие ф-ции

Write-Host "Script started" -ForegroundColor Yellow
Write-Output ("Start "+(Get-Date -Format D)) | Out-File "$globallog" -Append

& $PoshVerCheck
& $RagentCheck
& $RasCheck 
& $DestCheck
& $RemOldArch
& $DoBackup

Write-Host "Script finished" -ForegroundColor Yellow
Write-Output ("Finish "+(Get-Date -Format D)) | Out-File "$globallog" -Append

#-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#Очищаем буфер с переменными

Remove-Variable -Name *  -Force -ErrorAction SilentlyContinue