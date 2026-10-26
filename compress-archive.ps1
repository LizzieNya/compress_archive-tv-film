Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ----- CONFIG -----
$global:PixeldrainUser   = "" # Can be left blank; Pixeldrain only checks the API key after the colon
$global:PixeldrainApiKey = "YOUR_API_KEY"
$global:DefaultFolder    = (Get-Location).Path
$global:XzExe            = "xz.exe"
# -------------------

function Show-Error($msg) { [System.Windows.Forms.MessageBox]::Show($msg, "Error", "OK", "Error") | Out-Null }
function Show-Info($msg)  { [System.Windows.Forms.MessageBox]::Show($msg, "Info", "OK", "Information") | Out-Null }

function Get-AuthHeader() {
    $token = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($global:PixeldrainUser):$($global:PixeldrainApiKey)"))
    return @{ Authorization = "Basic $token" }
}

function Compress-Files($folder, $deleteOriginals) {
    $files = Get-ChildItem -Path (Join-Path $folder "*") -Include @("*.mp4","*.mkv") -File
    if (-not $files) { Show-Info "No mp4/mkv files found."; return }
    foreach ($f in $files) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $global:XzExe
        $psi.Arguments = "-9e -T0 --keep `"$($f.FullName)`""
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.WaitForExit()
        if ($deleteOriginals -and $p.ExitCode -eq 0) {
            Remove-Item -LiteralPath $f.FullName -Force
        }
    }
    Show-Info "Compression complete."
}

function Decompress-Files($folder) {
    $files = Get-ChildItem -Path (Join-Path $folder "*") -Include @("*.mp4.xz","*.mkv.xz") -File
    if (-not $files) { Show-Info "No .xz files found."; return }
    foreach ($f in $files) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $global:XzExe
        $psi.Arguments = "-d -T0 --keep `"$($f.FullName)`""
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.WaitForExit()
    }
    Show-Info "Decompression complete."
}

function Upload-To-Pixeldrain($filePath) {
    if (-not (Test-Path -LiteralPath $filePath)) { Show-Error "File not found: $filePath"; return }
    $headers = Get-AuthHeader
    $fileName = [uri]::EscapeDataString((Split-Path $filePath -Leaf))
    try {
        $resp = Invoke-RestMethod -Method Put -Uri "https://pixeldrain.com/api/file/$fileName" -Headers $headers -InFile $filePath -ContentType "application/octet-stream"
        if ($resp.id) {
            $url = "https://pixeldrain.com/u/$($resp.id)"
            [System.Windows.Forms.Clipboard]::SetText($url)
            Show-Info "Uploaded! Link copied to clipboard:`n$url"
            return $resp.id
        }
    } catch {
        Show-Error "Upload failed: $($_.Exception.Message)"
    }
}

function Download-From-Pixeldrain($fileId, $destFolder) {
    if (-not $fileId) { Show-Error "File ID required."; return }
    if (-not (Test-Path -LiteralPath $destFolder)) { New-Item -ItemType Directory -Path $destFolder | Out-Null }
    $headers = Get-AuthHeader
    try {
        $info = Invoke-RestMethod -Method Get -Uri "https://pixeldrain.com/api/file/$fileId/info" -Headers $headers
        $fileName = if ($info.name) { $info.name } else { "$fileId.bin" }
        $outFile = Join-Path $destFolder $fileName
        Invoke-RestMethod -Method Get -Uri "https://pixeldrain.com/api/file/$fileId" -Headers $headers -OutFile $outFile
        Show-Info "Downloaded to: $outFile"
    } catch {
        Show-Error "Download failed: $($_.Exception.Message)"
    }
}

# ----- UI -----
$form = New-Object System.Windows.Forms.Form
$form.Text = "XZ Batch Compress/Decompress with Pixeldrain"
$form.Size = New-Object System.Drawing.Size(520,320)
$form.StartPosition = "CenterScreen"

$lblFolder = New-Object System.Windows.Forms.Label
$lblFolder.Text = "Target Folder:"
$lblFolder.Location = New-Object System.Drawing.Point(10,20)
$lblFolder.AutoSize = $true
$form.Controls.Add($lblFolder)

