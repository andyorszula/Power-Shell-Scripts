# Begin
###############################################################  
#                                                           
# Script to add AWS VPN connection.
# 
# Created by Andy Orszula - https://www.linkedin.com/in/orszula
#
# This script allows the implementer to create
# a VPN connection in AWS and then generates a 
# script to destroy it easily when done.  
# 
# It assumes you have created a VPN 
# connection previously on your hardware VPN
# device and then all that needs to be updated is the
# AWS Virtual Private Gateway Public IP and the
# pre-shared key.  This works well if you only 
# need the VPN setup temporarily such as in cases
# of a lab setup.  This script also assumes AWS PowerShell 
# tools have been installed and configured.
#
# Disclaimer:
#
# This sample script provided here is not supported 
# under any standard support program or service. This 
# script is provided AS IS without warranty of any kind. 
# I further disclaim all implied warranties including, 
# without limitation, any implied warranties of 
# merchantability or of fitness for a particular purpose. 
# The entire risk arising out of the use or performance 
# of this sample script and documentation remains with
# you. In no event shall its author, or anyone else 
# involved in the creation, production, or delivery 
# of the script be liable for any damages whatsoever
# (including, without limitation, damages for loss 
# of business profits, business interruption, loss 
# of business information, or other pecuniary loss) 
# arising out of the use of or inability to use the
# sample script or documentation, even if it has 
# been advised of the possibility of such damages.
#  
############################################################


Set-AWSCredentials -ProfileName default
Set-DefaultAWSRegion -Region us-east-1

# Function to retrieve or enter public IP

function Get-ExternalIP{
Try{
(Invoke-WebRequest ifconfig.me/ip).Content
}
catch
{
Write-Host "We were unable to retrieve your External IP. Please enter it now."
$GCIP = Read-host 
return $GCIP
}
}

#Function to Select your VPC

function Select-VPC {

    $ArrVPC= Get-EC2Vpc | select VpcID,CidrBlock 
    For( $i = 0; $i -lt $ArrVPC.Count; $i++ ) 
    
    {
         $x = $x + 1 
         write-host $x"." $ArrVPC[$i].VpcId $ArrVPC[$i].CidrBlock
                  
    }

    Write-host "Please Select your VPC by line number."
    $SelVPC = Read-Host
    $iVPC = $SelVPC - 1
    $VPCID = $ArrVPC[$iVPC].VpcId
    Write-Host "You selected $VPCID"
    $VPCID = $VPCID -replace '\s',''
    return $VPCID
  
}

function Select-Subnet {

    $ArrSN= Get-EC2Subnet | where {$_.VpcId -eq $VPCID} | select SubnetId,CidrBlock  
    For( $i = 0; $i -lt $ArrSN.Count; $i++ ) 
    
    {
         $x = $x + 1 
         write-host $x"." $ArrSN[$i].SubnetId $ArrSN[$i].CidrBlock
                  
    }

    Write-host "Please Select your Subnet to associate by line number."
    $SelSN = Read-Host
    $iSN = $SelSN - 1
    $SNID = $ArrSN[$iSN].SubnetID
    write-host
    Write-Host "You selected $SNID"
    $SNID = $SNID -replace '\s',''
    return $SNID
  
}

#function to Create Customer Gateway

function Create-CGW($GCIP) {

$CGWID = New-EC2CustomerGateway -Type ipsec.1 -PublicIp $GCIP | select CustomerGatewayId | ft -HideTableHeaders | Out-String
$CGWID = $CGWID -replace '\s',''
return $CGWID 

}



#function to create and Add VPN Gateway

function Create-VGW($VPCID){

$VGW = New-EC2VpnGateway -Type ipsec.1 | select VpnGatewayId | ft -HideTableHeaders | out-string
$VGW = $VGW -replace '\s',''
Add-EC2VpnGateway -VpcId $VPCID -VpnGatewayId $VGW | Out-Null
return $VGW

}

function Create-VPN {

New-EC2VpnConnection -Type ipsec.1 -CustomerGatewayId $CGWID -VpnGatewayId $VGW -Options_StaticRoutesOnly $true | select CustomerGatewayConfiguration

}



#Retrieve or enter Public IP
Write-host
Write-host "Retrieving your public IP"

