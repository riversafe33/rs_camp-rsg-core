local _strblob = string.blob or function(length)
    return string.rep("\0", math.max(40 + 1, length))
end

DataView = {
    EndBig = ">",
    EndLittle = "<",
    Types = {
        Int8 = { code = "i1", size = 1 },
        Uint8 = { code = "I1", size = 1 },
        Int16 = { code = "i2", size = 2 },
        Uint16 = { code = "I2", size = 2 },
        Int32 = { code = "i4", size = 4 },
        Uint32 = { code = "I4", size = 4 },
        Int64 = { code = "i8", size = 8 },
        Uint64 = { code = "I8", size = 8 },

        LuaInt = { code = "j", size = 8 }, 
        UluaInt = { code = "J", size = 8 }, 
        LuaNum = { code = "n", size = 8}, 
        Float32 = { code = "f", size = 4 },
        Float64 = { code = "d", size = 8 }, 
        String = { code = "z", size = -1, }, 
    },

    FixedTypes = {
        String = { code = "c", size = -1, },
        Int = { code = "i", size = -1, },
        Uint = { code = "I", size = -1, },
    },
}
DataView.__index = DataView
local function _ib(o, l, t) return ((t.size < 0 and true) or (o + (t.size - 1) <= l)) end
local function _ef(big) return (big and DataView.EndBig) or DataView.EndLittle end
local SetFixed = nil
function DataView.ArrayBuffer(length)
    return setmetatable({
        offset = 1, length = length, blob = _strblob(length)
    }, DataView)
end
function DataView.Wrap(blob)
    return setmetatable({
        offset = 1, blob = blob, length = blob:len(),
    }, DataView)
end
function DataView:Buffer() return self.blob end
function DataView:ByteLength() return self.length end
function DataView:ByteOffset() return self.offset end
function DataView:SubView(offset)
    return setmetatable({
        offset = offset, blob = self.blob, length = self.length,
    }, DataView)
