# ============================================================
# PRINTER SWITCH 4.1
# MODO RESIDENTE - SEM JANELA DE POWERSHELL
# Atalho: CTRL + ALT + P
# ============================================================

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# 1. SOLICITAR ADMINISTRADOR SEM EXIBIR CONSOLE
# ------------------------------------------------------------

$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)

$isAdmin = $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {

    $argsLine = '-NoProfile -STA -ExecutionPolicy Bypass -File "' +
                $PSCommandPath + '"'

    Start-Process powershell.exe `
        -Verb RunAs `
        -WindowStyle Hidden `
        -ArgumentList $argsLine

    exit
}

# ------------------------------------------------------------
# 2. CARREGAR COMPONENTES
# ------------------------------------------------------------

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Import-Module PrintManagement -ErrorAction Stop

# ------------------------------------------------------------
# 3. CONFIGURACAO
# ------------------------------------------------------------

$script:ConfigDir = Join-Path $env:APPDATA "PrinterSwitch"
$script:ConfigPath = Join-Path $script:ConfigDir "config.json"

New-Item -ItemType Directory -Path $script:ConfigDir -Force |
    Out-Null

$script:Config = @{
    SelectedPrinter = ""
    States = @{}
}

if (Test-Path $script:ConfigPath) {

    try {

        $loaded = Get-Content $script:ConfigPath -Raw |
            ConvertFrom-Json

        if ($loaded.SelectedPrinter) {
            $script:Config.SelectedPrinter = [string]$loaded.SelectedPrinter
        }

        if ($loaded.States) {

            foreach ($property in $loaded.States.PSObject.Properties) {

                $script:Config.States[$property.Name] =
                    [string]$property.Value
            }
        }
    }
    catch {
        # Configuracao invalida: iniciar configuracao limpa.
    }
}

function Save-Config {

    $script:Config |
        ConvertTo-Json -Depth 5 |
        Set-Content -Path $script:ConfigPath -Encoding UTF8
}

# ------------------------------------------------------------
# 4. IDENTIFICAR IMPRESSORAS
# ------------------------------------------------------------

$printers = @(Get-Printer | Sort-Object Name)

if ($printers.Count -eq 0) {
    [System.Windows.Forms.MessageBox]::Show(
        "Nenhuma impressora instalada foi encontrada.",
        "PRINTER SWITCH"
    ) | Out-Null
    exit
}

$script:PrinterName = $script:Config.SelectedPrinter

if (-not ($printers | Where-Object {
    $_.Name -eq $script:PrinterName
})) {

    $defaultPrinter = Get-CimInstance Win32_Printer |
        Where-Object { $_.Default -eq $true } |
        Select-Object -First 1

    if ($defaultPrinter) {
        $script:PrinterName = $defaultPrinter.Name
    }
    else {
        $script:PrinterName = $printers[0].Name
    }
}

# Primeira utilizacao: bloqueada.
if (-not $script:Config.States.ContainsKey($script:PrinterName)) {
    $script:Config.States[$script:PrinterName] = "OFF"
}

$script:State = [string]$script:Config.States[$script:PrinterName]

if ($script:State -notin @("ON", "OFF")) {
    $script:State = "OFF"
}

# ------------------------------------------------------------
# 5. CONTROLAR PAUSA E RETOMADA
# ------------------------------------------------------------

function Set-SelectedPrinterState {

    param(
        [Parameter(Mandatory)]
        [ValidateSet("ON", "OFF")]
        [string]$NewState
    )

    $printerCim = Get-CimInstance Win32_Printer |
        Where-Object { $_.Name -eq $script:PrinterName } |
        Select-Object -First 1

    if (-not $printerCim) {
        throw "Impressora nao encontrada: $($script:PrinterName)"
    }

    if ($NewState -eq "OFF") {
        $method = "Pause"
    }
    else {
        $method = "Resume"
    }

    $result = Invoke-CimMethod `
        -InputObject $printerCim `
        -MethodName $method `
        -ErrorAction Stop

    if ($null -eq $result.ReturnValue -or
        $result.ReturnValue -ne 0) {

        throw "Falha ao executar $method. Codigo: $($result.ReturnValue)"
    }

    # Salvar somente depois da operacao aceita.
    $script:State = $NewState

    $script:Config.States[$script:PrinterName] = $NewState
    $script:Config.SelectedPrinter = $script:PrinterName

    Save-Config
}