$GCIP = Get-ExternalIP
$GCIP = $GCIP -replace '\s',''
write-host
write-host "IP is $GCIP"
write-Host
$VPCID = Select-VPC
write-host
$CGWID= Create-CGW($GCIP)
$VGW = Create-VGW($VPCID)

#Create VPN Connection
$VPNXML = Create-VPN

#Get Pre-Shared Keys, AWS Virtual Private Gateway Public IP, and VPN ConnectionID
$strVPNXMLcontent = $VPNXML.CustomerGatewayConfiguration | out-string
$XML = New-Object -TypeName System.Xml.XmlDocument
$xml.LoadXml($strVPNXMLcontent)
$KEYS = $xml.vpn_connection.ipsec_tunnel.ike.pre_shared_key | Out-String
$TUNIPs = $xml.vpn_connection.ipsec_tunnel.vpn_gateway.tunnel_outside_address.ip_address | Out-String
$VPNID = $xml.vpn_connection.id


#Add VPN Route to the inside subnet on local network and save XML Output for later
Write-host "What is the inside subnet subnet on local network in CIDR notation (e.g. 192.168.1.0/24)?"
$CIDRBLOCK = Read-Host
$VPNRoute = $xml.vpn_connection.id | Out-String
$VPNRoute = $VPNRoute -replace '\s',''
New-EC2VpnConnectionRoute -VpnConnectionId $VPNRoute -DestinationCidrBlock $CIDRBLOCK | Out-Null

#Create Route Table to attach to VPC and add route forward to Virtual Private Gateway

$VPNRoute = New-EC2RouteTable -VpcId  $VPCID | select RouteTableId | ft -HideTableHeaders | Out-String
$VPNRoute = $VPNRoute -replace '\s',''
Start-Sleep -s 30
New-EC2Route -RouteTableId $VPNRoute -DestinationCidrBlock $CIDRBLOCK -GatewayId $VGW

#Associate Subnet with Route Table
$SNID = Select-Subnet
Register-EC2RouteTable -RouteTableId $VPNRoute -SubnetId $SNID | Out-Null

#Output Pre-Shared Keys and AWS Virtual Private Gateway Public IP

$ArrVpnInfo = $KEYS + $TUNIPs
$Arrinfo = ($ArrVpnInfo -split '[\r\n]') |? {$_}  
    For( $i = 0; $i -lt 2; $i++ ) 
    
    {
         $x = $i + 1 
         write-host
         write-host Key Tunnel Pair $x is:
         write-host $ArrInfo[$i]
         write-host $ArrInfo[$i+2]
                 
    }

#Association ID from Route Table

$ASSID = Get-EC2Routetable -RouteTableId $VPNRoute | Select Associations | ft -HideTableHeaders | Out-String
$ASSID = $ASSID = $ASSID -replace '\s',''
$ASSID = $ASSID = $ASSID -replace '{',''
$ASSID = $ASSID = $ASSID -replace '}',''

#Create Undo Powershell Script

Write-Host
Write-Host "CREATE UNDO SCRIPT"
Write-Host "The script will the create and name the file:"
Write-Host "Enter Path to Folder:" 
$path = Read-Host
$file = "Remove-" + $VPNID + ".ps1"
New-Item -path $path -Name $file -ItemType file | Out-Null

Add-Content $path"\"$file "Set-AWSCredentials -ProfileName default"
Add-Content $path"\"$file "Set-DefaultAWSRegion -Region us-east-1"
Add-Content $path"\"$file "Remove-EC2VpnConnection -VpnConnectionId $VPNID"
Add-Content $path"\"$file "Dismount-EC2VpnGateway -VpnGatewayId $VGW -VpcId $VPCID"
Add-Content $path"\"$file "Remove-EC2VpnGateway -VpnGatewayId $VGW"
Add-Content $path"\"$file "Remove-EC2CustomerGateway -CustomerGatewayId $CGWID"
Add-Content $path"\"$file "Remove-EC2Route -RouteTableId $VPNRoute -DestinationCidrBlock $CIDRBLOCK"
Add-Content $path"\"$file "Unregister-EC2RouteTable -AssociationId $ASSID"
Add-Content $path"\"$file "Remove-EC2RouteTable -RouteTableId $VPNRoute"

write-host Path to file is $path"\"$file

# The End