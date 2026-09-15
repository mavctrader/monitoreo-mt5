# Mini servidor local para probar el panel sin abrir index.html como
# archivo (file://), que causa problemas al cargar supabase-js dos veces.
# Uso: abrir PowerShell en esta carpeta y correr:  .\server.ps1
# Después abrir http://localhost:8000 en el navegador. Ctrl+C para parar.

$carpeta = $PSScriptRoot
$puerto = 8000
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$puerto/")
$listener.Start()
Write-Host "Sirviendo $carpeta en http://localhost:$puerto  (Ctrl+C para parar)"

$tipos = @{ ".html" = "text/html"; ".css" = "text/css"; ".js" = "application/javascript"; ".json" = "application/json" }

try {
    while ($listener.IsListening) {
        $contexto = $listener.GetContext()
        $ruta = $contexto.Request.Url.LocalPath
        if ($ruta -eq "/") { $ruta = "/index.html" }
        $archivo = Join-Path $carpeta $ruta.TrimStart("/")

        if (Test-Path $archivo -PathType Leaf) {
            $bytes = [System.IO.File]::ReadAllBytes($archivo)
            $ext = [System.IO.Path]::GetExtension($archivo)
            if ($tipos.ContainsKey($ext)) {
                $contexto.Response.ContentType = $tipos[$ext]
            }
            $contexto.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $contexto.Response.StatusCode = 404
        }
        $contexto.Response.Close()
    }
} finally {
    $listener.Stop()
}