# ------------------------------------------------------------
# 6. LIMPAR FILA ANTES DE LIBERAR
# ------------------------------------------------------------

function Clear-SelectedPrinterQueue {

    for ($attempt = 1; $attempt -le 5; $attempt++) {

        $jobs = @(
            Get-PrintJob -PrinterName $script:PrinterName `
                -ErrorAction Stop
        )

        if ($jobs.Count -eq 0) {
            return
        }

        foreach ($job in $jobs) {

            Remove-PrintJob `
                -PrinterName $script:PrinterName `
                -ID $job.ID `
                -ErrorAction Stop
        }

        Start-Sleep -Milliseconds 300
    }

    $remaining = @(
        Get-PrintJob -PrinterName $script:PrinterName `
            -ErrorAction Stop
    )

    if ($remaining.Count -gt 0) {
        throw "Nao foi possivel limpar completamente a fila."
    }
}

# ------------------------------------------------------------
# 7. CRIAR ICONE VERDE OU VERMELHO
# ------------------------------------------------------------

function Update-TrayAppearance {

    $color = if ($script:State -eq "ON") {
        [System.Drawing.Color]::FromArgb(22, 163, 74)
    }
    else {
        [System.Drawing.Color]::FromArgb(220, 38, 38)
    }

    $bitmap = New-Object System.Drawing.Bitmap 32, 32

    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

    $graphics.SmoothingMode =
        [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    $graphics.Clear([System.Drawing.Color]::Transparent)

    $brush = New-Object System.Drawing.SolidBrush $color

    $pen = New-Object System.Drawing.Pen(
        [System.Drawing.Color]::White, 2
    )

    $graphics.FillEllipse($brush, 3, 3, 26, 26)
    $graphics.DrawEllipse($pen, 3, 3, 26, 26)

    $handle = $bitmap.GetHicon()

    $newIcon = [System.Drawing.Icon]::FromHandle($handle).Clone()

    [PrinterNativeMethods]::DestroyIcon($handle) | Out-Null

    $graphics.Dispose()
    $brush.Dispose()
    $pen.Dispose()
    $bitmap.Dispose()

    $oldIcon = $script:Tray.Icon

    $script:Tray.Icon = $newIcon

    if ($oldIcon) {
        $oldIcon.Dispose()
    }

    $stateText = if ($script:State -eq "ON") {
        "LIBERADA"
    }
    else {
        "BLOQUEADA"
    }

    $tip = "PRINTER SWITCH: $stateText - $($script:PrinterName)"

    if ($tip.Length -gt 63) {
        $tip = $tip.Substring(0, 63)
    }

    $script:Tray.Text = $tip
}

# ------------------------------------------------------------
# 8. ATUALIZAR STATUS DO MENU
# ------------------------------------------------------------

function Show-Status {

    $stateText = if ($script:State -eq "ON") {
        "LIBERADA - VERDE"
    }
    else {
        "BLOQUEADA - VERMELHO"
    }

    $script:StatusItem.Text =
        "$($script:PrinterName) | $stateText"
}

# ------------------------------------------------------------
# 9. ALTERNAR BLOQUEIO
# ------------------------------------------------------------

function Toggle-SelectedPrinter {

    try {

        if ($script:State -eq "OFF") {

            # PRIMEIRO: LIMPAR FILA
            Clear-SelectedPrinterQueue

            # SEGUNDO: LIBERAR
            Set-SelectedPrinterState -NewState "ON"

            $script:Tray.ShowBalloonTip(
                1800,
                "PRINTER SWITCH",
                "Impressora liberada!",
                [System.Windows.Forms.ToolTipIcon]::Info
            )
        }
        else {

            # BLOQUEAR SEM LIMPAR
            Set-SelectedPrinterState -NewState "OFF"

            $script:Tray.ShowBalloonTip(
                1800,
                "PRINTER SWITCH",
                "Impressora bloqueada!",
                [System.Windows.Forms.ToolTipIcon]::Warning
            )
        }
    }
    catch {

        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "ERRO - PRINTER SWITCH",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }

    Update-TrayAppearance
    Show-Status
}

# ------------------------------------------------------------
# 10. SELECIONAR IMPRESSORA
# ------------------------------------------------------------

function Select-Printer {

    param([string]$Name)

    try {

        if ($Name -eq $script:PrinterName) {
            return
        }

        $null = Get-Printer -Name $Name -ErrorAction Stop

        $script:PrinterName = $Name

        if (-not $script:Config.States.ContainsKey($Name)) {
            $script:Config.States[$Name] = "OFF"
        }

        $remembered = [string]$script:Config.States[$Name]

        if ($remembered -notin @("ON", "OFF")) {
            $remembered = "OFF"
        }

        Set-SelectedPrinterState -NewState $remembered

        Rebuild-PrinterMenu
        Update-TrayAppearance
        Show-Status
    }
    catch {

        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "Erro ao selecionar impressora"
        ) | Out-Null
    }
}

# ------------------------------------------------------------
# 11. CONSULTAR FILA
# ------------------------------------------------------------

function Show-Queue {

    try {

        $jobs = @(
            Get-PrintJob -PrinterName $script:PrinterName `
                -ErrorAction Stop
        )

        if ($jobs.Count -eq 0) {
            $message = "A fila esta vazia."
        }
        else {

            $message = ($jobs | ForEach-Object {
                "Trabalho $($_.ID): $($_.DocumentName) - $($_.JobStatus)"
            }) -join "`r`n"
        }

        [System.Windows.Forms.MessageBox]::Show(
            $message,
            "Fila de impressao"
        ) | Out-Null
    }
    catch {

        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "Erro ao consultar fila"
        ) | Out-Null
    }
}

