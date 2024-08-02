local typedefs = require "kong.db.schema.typedefs"

return {
  name = "upstream-proxy",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { proxy_url = typedefs.url { required = true } },
          { upstream_url = typedefs.url { required = true } },
          { upstream_host = typedefs.host { required = true } },
        },
      },
    },
  },
}