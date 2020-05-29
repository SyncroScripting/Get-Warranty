Import-Module $env:SyncroModule -WarningAction SilentlyContinue

#######  set up steps  configure VARS ######
# Enter your Company information here:
$subdomain = "YOUR SUBDOMAIN HERE"
$email = "YOUR EMAIL HERE"
# This is the number of minutes you want added to the ticket
$TicketTime = 10
# Very important to change for each script
$body = "Warranty checkup for $env:computername" 
# Addicional
$workdir = "c:\temp\"
#######  END ######

# Create Ticket and get the ticket number
# remove per syncro 
$varTicket = Create-Syncro-Ticket -SubDomain $SubDomain -Subject "Warranty checkup for $env:computername" -IssueType "Regular Maintenance" -Status "New"
$ticket = $varTicket.ticket.number

# Add time to ticket
$startAt = (Get-Date).AddMinutes(-30).toString("o")
Create-Syncro-Ticket-TimerEntry -SubDomain $SubDomain -TicketIdOrNumber $ticket -StartTime $startAt -DurationMinutes $TicketTime -Notes "Warranty end date: $EndDate." -UserIdOrEmail "$email"

# Add ticket notes
Create-Syncro-Ticket-Comment -SubDomain $SubDomain -TicketIdOrNumber $ticket -Subject "Warranty Checkup" -Body "$body" -Hidden $False -DoNotEmail $True


# Preferred Date Format "MM-dd-y" or "yyyy-MM-dd" or whatever other format you want to display in the syncro custom fields.
$mydatepref = "MM-dd-y"

# Get Service Tag
[String]$ServiceTags = $(Get-WmiObject -Class "Win32_Bios").SerialNumber

# Get Manufacturer
$mfg = Get-WmiObject -Class Win32_BIOS | Select-Object -expand Manufacturer

#Uncomment for diagnostics
#Write-Host $ServiceTags
#Write-Host $mfg

# Dell Section
if ($mfg -eq 'Dell Inc.')
{
	#Get OAuth2 Token
    $AuthURI = "https://apigtwb2c.us.dell.com/auth/oauth/v2/token"
    #Enter your dell ClientID and Client_Secret separated by a colon
    $OAuth = "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX:XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
    $Bytes = [System.Text.Encoding]::ASCII.GetBytes($OAuth)
    $EncodedOAuth = [Convert]::ToBase64String($Bytes)
    $Headers = @{ }
    $Headers.Add("authorization", "Basic $EncodedOAuth")
    $Authbody = 'grant_type=client_credentials'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Try 
    {
        $AuthResult = Invoke-RESTMethod -Method Post -Uri $AuthURI -Body $AuthBody -Headers $Headers
        $Global:token = $AuthResult.access_token
    }
    Catch 
    {
        $ErrorMessage = $Error[0]
        Write-Error $ErrorMessage
        BREAK        
    }
    Write-Host "Access Token is: $token`n"
# End OAuth Token Phase

    $headers = @{"Accept" = "application/json" }
    $headers.Add("Authorization", "Bearer $token")

    $params = @{ }
    $params = @{servicetags = $servicetags; Method = "GET" }

    $Global:response = Invoke-RestMethod -Uri "https://apigtwb2c.us.dell.com/PROD/sbil/eapi/v5/asset-entitlements" -Headers $headers -Body $params -Method Get -ContentType "application/json"

    foreach ($Record in $response) 
    {
        $servicetag = $Record.servicetag
        $Json = $Record | ConvertTo-Json
        $Record = $Json | ConvertFrom-Json 
        #Response Fields
        
        $Device = $Record.productLineDescription
        $Shipdate = $Record.shipDate
        $Shipdate2 = $Shipdate | Get-Date -f $mydatepref
        $EndDate = ($Record.entitlements | Select -Last 1).endDate
        $Support = ($Record.entitlements | Select -Last 1).serviceLevelDescription
        $EndDate = $EndDate | Get-Date -f $mydatepref
        #Optional Other Data Fields
        #$FieldID = $Record.id
        #$orderBuild = $Record.orderBuild
        #$productCode = $Record.productCode
        #$localChannel = $Record.localChannel
        #$productId = $Record.productId
        #$productLineDescription = $Record.productLineDescription
        #$productFamily = $Record.productFamily
        #$productLobDescription = $Record.productLobDescription
        #$countryCode = $Record.countryCode
        

        $today = get-date
        Set-Asset-Field -Subdomain $SubDomain -Name "WarrantyStartDate" -Value $Shipdate2
        Set-Asset-Field -Subdomain $SubDomain -Name "WarrantyEndDate" -Value $EndDate
        Set-Asset-Field -Subdomain $SubDomain -Name "WarrantyType" -Value $Support
        #Set-Asset-Field -Subdomain $SubDomain -Name "ShipDate" -Value $Shipdate2
        
        Write-Host "Shipped: $Shipdate2"
        Write-Host -ForegroundColor White -BackgroundColor "DarkRed" $Computer
        Write-Host "Service Tag   : $servicetag"
        Write-Host "Model         : $Device"
        # Uncomment for Diagnostics on Optional Fields
        #Write-Host "FieldID     : $FieldID"
        #Write-Host "Order Build : $orderBuild"
        #Write-Host "Product Code: $productCode"
        
        if ($today -ge $EndDate) { Write-Host -NoNewLine "Warranty Exp. : $EndDate  "; Write-Host -ForegroundColor "Yellow" "[WARRANTY EXPIRED]"; Write-Host "Support: $Support" }
        else { Write-Host "Warranty Exp. : $EndDate"; Write-Host "Support: $Support"; Write-Host "Shipdate: $Shipdate"} 
        if (!($ClearEMS)) 
        {
            $i = 0
            foreach ($Item in ($($WarrantyInfo.entitlements.serviceLevelDescription | select -Unique | Sort-Object -Descending)))
            {
                $i++
                Write-Host -NoNewLine "Service Level : $Item`n"
            }

        }
        else 
        {
            $i = 0
            foreach ($Item in ($($WarrantyInfo.entitlements.serviceLevelDescription | select -Unique | Sort-Object -Descending)))
            {
                $i++
                Write-Host "Service Level : $Item`n"
            }
        }
    }
	
	#Close Ticket
	# Update-Syncro-Ticket -SubDomain $SubDomain -TicketIdOrNumber $ticket -Status "Resolved" #-CustomFieldName "Automation Results" -CustomFieldValue "Completed"

	#Change status to Resolved/reference ticket elsewhere
	Update-Syncro-Ticket -SubDomain $SubDomain -TicketIdOrNumber $ticket -Status "Resolved"
	Exit 0
}