# ------------------------------------------------------------
# 12. HOTKEY GLOBAL E JANELA INVISIVEL
# ------------------------------------------------------------

$hotkeyCode = @'
using System;
using System.Windows.Forms;
using System.Runtime.InteropServices;

public class PrinterHotkeyForm : Form
{
    public event EventHandler HotkeyPressed;

    private const int WM_HOTKEY = 0x0312;
    private const int HOTKEY_ID = 1;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(
        IntPtr hWnd, int id, uint modifiers, uint key
    );

    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(
        IntPtr hWnd, int id
    );

    public PrinterHotkeyForm()
    {
        this.ShowInTaskbar = false;
        this.WindowState = FormWindowState.Minimized;
        this.FormBorderStyle = FormBorderStyle.FixedToolWindow;
        this.Opacity = 0;
        this.Text = "PRINTER SWITCH";
    }

    public bool RegisterGlobalHotkey()
    {
        // CTRL + ALT + P + MOD_NOREPEAT
        return RegisterHotKey(
            this.Handle, HOTKEY_ID,
            0x0001 | 0x0002 | 0x4000,
            0x50
        );
    }

    public void UnregisterGlobalHotkey()
    {
        if (this.IsHandleCreated) {
            UnregisterHotKey(this.Handle, HOTKEY_ID);
        }
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_HOTKEY &&
            m.WParam.ToInt32() == HOTKEY_ID)
        {
            EventHandler handler = HotkeyPressed;

            if (handler != null) {
                handler(this, EventArgs.Empty);
            }
        }

        base.WndProc(ref m);
    }
}

public static class PrinterNativeMethods
{
    [DllImport("user32.dll")]
    public static extern bool DestroyIcon(IntPtr handle);
}
'@

