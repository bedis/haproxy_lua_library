# haproxy_lua_library

A module to access HAProxy runtime API (stats socket) from Lua to execute commands which have no bindings in Lua yet
This module is intended to be called from a Lua script running **inside** haproxy.

## Quick start
Copy the haproxy.lua file in your Lua path or use the haproxy global directive `lua-prepend-path` to load it properly form your own Lua code.

Example, if your lua scripts are installed in a specific path:

    lua-prepend-path /my/path/lua/?.lua

In your Lua script, simply load the module like this:

    haproxy = require("haproxy")

Then, use the New() function to create a new instance:

    -- HAProxy handler
    local myHAProxy = {
      addr   = "127.0.0.1",
      port   = "1025",
    }
    local h, err = haproxy:New(myHAProxy)
    if err ~= nil then
      print(err)
      return
    end

the New function expect a Lua table with the following optional values:

| Parameter | type    |  description                                  | default value |
|-----------|---------|-----------------------------------------------|---------------|
| addr      | string  | IP address where the runtime API is listening | 127.0.0.1     |
| port      | string  | Port where the runtime API is listening       | 1023          |
| timeout   | number  | runtime API timeout, in seconds               | 600           |
| debug     | boolean | enable debugging messages, boolean            | false         |

If everything went well, you can enjoy the methods listed below.

## Methods

### New()

Create a module object from scratch or optionally based on object passed

* **@param** o: Optional object settings
* **@return**: Module object and or nil and error string

The following object members are accepted:
* **addr**: Optional path to HAProxy runtime API IP address - defaults to 127.0.0.1
* **port**: Optional path to HAProxy runtime API TCP port - defaults to 1023
* **timeout**: Optional CLI timeout - defaults to 600
* **debug**: Optional enable verbose messages - defaults to false

### runCmd()

run a custom command

* **@param**  cmd: the command to run
* **@return** : command output or nil and an error message

### info()

return HAProxy process information (aka `show info`)

* **@return**: a Lua table with haproxy process information indexed by information name or nil and an error message

### certList()

return a list of SSL/TLS certificate names currently configured in HAProxy

* **@return**: a Lua table indexed by certificate names or nil and an error message

### certInfo(certName)

return information for a given certificate

* **@param** certName: name of the certificate to get info from (usually issued from certList above)
* **@return** certificate information as a Lua indexed table or nil and an error message

### certUpdate (certName, pem)

Update a SSL / TLS certificate

* **@param** certName: name of the certificate to update (usually issued from certList above)
* **@param** pem: pem file format (concatenation of public certificate, intermediaries if any and private key)
* **@return** nil or an error message if update could not happen