# Lenovo Section
if ($mfg -eq 'Lenovo') 
{
    $today = Get-Date -Format yyyy-MM-dd
    $APIURL = "https://ibase.lenovo.com/POIRequest.aspx"
    $SourceXML = "xml=<wiInputForm source='ibase'><id>LSC3</id><pw>IBA4LSC3</pw><product></product><serial>$ServiceTags</serial><wiOptions><machine/><parts/><service/><upma/><entitle/></wiOptions></wiInputForm>"
    $Req = Invoke-RestMethod -Uri $APIURL -Method POST -Body $SourceXML -ContentType 'application/x-www-form-urlencoded'
    if ($req.wiOutputForm) 
    {
        $warlatest = $Req.wiOutputForm.warrantyInfo.serviceInfo.wed | sort-object | select-object -last 1 
        $WarrantyState = if ($warlatest -le $today) { "Expired" } else { "OK" }
        $Startdate = $Req.wiOutputForm.warrantyInfo.serviceInfo.warstart | sort-object -Descending | select-object -last 1 | Get-Date -f $mydatepref
        $Description = $Req.wiOutputForm.warrantyInfo.serviceInfo.sdfDesc
        $EndDate = $Req.wiOutputForm.warrantyInfo.serviceInfo.wed | sort-object | select-object -last 1 | Get-Date -f $mydatepref
        
        
        Set-Asset-Field -Subdomain $SubDomain -Name "WarrantyStartDate" -Value $Startdate
        Set-Asset-Field -Subdomain $SubDomain -Name "WarrantyEndDate" -Value $EndDate
        Set-Asset-Field -Subdomain $SubDomain -Name "WarrantyType" -Value $Description 
        $WarObj = [PSCustomObject]@{
            'Serial'                = $Req.wiOutputForm.warrantyInfo.machineinfo.serial
            'Warranty Product name' = $Req.wiOutputForm.warrantyInfo.machineinfo.productname -join "`n"
            'StartDate'             = $Req.wiOutputForm.warrantyInfo.serviceInfo.warstart | sort-object -Descending | select-object -last 1
            'EndDate'               = $Req.wiOutputForm.warrantyInfo.serviceInfo.wed | sort-object | select-object -last 1
            'Warranty Status'       = $WarrantyState
            'Client'                = $Client
            'Description'           = $Req.wiOutputForm.warrantyInfo.serviceInfo.sdfDesc
        }
        
    }
    else 
    {
        $WarObj = [PSCustomObject]@{
            'Serial'                = $SourceDevice
            'Warranty Product name' = 'Could not get warranty information'
            'StartDate'             = $null
            'EndDate'               = $null
            'Warranty Status'       = 'Could not get warranty information'
            'Client'                = $Client
            'Description'           = $null
        }
    }
    return $WarObj
	
	#Close Ticket
	# Update-Syncro-Ticket -SubDomain $SubDomain -TicketIdOrNumber $ticket -Status "Resolved" #-CustomFieldName "Automation Results" -CustomFieldValue "Completed"

	#Change status to Resolved/reference ticket elsewhere
	Update-Syncro-Ticket -SubDomain $SubDomain -TicketIdOrNumber $ticket -Status "Resolved"
	Exit 0
}


