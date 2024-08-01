local http = require "resty.http"
local url = require "socket.url"

local UpstreamProxyHandler = {
  PRIORITY = 1000,
  VERSION = "1.0.4",
}

function UpstreamProxyHandler:access(conf)
  kong.log.debug("Plugin version: " .. self.VERSION)  -- Log the plugin version

  local client = http.new()

  -- Set timeout values and log them
  local connect_timeout = 20000
  local send_timeout = 20000
  local read_timeout = 20000

  kong.log.debug("Setting timeouts - connect: " .. connect_timeout .. "ms, send: " .. send_timeout .. "ms, read: " .. read_timeout .. "ms")

  client:set_timeouts(connect_timeout, send_timeout, read_timeout)

  -- Get the upstream URL from the service configuration
  local upstream_url = conf.upstream_url or (kong.service.protocol .. "://" .. kong.service.host .. ":" .. (kong.service.port or 80))

  -- Ensure correct path transformation
  local request_path = kong.request.get_path()

  -- Parse the upstream URL
  kong.log.debug("Request path: " .. request_path)
  local parsed_url = url.parse(upstream_url)
  parsed_url.path = parsed_url.path or ""
  parsed_url.path = parsed_url.path .. request_path

  -- Set up the proxy
  kong.log.debug("Setting proxy options")
  client:set_proxy_options({
    http_proxy = conf.proxy_url,
    https_proxy = conf.proxy_url,
  })

  -- Prepare headers
  local headers = kong.request.get_headers()
  headers["Host"] = parsed_url.host

  -- Construct the full URL
  local full_url = url.build(parsed_url)

  kong.log.debug("Upstream URL: " .. full_url)
  kong.log.debug("Proxy URL: " .. conf.proxy_url)

  -- Log headers
  kong.log.debug("Request headers: " .. require("cjson").encode(headers))

  -- Send the request through the proxy
  local res, err = client:request {
    method = kong.request.get_method(),
    url = full_url,
    body = kong.request.get_raw_body(),
    headers = headers,
    ssl_verify = false,  -- Equivalent to curl's -k option. Remove if you want to verify SSL.
  }

  if not res then
    kong.log.err("failed to request: ", err)
    return kong.response.exit(500, "Failed to send request: " .. (err or "unknown error"))
  end

  -- Log response details
  kong.log.debug("Response status: " .. res.status)
  kong.log.debug("Response headers: " .. require("cjson").encode(res.headers))

  -- Send the response back to the client
    kong.response.set_header(k, v)
  local body, err = res:read_body()
  if not body then
    kong.log.err("failed to read response body: ", err)
    return kong.response.exit(500, "Failed to read response body: " .. (err or "unknown error"))
  end

  kong.response.set_status(res.status)
  for k, v in pairs(res.headers) do
    kong.response.set_header(k, v)
  end

  kong.response.set_raw_body(body)

  -- Terminate further plugin execution
  return kong.response.exit(res.status)
end

return UpstreamProxyHandler
