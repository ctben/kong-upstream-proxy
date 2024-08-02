local http = require "resty.http"
local cjson = require "cjson"

local UpstreamProxyHandler = {
  PRIORITY = 1000,
  VERSION = "1.0.5",
}

function UpstreamProxyHandler:access(conf)
  kong.log.debug("Plugin version: " .. self.VERSION)  -- Log the plugin version

  local client = http.new()

  -- Set timeout values
  client:set_timeouts(10000, 10000, 10000)  -- 10 second timeouts for connect, send, and read

  -- Set up the proxy
  client:set_proxy_options({
    http_proxy = conf.proxy_url,
    https_proxy = conf.proxy_url,
  })

  -- Prepare headers
  local headers = kong.request.get_headers()
  headers["Host"] = conf.upstream_host

  -- Construct the full URL
  local full_url = conf.upstream_url .. kong.request.get_path_with_query()

  kong.log.debug("Upstream URL: " .. full_url)
  kong.log.debug("Proxy URL: " .. conf.proxy_url)

  -- Log headers
  kong.log.debug("Request headers: " .. require("cjson").encode(headers))

  -- Send the request through the proxy
  local res, err = client:request {
    method = kong.request.get_method(),
    url = full_url,
    headers = headers,
    ssl_verify = false,  -- Equivalent to curl's -k option
    proxy = conf.proxy_url,
  }

  if not res then
    kong.log.err("Failed to send request: ", err)
    return kong.response.exit(500, "Failed to send request: " .. (err or "unknown error"))
  end

  -- Log response details
  kong.log.debug("Response status: " .. res.status)
  kong.log.debug("Response headers: " .. cjson.encode(res.headers))

  -- Handle redirects (similar to curl --location)
  local redirect_count = 0
  while res.status >= 300 and res.status < 400 and redirect_count < 5 do
    redirect_count = redirect_count + 1
    local new_url = res.headers["Location"]
    if not new_url then
      break
    end
    kong.log.debug("Following redirect to: " .. new_url)
    res, err = client:request {
      method = "GET",
      url = new_url,
      headers = headers,
      ssl_verify = false,
      proxy = conf.proxy_url,
    }
    if not res then
      kong.log.err("Failed to send request to redirect: ", err)
      return kong.response.exit(500, "Failed to send request to redirect: " .. (err or "unknown error"))
    end
  end

  -- Send the response back to the client
  kong.response.set_status(res.status)
  for k, v in pairs(res.headers) do
    kong.response.set_header(k, v)
  end
  
  local body, err = res:read_body()
  if not body then
    kong.log.err("Failed to read response body: ", err)
    return kong.response.exit(500, "Failed to read response body: " .. (err or "unknown error"))
  end

  kong.response.set_raw_body(body)

  -- Log the response body for debugging
  kong.log.debug("Response body: " .. body)

  -- Terminate further plugin execution
  return kong.response.exit(res.status)
end

return UpstreamProxyHandler