# Microsoft Section
if ($mfg -eq 'Microsoft Corporation') 
{
    $body = ConvertTo-Json @{
        sku          = "Surface_"
        SerialNumber = $ServiceTags
        ForceRefresh = $false
    }
    $today = Get-Date -Format yyyy-MM-dd
    $PublicKey = Invoke-RestMethod -Uri 'https://surfacewarrantyservice.azurewebsites.net/api/key' -Method Get
    $AesCSP = New-Object System.Security.Cryptography.AesCryptoServiceProvider 
    $AesCSP.GenerateIV()
    $AesCSP.GenerateKey()
    $AESIVString = [System.Convert]::ToBase64String($AesCSP.IV)
    $AESKeyString = [System.Convert]::ToBase64String($AesCSP.Key)
    $AesKeyPair = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$AESIVString,$AESKeyString"))
    $bodybytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $bodyenc = [System.Convert]::ToBase64String($AesCSP.CreateEncryptor().TransformFinalBlock($bodybytes, 0, $bodybytes.Length))
    $RSA = New-Object System.Security.Cryptography.RSACryptoServiceProvider
    $RSA.ImportCspBlob([System.Convert]::FromBase64String($PublicKey))
    $EncKey = [System.Convert]::ToBase64String($rsa.Encrypt([System.Text.Encoding]::UTF8.GetBytes($AesKeyPair), $false))
     
    $FullBody = @{
        Data = $bodyenc
        Key  = $EncKey
    } | ConvertTo-Json
     
    $WarReq = Invoke-RestMethod -uri "https://surfacewarrantyservice.azurewebsites.net/api/v2/warranty" -Method POST -body $FullBody -ContentType "application/json"
    if ($WarReq.warranties) 
    {
        $WarrantyState = foreach ($War in ($WarReq.warranties.effectiveenddate -split 'T')[0])
        {
            if ($War -le $today) { "Expired" } else { "OK" }
        $Startdate = (($WarReq.warranties.effectivestartdate | sort-object -Descending | select-object -last 1) -split 'T')[0]  | Get-Date -f $mydatepref
        $EndDate = (($WarReq.warranties.effectiveenddate | sort-object | select-object -last 1) -split 'T')[0] | Get-Date -f $mydatepref
        $Description = $WarReq.warranties.name -join "`n"
        Set-Asset-Field -Subdomain $SubDomain -Name "WarrantyStartDate" -Value $Startdate
        Set-Asset-Field -Subdomain $SubDomain -Name "WarrantyEndDate" -Value $EndDate
        Set-Asset-Field -Subdomain $SubDomain -Name "WarrantyType" -Value $Description
        
        }
        $WarObj = [PSCustomObject]@{
            'Serial'                = $ServiceTags
            'Warranty Product name' = $WarReq.warranties.name -join "`n"
            'StartDate'             = (($WarReq.warranties.effectivestartdate | sort-object -Descending | select-object -last 1) -split 'T')[0]
            'EndDate'               = (($WarReq.warranties.effectiveenddate | sort-object | select-object -last 1) -split 'T')[0]
            'Warranty Status'       = $WarrantyState
            'Client'                = $Client
        }
    }
    else 
    {
        $WarObj = [PSCustomObject]@{
            'Serial'                = $ServiceTags
            'Warranty Product name' = 'Could not get warranty information'
            'StartDate'             = $null
            'EndDate'               = $null
            'Warranty Status'       = 'Could not get warranty information'
            'Client'                = $Client
        }
    }
    return $WarObj
	
	#Close Ticket
	# Update-Syncro-Ticket -SubDomain $SubDomain -TicketIdOrNumber $ticket -Status "Resolved" #-CustomFieldName "Automation Results" -CustomFieldValue "Completed"

	#Change status to Resolved/reference ticket elsewhere
	Update-Syncro-Ticket -SubDomain $SubDomain -TicketIdOrNumber $ticket -Status "Resolved"
	Exit 0
}

