function Get-CorsHeaders {
  param([Parameter(Mandatory)] $Request)

  $allowedOrigin = $env:ALLOWED_ORIGIN
  $requestOrigin = $Request.Headers["Origin"]

  $headers = @{
    "Access-Control-Allow-Methods" = "POST, OPTIONS"
    "Access-Control-Allow-Headers" = "Authorization, Content-Type"
  }

  if ($requestOrigin -and $requestOrigin -eq $allowedOrigin) {
    $headers["Access-Control-Allow-Origin"] = $allowedOrigin
  }

  return $headers
}

function Test-IsPreflightRequest {
  param([Parameter(Mandatory)] $Request)
  return $Request.Method -eq "OPTIONS"
}
