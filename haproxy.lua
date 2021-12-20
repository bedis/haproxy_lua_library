-- MIT License
-- 
-- Copyright (c) 2021 Baptiste Assmann, https://github.com/bedis/haproxy_lua_library
-- 
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
-- 
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
-- 
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.


-- Lua module to execute commands on a runtime API
-- It takes care of the connection management and read / write operations.
--
-- This module is supposed to run inside an HAProxy process

local string = require('string')

local _M = {
	version = "0.0.1",
}


----------------------
-- helper functions --
----------------------


-- Turn a string into a table based on a given delimiter
--
-- @param s              the string
-- @param delimiter      the delimiter, can be a string
--
-- @return               a table
--
-- taken from https://www.codegrepper.com/code-examples/lua/lua+split+string+into+table
function Split(s, delimiter)
	local result = {};
	for match in (s..delimiter):gmatch("(.-)"..delimiter) do
		table.insert(result, match);
	end
	return result;
end


-- check if a severity return code is an error or not
--
-- @param sev        severity number
--
-- @return           true if sev code is an error, false if not and nil
--                   when sev is not a number, optional sev parsing error message
function severityIsError(sev)
	-- check sev type and if not number, tries to convert it
	-- or return an error
	if type(sev) ~= 'number' then
		sev = tonumber(sev)
		if sev == nil then
			return nil, "sev parameter is not a number"
		end
	end

	return sev < 5, false
end


----------------------
-- global variables --
----------------------

-- HAProxy severity as string
-- Check src/log.c log_levels variable
-- 
-- NOTE: HAProxy severity starts at index 0 while in Lua, table index starts at 1
local severity = { "emerg", "alert", "crit", "err", "warning", "notice", "info", "debug" }

-- numer of bytes consumed by severity code: '[c]: ' => 6
local severityCodeOffset = 6


------------------------------
-- HAProxy library function --
------------------------------

-- Create a module object from scratch or optionally based on object passed
--
-- The following object members are accepted:
-- addr          Optional path to HAProxy runtime API IP address
--               - defaults to 127.0.0.1
-- port          Optional path to HAProxy runtime API TCP port
--               - defaults to 1023
-- timeout       Optional CLI timeout
-- debug         Optional enable verbose messages
--               - defaults to false
--
-- @param o      Optional object settings
--
-- @return       Module object and or nil and error string
function _M:New(o)
	local o = o or {}

	-- select the right address, port and timeout
	o.addr    = o.addr or '127.0.0.1'
	o.port    = o.port or '1023'
	o.timeout = tonumber(o.timeout) or 600
	o.debug   = o.debug or false

	-- sanitization checks
	if o.addr == nil then
		return nil, "addr missing"
	end
	if o.port == nil then
		return nil, "port missing"
	end

	-- save the set timeout command, so no need to rebuid it at runtime
	o.settimeout = 'set timeout cli ' .. tostring(o.timeout)  ..'\n'

	setmetatable(o, self)
	self.__index = self

	-- return table
	return o
end


-- set connection to HAProxy and save the socket
--
-- @param self         an HAProxy module object
--
-- @return             nil if succesful or connection error message
local function connectHAProxy(self)
	local tcp, err

	-- check if socket is still connected
	if self.socket ~= nil then
		local nb, err = self.socket:send(self.settimeout)
		-- the connection is still active
		if nb > 0 then
			self.socket:receive('*l')
			return nil
		end

		-- connection clean up
		self.socket:close()
		self.socket = nil
	end

	self.socket = core.tcp()
	self.socket:settimeout(self.timeout)

	tcp, err = connect(self)
	
	if tcp == nil then
		return err
	end

	-- enable interactive mode and clear the read buffer
	self.socket:send('prompt\n')
	local line, status = self.socket:receive('*l')

	return nil
end


-- get connected to haproxy
--
-- @param self         HAProxy Module object
--
-- @return             connection error message or nil
function connect (self)
	if self.socket == nil then
		return 'self.socket is nil'
	end

	return self.socket:connect(self.addr, self.port)
end


-- execute a command on an HAProxy runtime API
--
-- @param self         an HAProxy Module object
-- @param cmd          the command to run
--
-- @return             a table containing command output or nil in case of error,
--                     a severity code when available or nil in case of error,
--                     a string with an error message or nil if no error
local function callHAProxy(self, cmd)
	-- response body
	local output = {}
	local err
	local status = nil
	local lineid = 0
	local severityCode = nil

	if cmd == nil then
		return nil, nil, "cmd required"
	end

	err = connectHAProxy(self)
	if err ~= nil then
		return nil, nil, err
	end

	if not self.socket:send(cmd) then
                return nil, nil, "error when sending command on HAProxy runtime API"
        end

	-- read all the lines
	while status == nil do
		local line, status = self.socket:receive('*l')

		if string.len(line) == 0 then
			break
		end
		if status ~= nil and string.match(status, "closed") then
			self.socket:close()
			self.socket = nil
			break
		end
		if string.len(line) > 0 then
			if lineid == 0 then
				if string.match(line, '^%[[0-7]%]: ') then
					severityCode = tonumber(string.sub(line, 2, 2))
					if severityIsError(severityCode) then
						return nil, severityCode, string.sub(line, severityCodeOffset)
					end
				end
			end
			local t = Split(line, ": ")
			if t[2] == nil then
				t[2] = ""
			end
			output[t[1]] = t[2]
			lineid = 1
		end
	end

	return output, severityCode, nil
end


-- run custom command
--
-- @param cmd           the command to run
--
-- @return             command output and error message or nil
function _M:runCmd (cmd)
	local output
	local severityCode
	local err

	output, severityCode, err =  callHAProxy(self, 'set severity-output number; ' .. cmd .. '\n')
	if self.debug and severityCode == nil then
		core.Debug("[haproxy.lua DEBUG] Command '" .. string.sub(cmd, 0, 32) .. "...' does not return a severity code")
	end

	-- exploit severityCode here if needed or may need to forward it back
	-- to function caller

	return output, err
end


-- get HAProxy process info
--
-- @return             information data and error message or nil
function _M:info ()
	local t, err

	t, err = self:runCmd('show info')
	if t ~= nil then
		-- remove useless lines from the list
		t["> Name"] = nil
		t["> "] = nil
	end

	return t, err
end


-- get list of SSL certificates loaded
--
-- @return             list of certificate and error message or nil
function _M:certList ()
	local t, err

	t, err = self:runCmd('show ssl cert')
	if t ~= nil then
		-- remove useless lines from the list
		t["> # filename"] = nil
		t["> "] = nil
	end

	return t, err
end


-- get information about SSL certificate
--
-- @param certName     name of the certificate
--
-- @return             information data and error message or nil
function _M:certInfo (certName)
	local t, err

	t, err = self:runCmd('show ssl cert ' .. certName)
	if t ~= nil then
		-- remove useless lines from the list
		t["> Filename"] = nil
		t["> "] = nil
	end

	return t, err
end


-- update ssl certificate
--
-- @param certName     name of the certificate
-- @param pem          pem file content
--
-- @return             error message or nil
function _M:certUpdate (certName, pem)
	local data, err

	if pem == nil then
		return "pem required"
	end

	-- need to send command + payload. The double '\n' at the end is expected
	data, err = self:runCmd('set ssl cert ' .. certName .. ' <<\n' .. pem .. '\n')
	if err ~= nil then
		self:runCmd('abort ssl cert ' .. certName .. '\n')
		return nil, err
	end

	-- now we can commit transaction
	_, err = self:runCmd('commit ssl cert '.. certName)
	return err
end


-- return module table
return _M