if (($mfg -eq 'Hewlett-Packard') -or ($mfg -eq 'HP')) 
{

	$MWSID = (invoke-restmethod -uri 'https://support.hp.com/us-en/checkwarranty/multipleproducts/' -SessionVariable 'session' -Method get) -match '.*mwsid":"(?<wssid>.*)".*'
    $HPBody = " { `"gRecaptchaResponse`":`"`", `"obligationServiceRequests`":[ { `"serialNumber`":`"$ServiceTags`", `"isoCountryCde`":`"US`", `"lc`":`"EN`", `"cc`":`"US`", `"modelNumber`":null }] }"
 
    $HPReq = Invoke-RestMethod -Uri "https://support.hp.com/hp-pps-services/os/multiWarranty?ssid=$($matches.wssid)" -WebSession $session -Method "POST" -ContentType "application/json" -Body $HPbody
    if ($HPreq.productWarrantyDetailsVO.warrantyResultList.obligationStartDate) 
    {
        $Startdate = $hpreq.productWarrantyDetailsVO.warrantyResultList.obligationStartDate | sort-object | select-object -last 1 | Get-Date -f $mydatepref
        $EndDate = $hpreq.productWarrantyDetailsVO.warrantyResultList.obligationEndDate | sort-object | select-object -last 1 | Get-Date -f $mydatepref
        $Description = $hpreq.productWarrantyDetailsVO.warrantyResultList.warrantyType | Out-String
        Set-Asset-Field -Subdomain $SubDomain -Name "WarrantyStartDate" -Value $Startdate
        Set-Asset-Field -Subdomain $SubDomain -Name "WarrantyEndDate" -Value $EndDate
        Set-Asset-Field -Subdomain $SubDomain -Name "WarrantyType" -Value $Description
        $WarObj = [PSCustomObject]@{
            'Serial'                = $ServiceTags
            'Warranty Product name' = $hpreq.productWarrantyDetailsVO.warrantyResultList.warrantyType | Out-String
            'StartDate'             = $hpreq.productWarrantyDetailsVO.warrantyResultList.obligationStartDate | sort-object | select-object -last 1
            'EndDate'               = $hpreq.productWarrantyDetailsVO.warrantyResultList.obligationEndDate | sort-object | select-object -last 1
            'Warranty Status'       = $hpreq.productWarrantyDetailsVO.obligationStatus
            'Client'                = $Client
        }
    }
    else 
    {
        $WarObj = [PSCustomObject]@{
            'Serial'                = $ServiceTags
            'Warranty Product name' = 'Could not get warranty information'
            'StartDate'             = $null
            'EndDate'               = $null
            'Warranty Status'       = 'Could not get warranty information'
            'Client'                = $Client
        }
    }
    return $WarObj
	
	#Close Ticket
	# Update-Syncro-Ticket -SubDomain $SubDomain -TicketIdOrNumber $ticket -Status "Resolved" #-CustomFieldName "Automation Results" -CustomFieldValue "Completed"

	#Change status to Resolved/reference ticket elsewhere
	Update-Syncro-Ticket -SubDomain $SubDomain -TicketIdOrNumber $ticket -Status "Resolved"
	Exit 0
}

$Startdate = "Unknown Device"
$EndDate = "Unknown Device"
$Description = "Unknown Device"

Set-Asset-Field -Subdomain $SubDomain -Name "WarrantyStartDate" -Value $Startdate
Set-Asset-Field -Subdomain $SubDomain -Name "WarrantyEndDate" -Value $EndDate
Set-Asset-Field -Subdomain $SubDomain -Name "WarrantyType" -Value $Description


#Close Ticket
# Update-Syncro-Ticket -SubDomain $SubDomain -TicketIdOrNumber $ticket -Status "Resolved" #-CustomFieldName "Automation Results" -CustomFieldValue "Completed"

#Change status to Resolved/reference ticket elsewhere
Update-Syncro-Ticket -SubDomain $SubDomain -TicketIdOrNumber $ticket -Status "Resolved"
Exit 0