$txtFolder = New-Object System.Windows.Forms.TextBox
$txtFolder.Text = $global:DefaultFolder
$txtFolder.Location = New-Object System.Drawing.Point(100,16)
$txtFolder.Size = New-Object System.Drawing.Size(300,20)
$form.Controls.Add($txtFolder)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "Browse"
$btnBrowse.Location = New-Object System.Drawing.Point(410,14)
$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dlg.ShowDialog() -eq "OK") { $txtFolder.Text = $dlg.SelectedPath }
})
$form.Controls.Add($btnBrowse)

$chkDelete = New-Object System.Windows.Forms.CheckBox
$chkDelete.Text = "Delete originals after compression"
$chkDelete.Location = New-Object System.Drawing.Point(10,50)
$chkDelete.AutoSize = $true
$form.Controls.Add($chkDelete)

$btnCompress = New-Object System.Windows.Forms.Button
$btnCompress.Text = "Compress (*.mp4/*.mkv)"
$btnCompress.Location = New-Object System.Drawing.Point(10,80)
$btnCompress.Size = New-Object System.Drawing.Size(180,30)
$btnCompress.Add_Click({
    Compress-Files $txtFolder.Text $chkDelete.Checked
})
$form.Controls.Add($btnCompress)

$btnDecompress = New-Object System.Windows.Forms.Button
$btnDecompress.Text = "Decompress (*.xz)"
$btnDecompress.Location = New-Object System.Drawing.Point(200,80)
$btnDecompress.Size = New-Object System.Drawing.Size(180,30)
$btnDecompress.Add_Click({
    Decompress-Files $txtFolder.Text
})
$form.Controls.Add($btnDecompress)

# Pixeldrain upload
$lblUpload = New-Object System.Windows.Forms.Label
$lblUpload.Text = "Upload a file to Pixeldrain:"
$lblUpload.Location = New-Object System.Drawing.Point(10,130)
$lblUpload.AutoSize = $true
$form.Controls.Add($lblUpload)

$txtUpload = New-Object System.Windows.Forms.TextBox
$txtUpload.Location = New-Object System.Drawing.Point(10,150)
$txtUpload.Size = New-Object System.Drawing.Size(390,20)
$form.Controls.Add($txtUpload)

$btnPickUpload = New-Object System.Windows.Forms.Button
$btnPickUpload.Text = "Pick File"
$btnPickUpload.Location = New-Object System.Drawing.Point(410,148)
$btnPickUpload.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "Video or XZ|*.mp4;*.mkv;*.xz|All|*.*"
    if ($dlg.ShowDialog() -eq "OK") { $txtUpload.Text = $dlg.FileName }
})
$form.Controls.Add($btnPickUpload)

$btnUpload = New-Object System.Windows.Forms.Button
$btnUpload.Text = "Upload"
$btnUpload.Location = New-Object System.Drawing.Point(10,175)
$btnUpload.Add_Click({
    Upload-To-Pixeldrain $txtUpload.Text | Out-Null
})
$form.Controls.Add($btnUpload)

# Pixeldrain download
$lblDownload = New-Object System.Windows.Forms.Label
$lblDownload.Text = "Download from Pixeldrain (file ID):"
$lblDownload.Location = New-Object System.Drawing.Point(10,210)
$lblDownload.AutoSize = $true
$form.Controls.Add($lblDownload)

$txtFileId = New-Object System.Windows.Forms.TextBox
$txtFileId.Location = New-Object System.Drawing.Point(10,230)
$txtFileId.Size = New-Object System.Drawing.Size(200,20)
$form.Controls.Add($txtFileId)

$lblDest = New-Object System.Windows.Forms.Label
$lblDest.Text = "Save to folder:"
$lblDest.Location = New-Object System.Drawing.Point(220,210)
$lblDest.AutoSize = $true
$form.Controls.Add($lblDest)

$txtDest = New-Object System.Windows.Forms.TextBox
$txtDest.Location = New-Object System.Drawing.Point(220,230)
$txtDest.Size = New-Object System.Drawing.Size(190,20)
$txtDest.Text = $global:DefaultFolder
$form.Controls.Add($txtDest)

$btnDownload = New-Object System.Windows.Forms.Button
$btnDownload.Text = "Download"
$btnDownload.Location = New-Object System.Drawing.Point(410,228)
$btnDownload.Add_Click({
    Download-From-Pixeldrain $txtFileId.Text $txtDest.Text
})
$form.Controls.Add($btnDownload)

$form.Topmost = $true
[void]$form.ShowDialog()
