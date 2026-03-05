local file_path, tag_name = arg[1], arg[2]
local f = io.open(file_path, "r")
if not f then os.exit(1) end

local conf = {}
local valid, line_count = false, 0
for line in f:lines() do
    line = line:gsub("\r", "")
    line_count = line_count + 1
    if line_count <= 5 and line:match("%[Interface%]") then valid = true end
    local key, val = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if key and val then conf[key:lower()] = val end
end
f:close()
if not valid then os.exit(1) end

local function split_to_array(str, enforce_cidr)
    if not str then return "[]" end
    local res = {}
    for s in str:gmatch("[^,]+") do
        local clean = s:match("^%s*(.-)%s*$")
        if enforce_cidr and not clean:match("/") then
            clean = clean .. (clean:match(":") and "/128" or "/32")
        end
        table.insert(res, '"' .. clean .. '"')
    end
    return "[" .. table.concat(res, ", ") .. "]"
end

local host, port = "", 0
if conf["endpoint"] then
    local h, p = conf["endpoint"]:match("^%[(.+)%]:(%d+)$")
    if not h then h, p = conf["endpoint"]:match("^([^:]+):(%d+)$") end
    host, port = h or conf["endpoint"], tonumber(p) or 0
end

local is_awg = conf["jc"] ~= nil
local json = string.format([[
{
  "type": "%s",
  "tag": "%s",
  "address": %s,
  "private_key": "%s",
  "mtu": %d,
  "peers": [{
      "address": "%s", "port": %d, "public_key": "%s", "allowed_ips": %s
  }]
]], is_awg and "awg" or "wireguard", tag_name, split_to_array(conf["address"], true),
    conf["privatekey"] or "", tonumber(conf["mtu"]) or 1280, host, port, 
    conf["publickey"] or "", split_to_array(conf["allowedips"], true))

if is_awg then
    json = json .. string.format([[
  ,"s1": %d, "s2": %d, "jc": %d, "jmin": %d, "jmax": %d,
  "h1": "%s", "h2": "%s", "h3": "%s", "h4": "%s"]],
    tonumber(conf["s1"]) or 0, tonumber(conf["s2"]) or 0, tonumber(conf["jc"]) or 0,
    tonumber(conf["jmin"]) or 0, tonumber(conf["jmax"]) or 0,
    conf["h1"] or "1", conf["h2"] or "2", conf["h3"] or "3", conf["h4"] or "4")
    if conf["i1"] then json = json .. string.format(',"i1": "%s"', conf["i1"]) end
    if conf["i2"] then json = json .. string.format(',"i2": "%s"', conf["i2"]) end
end
print(json .. "\n}")