end
for label,datatype in pairs(DataView.Types) do
    DataView["Get" .. label] = function(self, offset, endian)
        local o = self.offset + offset
        if _ib(o, self.length, datatype) then
            local v,_ = string.unpack(_ef(endian) .. datatype.code, self.blob, o)
            return v
        end
        return nil
    end

    DataView["Set" .. label] = function(self, offset, value, endian)
        local o = self.offset + offset
        if _ib(o, self.length, datatype) then
            return SetFixed(self, o, value, _ef(endian) .. datatype.code)
        end
        return self
    end
    if datatype.size >= 0 and string.packsize(datatype.code) ~= datatype.size then
        local msg = "Pack size of %s (%d) does not match cached length: (%d)"
        error(msg:format(label, string.packsize(fmt[#fmt]), datatype.size))
        return nil
    end
end
for label,datatype in pairs(DataView.FixedTypes) do
    DataView["GetFixed" .. label] = function(self, offset, typelen, endian)
        local o = self.offset + offset
        if o + (typelen - 1) <= self.length then
            local code = _ef(endian) .. "c" .. tostring(typelen)
            local v,_ = string.unpack(code, self.blob, o)
            return v
        end
        return nil
    end
    DataView["SetFixed" .. label] = function(self, offset, typelen, value, endian)
        local o = self.offset + offset
        if o + (typelen - 1) <= self.length then
            local code = _ef(endian) .. "c" .. tostring(typelen)
            return SetFixed(self, o, value, code)
        end
        return self
    end
end

SetFixed = function(self, offset, value, code)
    local fmt = { }
    local values = { }
    if self.offset < offset then
        local size = offset - self.offset
        fmt[#fmt + 1] = "c" .. tostring(size)
        values[#values + 1] = self.blob:sub(self.offset, size)
    end
    fmt[#fmt + 1] = code
    values[#values + 1] = value
    local ps = string.packsize(fmt[#fmt])
    if (offset + ps) <= self.length then
        local newoff = offset + ps
        local size = self.length - newoff + 1

        fmt[#fmt + 1] = "c" .. tostring(size)
        values[#values + 1] = self.blob:sub(newoff, self.length)
    end
    self.blob = string.pack(table.concat(fmt, ""), table.unpack(values))
    self.length = self.blob:len()
    return self
end

DataStream = { }
DataStream.__index = DataStream

function DataStream.New(view)
    return setmetatable({ view = view, offset = 0, }, DataStream)
end

for label,datatype in pairs(DataView.Types) do
    DataStream[label] = function(self, endian, align)
        local o = self.offset + self.view.offset
        if not _ib(o, self.view.length, datatype) then
            return nil
        end
        local v,no = string.unpack(_ef(endian) .. datatype.code, self.view:Buffer(), o)
        if align then
            self.offset = self.offset + math.max(no - o, align)
        else
            self.offset = no - self.view.offset
        end
        return v
    end
end

function LoadTexture(dict)
    if Citizen.InvokeNative(0x7332461FC59EB7EC, dict) then
        RequestStreamedTextureDict(dict, true)
        while not HasStreamedTextureDictLoaded(dict) do
            Wait(1)
        end
        return true
    else
        return false
    end
end


function bigInt(text)
    local string1 =  DataView.ArrayBuffer(16)
    string1:SetInt64(0,text)
    return string1:GetInt64(0)
end



exports("ShowAdvancedRightNotification",function(_text, _dict, icon, text_color, duration, quality)
    local text = CreateVarString(10, "LITERAL_STRING", _text)
    local dict = CreateVarString(10, "LITERAL_STRING", _dict)
    local sdict = CreateVarString(10, "LITERAL_STRING", "Transaction_Feed_Sounds")
    local sound = CreateVarString(10, "LITERAL_STRING", "Transaction_Positive")

    local struct1 = DataView.ArrayBuffer(8*7)
    struct1:SetInt32(8*0,duration)
    struct1:SetInt64(8*1,bigInt(sdict))
    struct1:SetInt64(8*2,bigInt(sound))

    local struct2 = DataView.ArrayBuffer(8*10)
    struct2:SetInt64(8*1,bigInt(text))
    struct2:SetInt64(8*2,bigInt(dict))
    struct2:SetInt64(8*3,bigInt(GetHashKey(icon)))
    struct2:SetInt64(8*5,bigInt(GetHashKey(text_color or "COLOR_ENEMY")))
    --struct2:SetInt32(8*6,quality or 1)

    Citizen.InvokeNative(0xB249EBCB30DD88E0,struct1:Buffer(),struct2:Buffer(),1)
end)

RegisterNetEvent('paintwall:NotifyLeft')
AddEventHandler('paintwall:NotifyLeft', function(firsttext, secondtext, dict, icon, duration)
    local _dict = dict
    local _icon = icon
    if not LoadTexture(_dict) then
        _dict = "generic_textures"
        LoadTexture(_dict)
        _icon = "tick"
    end
    exports.dodi_paintwall:ShowAdvancedNotification(tostring(firsttext), tostring(secondtext), tostring(_dict), tostring(_icon), tonumber(duration))
end)

RegisterNetEvent('paintwall:ShowTopNotification')
AddEventHandler('paintwall:ShowTopNotification',
                function(tittle, subtitle, duration)
    exports.dodi_paintwall:ShowTopNotification(tostring(tittle),
                                                    tostring(subtitle),
                                                    tonumber(duration))
end)

RegisterNetEvent('paintwall:ShowObjective')
AddEventHandler('paintwall:ShowObjective', function(text, duration)
    exports.dodi_paintwall:ShowObjective(tostring(text), tonumber(duration))
end)

exports("ShowTopNotification", function(title, subtext, duration)
    local struct1 = DataView.ArrayBuffer(8 * 7)
    struct1:SetInt32(8 * 0, duration)
    -- struct1:SetInt64(8*1,bigInt(sound_dict))
    -- struct1:SetInt64(8*2,bigInt(sound))
    local string1 = CreateVarString(10, "LITERAL_STRING", title)
    local string2 = CreateVarString(10, "LITERAL_STRING", subtext)
    local struct2 = DataView.ArrayBuffer(8 * 7)
    struct2:SetInt64(8 * 1, bigInt(string1))
    struct2:SetInt64(8 * 2, bigInt(string2))
    Citizen.InvokeNative(0xA6F4216AB10EB08E, struct1:Buffer(), struct2:Buffer(),
                         1, 1)
end)


exports("ShowObjective",function(text, duration)
    Citizen.InvokeNative("0xDD1232B332CBB9E7", 3, 1, 0)
    local string1 = CreateVarString(10, "LITERAL_STRING", text)
    local struct1 = DataView.ArrayBuffer(8*7)
    local struct2 = DataView.ArrayBuffer(8*3)
    struct1:SetInt32(8*0,duration)
    --struct1:SetInt64(8*1,bigInt(sound_dict))
    --struct1:SetInt64(8*2,bigInt(sound))
    struct2:SetInt64(8*1,bigInt(string1))

    Citizen.InvokeNative(0xCEDBF17EFCC0E4A4,struct1:Buffer(),struct2:Buffer(),1)
end)

exports("ShowAdvancedNotification",function(title, subTitle, dict, icon, duration, color)
    local struct1 = DataView.ArrayBuffer(8*7)
    local struct2 = DataView.ArrayBuffer(8*8)
    struct1:SetInt32(8*0,duration)
    --struct1:SetInt64(8*1,bigInt(sound_dict))
    --struct1:SetInt64(8*2,bigInt(sound))
    local string1 = CreateVarString(10, "LITERAL_STRING", title)
    local string2 = CreateVarString(10, "LITERAL_STRING", subTitle)
    struct2:SetInt64(8*1,bigInt(string1))
    struct2:SetInt64(8*2,bigInt(string2))
    struct2:SetInt32(8*3,0)
    struct2:SetInt64(8*4,bigInt(GetHashKey(dict)))
    struct2:SetInt64(8*5,bigInt(GetHashKey(icon)))
    struct2:SetInt64(8*6,bigInt(GetHashKey(color or "COLOR_WHITE")))
    Citizen.InvokeNative(0x26E87218390E6729,struct1:Buffer(),struct2:Buffer(),1,1)
end)

