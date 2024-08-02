local http = require "resty.http"
local cjson = require "cjson"

local UpstreamProxyHandler = {
  PRIORITY = 1000,
  VERSION = "1.0.9",
}

function UpstreamProxyHandler:access(conf)
  kong.log.debug("Plugin version: " .. self.VERSION)

  local client = http.new()

  -- Set timeout values
  client:set_timeouts(10000, 10000, 10000)

  -- Prepare headers
  local headers = kong.request.get_headers()
  headers["Host"] = conf.upstream_host

  -- Construct the full URL
  local full_url = conf.upstream_url .. kong.request.get_path_with_query()

  kong.log.debug("Upstream URL: " .. full_url)
  kong.log.debug("Request headers: " .. cjson.encode(headers))

  -- Attempt to establish a connection
  local ok, err = client:connect({
    scheme = "https",
    host = conf.upstream_host,
    port = 443,
    ssl_verify = false,
    proxy = "http://198.1.1.219:9001",
    ssl = {
      verify = false,
      server_name = conf.upstream_host
    }
  })

  if not ok then
    kong.log.err("Failed to connect: ", err)
    return kong.response.exit(500, "Failed to connect: " .. (err or "unknown error"))
  end

  kong.log.debug("Connection established")

  -- Send the request
  local res, err = client:request {
    method = kong.request.get_method(),
    path = kong.request.get_path_with_query(),
    headers = headers,
  }

  if not res then
    kong.log.err("Failed to send request: ", err)
    return kong.response.exit(500, "Failed to send request: " .. (err or "unknown error"))
  end

  kong.log.debug("Response status: " .. res.status)
  kong.log.debug("Response headers: " .. cjson.encode(res.headers))

  -- Read the response body
  local body, err = res:read_body()
  if not body then
    kong.log.err("Failed to read response body: ", err)
    return kong.response.exit(500, "Failed to read response body: " .. (err or "unknown error"))
  end

  -- Send the response back to the client
  kong.response.set_status(res.status)
  for k, v in pairs(res.headers) do
    kong.response.set_header(k, v)
  end
  kong.response.set_raw_body(body)

  kong.log.debug("Response body: " .. body)

  return kong.response.exit(res.status)
end

return UpstreamProxyHandler