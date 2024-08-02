local http = require "resty.http"
local cjson = require "cjson"

local UpstreamProxyHandler = {
  PRIORITY = 1000,
  VERSION = "1.0.12",
}

function UpstreamProxyHandler:access(conf)
  kong.log.debug("Plugin version: " .. self.VERSION)

  local client = http.new()

  -- Set timeout values
  client:set_timeouts(10000, 10000, 10000)
  kong.log.debug("Timeouts set to 10000ms for connect, send, and read")

  -- Prepare headers
  local headers = kong.request.get_headers()
  headers["Host"] = conf.upstream_host
  kong.log.debug("Request headers prepared: " .. cjson.encode(headers))

  -- Construct the full URL
  local full_url = conf.upstream_url .. kong.request.get_path_with_query()
  kong.log.debug("Full URL constructed: " .. full_url)

  kong.log.debug("Request headers: " .. cjson.encode(headers))
  -- Attempt to establish a connection using proxy settings
  local connect_options = {
    scheme = "http",
    host = "198.1.1.219",
    port = 9001,
  }

  kong.log.debug("Connecting to proxy with options: " .. cjson.encode(connect_options))

  local ok, err = client:connect(connect_options)

  if not ok then
    kong.log.err("Failed to connect to proxy: ", err)
    return kong.response.exit(500, "Failed to connect to proxy: " .. (err or "unknown error"))
  end

  kong.log.debug("Connection to proxy established")

  -- Perform SSL handshake with the upstream server through the proxy
  kong.log.debug("Attempting SSL handshake with upstream host: " .. conf.upstream_host)
  
  local handshake_options = {
    verify = false,
    server_name = conf.upstream_host,  -- Ensure the correct SNI is used
    ssl_protocols = "TLSv1.2",  -- Specify SSL/TLS protocol
  }
  
  local ok, err = client:ssl_handshake(false, conf.upstream_host, false, handshake_options)

  if not ok then
    kong.log.err("Failed to perform SSL handshake: ", err)
    return kong.response.exit(500, "Failed to perform SSL handshake: " .. (err or "unknown error"))
  end

  kong.log.debug("SSL handshake completed")

  -- Send the request through the proxy
  kong.log.debug("Sending request through proxy to full URL: " .. full_url)
  local res, err = client:request {
    method = kong.request.get_method(),
    path = full_url,
    headers = headers,
  }

  if not res then
    kong.log.err("Failed to send request: ", err)
    return kong.response.exit(500, "Failed to send request: " .. (err or "unknown error"))
  end

  kong.log.debug("Received response with status: " .. res.status)
  kong.log.debug("Response headers: " .. cjson.encode(res.headers))

  -- Read the response body
  kong.log.debug("Reading response body")
  local body, err = res:read_body()
  if not body then
    kong.log.err("Failed to read response body: ", err)
    return kong.response.exit(500, "Failed to read response body: " .. (err or "unknown error"))
  end

  kong.log.debug("Response body read successfully")

  -- Send the response back to the client
  kong.log.debug("Setting response status: " .. res.status)
  kong.response.set_status(res.status)
  for k, v in pairs(res.headers) do
    kong.response.set_header(k, v)
  end
  kong.response.set_raw_body(body)

  kong.log.debug("Response body sent to client: " .. body)

  return kong.response.exit(res.status)
end

return UpstreamProxyHandler
