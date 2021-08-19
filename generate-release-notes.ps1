
$VerbosePreference ='Continue'

function Get-Web-Request
{
    param
    (
        [string] $uri
    )
    Write-Host 'Get-Web-Request'
    $headers = @{
        Authorization = "[YOUR TOKEN]"
    }
    Write-Host $uri
    $response = Invoke-WebRequest -Uri $uri -Headers $headers
    $content = ConvertFrom-Json $response.Content
    $content
}

function Get-Latest-Tag
{
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Host 'Get-Release-Information'

    $result = Get-Web-Request "https://api.github.com/repos/[YOUR ORGANIZATION]/[YOUR REPOSITORY]/releases"

    $latest = $result[0].name
    
    $sourcebranch = $Env:BUILD_SOURCEBRANCH
    $notesversion = 'v' + $sourcebranch.Split('/')[-1] + '*'

    Write-Host 'Release notes version ' + $notesversion
    
    foreach($item in  $result){
        if($item.name -like $notesversion){
            $latest = $item.name
            break
        }
    }
    $latest
}

function Get-Commit-Information
{
    Write-Host 'Get-Commit-Information'
    $latestTag = Get-Latest-Tag
    Write-Host 'Latest release' + $latestTag
    if ($latestTag){
        $uri = "https://api.github.com/repos/[YOUR ORGANIZATION]/[YOUR REPOSITORY]/compare/$latestTag...$Env:BUILD_SOURCEBRANCH"
        $result = Get-Web-Request $uri
        $result.commits
    }
}

# Assembly reference for System.Web.HttpUtility
Add-Type -AssemblyName System.Web
function Build-Release-Notes
{
    Write-Host "Build-Release-Notes"
    $buildNumber = $env:BUILD_BUILDNUMBER

    $commits = Get-Commit-Information

    $html = "<br/>"
    $html += "<table class=`"confluenceTable`"><tr>"
    $html += "<th><h3>Build Definition: $Env:BUILD_DEFINITIONNAME </h3></th>"
    $html += "<th><h3>Build Number: <span style=`"color:rgb(54,179,126)`">" + $buildNumber + "</span></h3></th><th><h3>Branch: " + $Env:BUILD_SOURCEBRANCH + "</h3></th><th>Jira</th></tr>"

    if ($commits.Length -ne 0)
    {
        foreach ($item in $commits)
        {
            $title = $item.commit.message.Split([Environment]::NewLine) | Select-Object -First 1
            $encodedTitle = [System.Web.HttpUtility]::HtmlEncode($title)

            $html += "<tr>"
            $html += "<td>"
            $html += "<b>Date: </b> <span>" +  $item.commit.author.date  + "</span>"
            $html += "</td>"
            $html += "<td>"
            $html += "<a href=`"https://github.com/[YOUR ORGANIZATION]/[YOUR REPOSITORY]/commit/" + $item.sha + "`">" + $item.sha + "</a>"
            $html += "</td>"
            $html += "<td>"
            $html += "<b>Author</b> <span>" + $item.commit.author.name + "</span>"
            $html += "</td>"
            $html += "<td>"
            $html += "</td>"
            $html += "</tr>"
            $html += "<tr><td colspan=`"4`"><span>" + $encodedTitle + "</span></td></tr>"

            $latest_commit = $item.sha
        }

        $headers = @{
            Authorization = "[YOUR TOKEN]"
        }

        $uri_tag_commit = "https://api.github.com/[YOUR ORGANIZATION]/[YOUR REPOSITORY]/releases"

        $body = @{
            "tag_name" = "v" + $buildNumber;
            "target_commitish" = $latest_commit;
            "name" = "v" + $buildNumber;
            "body" = "CI Release";
        } | ConvertTo-Json

        $response = Invoke-RestMethod -Uri $uri_tag_commit -Body $body -Headers $headers -Method 'Post' -ContentType "application/json"
        Write-Host $response
    }
    $html += "</table>"

    $html
}

function Update-ConfluencePage
{
    param
    (
        [string] $Username,
        [string] $ApiToken,
        [string] $PageId,
        [string] $ContentToAppend
    )
    Write-Host "Update-ConfluencePage"
    $uri = "https://[YOUR ORGANIZATION].atlassian.net/wiki/rest/api/content/$PageId"

    $userpass = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Username + ":" + $ApiToken))

    $authHeader = @{"Authorization" = "Basic $userpass"}
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $page = Invoke-RestMethod -Uri "$($uri)?expand=body.storage,version" -Headers $authHeader -Method 'Get' -ContentType "application/json"

    Write-Host $page

    $changed = @{
        "body" = @{
            "storage" = @{
                "value" = $page.body.storage.value + $ContentToAppend;
                "representation" = "storage"
            }
        };
        "version" = @{
            "number" = $page.version.number + 1;
            "minorEdit" = $TRUE;
            "message" = "Updated by build PS"
        };
        "type" = "page";
        "title"=$page.title
    } | ConvertTo-Json
    $response = Invoke-RestMethod -Uri "$($uri)?expand=body.storage" -Body $changed -Headers $authHeader -Method 'Put' -ContentType "application/json"

    Write-Host $response
}

$releaseNotes = Build-Release-Notes

Write-Host $Env:CONFLUENCE_PAGE_ID

if($releaseNotes){
    # TODO transfer Username and APIToken to environment variables (secrets?)
    Update-ConfluencePage -Username "[YOUR USERNAME]" -ApiToken "[YOUR TOKEN]" -PageId [PAGE ID] -ContentToAppend $releaseNotes
}