Add-Type -TypeDefinition $hotkeyCode `
    -ReferencedAssemblies System.Windows.Forms.dll

# ------------------------------------------------------------
# 13. MENU DA BANDEJA
# ------------------------------------------------------------

$script:Menu = New-Object System.Windows.Forms.ContextMenuStrip

$script:StatusItem =
    New-Object System.Windows.Forms.ToolStripMenuItem

$script:StatusItem.Enabled = $false

[void]$script:Menu.Items.Add($script:StatusItem)

[void]$script:Menu.Items.Add(
    (New-Object System.Windows.Forms.ToolStripSeparator)
)

$script:ToggleItem =
    New-Object System.Windows.Forms.ToolStripMenuItem(
        "Alternar bloqueio (Ctrl+Alt+P)"
    )

$script:ToggleItem.add_Click({
    Toggle-SelectedPrinter
})

[void]$script:Menu.Items.Add($script:ToggleItem)

$script:PrinterMenu =
    New-Object System.Windows.Forms.ToolStripMenuItem(
        "Selecionar impressora"
    )

[void]$script:Menu.Items.Add($script:PrinterMenu)

function Rebuild-PrinterMenu {

    $script:PrinterMenu.DropDownItems.Clear()

    foreach ($printer in (Get-Printer | Sort-Object Name)) {

        $printerNameLocal = [string]$printer.Name

        $item = New-Object System.Windows.Forms.ToolStripMenuItem(
            $printerNameLocal
        )

        $item.Checked = ($printerNameLocal -eq $script:PrinterName)

        $item.add_Click({
            Select-Printer -Name $printerNameLocal
        }.GetNewClosure())

        [void]$script:PrinterMenu.DropDownItems.Add($item)
    }
}

$script:QueueItem =
    New-Object System.Windows.Forms.ToolStripMenuItem(
        "Mostrar fila de impressao"
    )

$script:QueueItem.add_Click({
    Show-Queue
})

[void]$script:Menu.Items.Add($script:QueueItem)

[void]$script:Menu.Items.Add(
    (New-Object System.Windows.Forms.ToolStripSeparator)
)

$script:ExitItem =
    New-Object System.Windows.Forms.ToolStripMenuItem("Sair")

[void]$script:Menu.Items.Add($script:ExitItem)

# ------------------------------------------------------------
# 14. ICONE DA BANDEJA
# ------------------------------------------------------------

$script:Tray = New-Object System.Windows.Forms.NotifyIcon

$script:Tray.Visible = $true
$script:Tray.ContextMenuStrip = $script:Menu

$script:Tray.add_DoubleClick({
    Toggle-SelectedPrinter
})

# ------------------------------------------------------------
# 15. CRIAR FORMULARIO OCULTO
# ------------------------------------------------------------

$script:Form = New-Object PrinterHotkeyForm

$script:Form.add_HotkeyPressed({
    Toggle-SelectedPrinter
})

$script:ExitItem.add_Click({
    [System.Windows.Forms.Application]::Exit()
})

$script:Form.Show()
$script:Form.Hide()

# ------------------------------------------------------------
# 16. APLICAR ESTADO MEMORIZADO
# ------------------------------------------------------------

try {

    Set-SelectedPrinterState -NewState $script:State

}
catch {

    [System.Windows.Forms.MessageBox]::Show(
        "Nao foi possivel aplicar o estado salvo.`n`n$($_.Exception.Message)",
        "PRINTER SWITCH"
    ) | Out-Null

    $script:Tray.Visible = $false
    exit
}

Rebuild-PrinterMenu
Update-TrayAppearance
Show-Status

# ------------------------------------------------------------
# 17. REGISTRAR ATALHO
# ------------------------------------------------------------

if (-not $script:Form.RegisterGlobalHotkey()) {

    $errorCode =
        [Runtime.InteropServices.Marshal]::GetLastWin32Error()

    [System.Windows.Forms.MessageBox]::Show(
        "Nao foi possivel registrar CTRL + ALT + P.`nCodigo: $errorCode",
        "PRINTER SWITCH"
    ) | Out-Null

    $script:Tray.Visible = $false
    exit
}

# ------------------------------------------------------------
# 18. INICIAR MODO RESIDENTE
# ------------------------------------------------------------

$script:Tray.ShowBalloonTip(
    2500,
    "PRINTER SWITCH 4.1",
    "Aplicativo ativo em segundo plano.",
    [System.Windows.Forms.ToolTipIcon]::Info
)

# Loop de mensagens sem janela de console.
try {
    [System.Windows.Forms.Application]::Run()
}
finally {

    try {
        $script:Form.UnregisterGlobalHotkey()
    }
    catch {}

    $script:Tray.Visible = $false
    $script:Tray.Dispose()
    $script:Menu.Dispose()
    $script:Form.Dispose()
}
